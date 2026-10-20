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
fun overviewInventoryCost(owner:UserId,channels:List<CloudRecord>,assets:List<CloudRecord>,trades:List<CloudRecord>):BigInteger? {
    val activeChannels=channels.filter {it.ownedOverviewEnvelope(owner,CloudEntity.INVESTMENT_CHANNEL,true)}.map {it.id}.toSet()
    val activeAssets=assets.filter {it.ownedOverviewEnvelope(owner,CloudEntity.INVESTMENT_ASSET,true) && it.payload.investmentString("channel_id") in activeChannels}
    val byAsset=trades.filter {it.ownedOverviewEnvelope(owner,CloudEntity.INVESTMENT_TRADE,false)}.groupBy {it.payload.investmentString("asset_id")}
    var total=BigInteger.ZERO
    for(asset in activeAssets) {
        val candidates=byAsset[asset.id].orEmpty()
        // A corrupt calendar cannot establish which snapshot is current; hold the portfolio.
        if(candidates.any {runCatching {Instant.parse(it.payload.investmentString("occurred_at"));Instant.parse(it.payload.investmentString("created_at"))}.isFailure}) return null
        val latest=candidates.maxWithOrNull(compareBy<CloudRecord> {Instant.parse(it.payload.investmentString("occurred_at"))}
            .thenBy {Instant.parse(it.payload.investmentString("created_at"))}.thenBy {it.id.lowercase(Locale.ROOT)}) ?: continue
        val quantity=(latest.payload["position_quantity_after_decimal_string"] as? JsonPrimitive)?.takeIf {it.isString}?.content?.toBigDecimalOrNull() ?: return null
        if(quantity.signum()<=0) continue
        val cost=(latest.payload["position_cost_basis_after_minor"] as? JsonPrimitive)?.takeIf {!it.isString}?.longOrNull ?: return null
        total+=BigInteger.valueOf(maxOf(cost,0))
    }
    return total
}

/** Currency metadata is independent of wallet cash parsing; null holds an invalid existing dependency. */
fun overviewInventoryAccountingCurrency(owner:UserId,wallets:List<CloudRecord>,primaryCurrency:String):String? {
    val systemId=investmentSystemWalletId(owner)
    val owned=wallets.filter {it.id==systemId && it.ownedOverviewEnvelope(owner,CloudEntity.LEDGER_WALLET,false)}
    if(owned.isEmpty()) return primaryCurrency
    val wallet=owned.singleOrNull() ?: return null
    val value=(wallet.payload["currency_code"] as? JsonPrimitive)?.takeIf {it.isString}?.contentOrNull ?: return null
    return value.trim().uppercase(Locale.ROOT).takeIf {it.matches(Regex("[A-Z]{3}"))}
}

fun investmentSystemWalletId(owner:UserId):String {
    val normalized=UUID.fromString(owner.value).toString()
    val bytes=MessageDigest.getInstance("SHA-256").digest("com.mistia.wallet.system.investment-profit:$normalized".toByteArray(Charsets.UTF_8)).copyOf(16)
    bytes[6]=((bytes[6].toInt() and 15) or 80).toByte();bytes[8]=((bytes[8].toInt() and 63) or 128).toByte()
    val buffer=ByteBuffer.wrap(bytes);return UUID(buffer.long,buffer.long).toString()
}

private fun CloudRecord.ownedOverviewEnvelope(owner:UserId,entity:CloudEntity,active:Boolean):Boolean {
    if(this.entity!=entity.table || ownerUserId!=owner.value || deletedAt!=null || payload.investmentString("id")!=id || payload.investmentString("user_id")!=owner.value) return false
    if(payload["deleted_at"]!=null && payload["deleted_at"]!=JsonNull) return false
    if(!runCatching {UUID.fromString(id).toString()==id.lowercase(Locale.ROOT)}.getOrDefault(false)) return false
    if(active && payload["is_archived"]!=null && (payload["is_archived"] as? JsonPrimitive)?.booleanOrNull!=false) return false
    return true
}
private fun JsonObject.investmentString(key:String)=(get(key) as? JsonPrimitive)?.contentOrNull
