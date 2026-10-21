package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.time.Instant
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.json.*

/** Read-only exact report; financial mutations keep their existing validation/balance contracts. */
fun overviewTotalAssets(owner:UserId,wallets:List<LedgerWalletRecord>,records:List<LedgerTransactionRecord>,currency:String,
    rates:List<ExchangeRateSnapshot> = emptyList(),inventoryCost:BigInteger?=BigInteger.ZERO,inventoryCurrency:String?=currency):BigInteger? {
    val active=wallets.filter {it.ownerUserId==owner.value && it.deletedAt==null && !it.isArchived && it.kind!=null && it.kind!=WalletKind.CREDIT_CARD}
    val balances=active.associate {it.id to BigInteger.valueOf(it.openingBalanceMinor)}.toMutableMap()
    fun apply(id:String?,amount:Long,outgoing:Boolean) {
        val key=id ?: return
        val previous=balances[key] ?: return
        val delta=BigInteger.valueOf(amount)
        balances[key]=if(outgoing) previous-delta else previous+delta
    }
    for(record in records) {
        if(record.ownerUserId!=owner.value || record.deletedAt!=null || record.isArchived || record.entryStatus!=TransactionEntryStatus.POSTED) continue
        when(record.primaryKind) {
            TransactionPrimaryKind.EXPENSE -> apply(record.sourceWalletId,record.amountMinor,true)
            TransactionPrimaryKind.INCOME -> apply(record.sourceWalletId,record.amountMinor,false)
            TransactionPrimaryKind.TRANSFER -> when(record.transferSubtype) {
                TransactionTransferSubtype.INTERNAL_TRANSFER -> {
                    if(record.destinationWalletId in balances && record.destinationAmountMinor==null && record.amountMinor!=0L) {
                        val sourceWallet=wallets.firstOrNull {it.id==record.sourceWalletId && it.ownerUserId==owner.value && it.deletedAt==null && !it.isArchived}
                        val explicit=record.sourceCurrencyCode?.takeIf(String::isNotBlank)
                        val sourceCode=(explicit ?: sourceWallet?.currencyCode)?.overviewCurrencyCode()
                        val sourceWalletCode=sourceWallet?.currencyCode?.overviewCurrencyCode()
                        val destinationCode=active.last {it.id==record.destinationWalletId}.currencyCode.overviewCurrencyCode()
                        if(sourceCode==null || sourceCode!=destinationCode || (explicit!=null && sourceWalletCode!=null && sourceCode!=sourceWalletCode)) return null
                    }
                    apply(record.sourceWalletId,record.amountMinor,true)
                    apply(record.destinationWalletId,record.destinationAmountMinor ?: record.amountMinor,false)
                }
                TransactionTransferSubtype.FAMILY_TRANSFER -> apply(record.sourceWalletId,record.amountMinor,record.destinationWalletId!=null)
                TransactionTransferSubtype.DEBT -> {
                    if(record.settlementRoleWireValue in setOf("sharedExpenseReceivable","sharedExpensePayable")) continue
                    if(record.debtIntent==TransactionDebtIntent.LEND && record.settlementRoleWireValue=="resaleReceivable") {
                        apply(record.sourceWalletId,maxOf(record.reportingExpenseMinor ?: 0,0),true);continue
                    }
                    when(record.debtIntent) {
                        TransactionDebtIntent.LEND,TransactionDebtIntent.REPAY -> apply(record.sourceWalletId,record.amountMinor,true)
                        TransactionDebtIntent.COLLECT,TransactionDebtIntent.BORROW -> apply(record.sourceWalletId,record.amountMinor,false)
                        null -> Unit
                    }
                }
                null -> Unit
            }
            null -> Unit
        }
    }
    val cost=inventoryCost ?: return null
    var total=if(cost.signum()==0) BigInteger.ZERO else {
        val code=inventoryCurrency ?: return null
        overviewMoneyMinorExact(cost,code,currency,rates) ?: return null
    }
    for(wallet in active) total+=overviewMoneyMinorExact(balances.getValue(wallet.id),wallet.currencyCode,currency,rates) ?: return null
    return total
}

/** Current inventory position snapshots, not trade gross amounts or realized gains. */
fun overviewInventoryCost(owner:UserId,channels:List<CloudRecord>,assets:List<CloudRecord>,trades:List<CloudRecord>):BigInteger? =
    overviewInventoryCostRead(owner,channels,assets,trades,null,false)

/** Required accounting denomination is checked only for a nonzero current cost. */
fun overviewInventoryCostInCurrency(owner:UserId,channels:List<CloudRecord>,assets:List<CloudRecord>,trades:List<CloudRecord>,accountingCurrency:String?):BigInteger? =
    overviewInventoryCostRead(owner,channels,assets,trades,accountingCurrency,true)

private fun overviewInventoryCostRead(owner:UserId,channels:List<CloudRecord>,assets:List<CloudRecord>,trades:List<CloudRecord>,accountingCurrency:String?,checkCurrency:Boolean):BigInteger? {
    val possibleChannels=channels.filter {it.financeRawIdentity(owner,CloudEntity.INVESTMENT_CHANNEL,true) && it.financeRawDeleted()!=true && it.payload.financeRawArchived()!=true}.associateBy {financeRawUuid(it.id)}
    val possibleAssets=assets.filter {it.financeRawIdentity(owner,CloudEntity.INVESTMENT_ASSET,true) && it.financeRawDeleted()!=true && it.payload.financeRawArchived()!=true}
        .filter {it.payload.financeRawReference("channel_id").let {reference -> !reference.readable && possibleChannels.isNotEmpty() || reference.id in possibleChannels}}
    if(possibleAssets.isEmpty()) return BigInteger.ZERO
    val ownedTrades=trades.filter {it.financeRawIdentity(owner,CloudEntity.INVESTMENT_TRADE,true) && it.financeRawDeleted()!=true}
    if(ownedTrades.any {!it.payload.financeRawReference("asset_id").readable}) return null
    val byAsset=ownedTrades.groupBy {it.payload.financeRawReference("asset_id").id}
    var total=BigInteger.ZERO
    for(asset in possibleAssets) {
        val candidates=byAsset[financeRawUuid(asset.id)].orEmpty()
        if(candidates.isEmpty()) continue
        if(candidates.any {it.financeRawDeleted()==null}) return null
        // A corrupt calendar cannot establish which snapshot is current; hold the portfolio.
        if(candidates.any {runCatching {Instant.parse(it.payload.investmentString("occurred_at"));Instant.parse(it.payload.investmentString("created_at"))}.isFailure}) return null
        val latest=candidates.maxWithOrNull(compareBy<CloudRecord> {Instant.parse(it.payload.investmentString("occurred_at"))}
            .thenBy {Instant.parse(it.payload.investmentString("created_at"))}.thenBy {it.id.lowercase(Locale.ROOT)}) ?: continue
        val quantity=(latest.payload["position_quantity_after_decimal_string"] as? JsonPrimitive)?.takeIf {it.isString}?.content?.toBigDecimalOrNull() ?: return null
        if(quantity.signum()<=0) continue
        val channelRef=asset.payload.financeRawReference("channel_id")
        val channel=possibleChannels[channelRef.id]
        if(!channelRef.readable || channel==null || channel.financeRawDeleted()==null || channel.payload.financeRawArchived()==null ||
            asset.financeRawDeleted()==null || asset.payload.financeRawArchived()==null) return null
        val cost=(latest.payload["position_cost_basis_after_minor"] as? JsonPrimitive)?.takeIf {!it.isString}?.longOrNull ?: return null
        if(checkCurrency && cost>0) {
            val source=latest.payload.financeRawString("accounting_currency_code")?.investmentAccountingCode()
            if(source==null || accountingCurrency==null || source!=accountingCurrency) return null
        }
        total+=BigInteger.valueOf(maxOf(cost,0))
    }
    return total
}

/** Currency metadata is independent of wallet cash parsing; null holds an invalid existing dependency. */
fun overviewInventoryAccountingCurrency(owner:UserId,wallets:List<CloudRecord>,primaryCurrency:String):String? {
    val systemId=investmentSystemWalletId(owner)
    val owned=wallets.filter {financeRawUuid(it.id)==systemId && it.financeRawIdentity(owner,CloudEntity.LEDGER_WALLET,true) && it.financeRawDeleted()!=true}
    if(owned.isEmpty()) return primaryCurrency
    val wallet=owned.singleOrNull() ?: return null
    if(wallet.financeRawDeleted()==null) return null
    val value=(wallet.payload["currency_code"] as? JsonPrimitive)?.takeIf {it.isString}?.contentOrNull ?: return null
    return value.trim().uppercase(Locale.ROOT).takeIf {it.matches(Regex("[A-Z]{3}"))}
}

fun investmentSystemWalletId(owner:UserId):String {
    val normalized=UUID.fromString(owner.value).toString()
    val bytes=MessageDigest.getInstance("SHA-256").digest("com.mistia.wallet.system.investment-profit:$normalized".toByteArray(Charsets.UTF_8)).copyOf(16)
    bytes[6]=((bytes[6].toInt() and 15) or 80).toByte();bytes[8]=((bytes[8].toInt() and 63) or 128).toByte()
    val buffer=ByteBuffer.wrap(bytes);return UUID(buffer.long,buffer.long).toString()
}

private fun JsonObject.investmentString(key:String)=(get(key) as? JsonPrimitive)?.contentOrNull
