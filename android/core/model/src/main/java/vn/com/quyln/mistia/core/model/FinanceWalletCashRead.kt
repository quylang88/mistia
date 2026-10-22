package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import kotlinx.serialization.json.*

/** Read only consumed cash legs. These partial typed snapshots must never be persisted. */
fun financeWalletBalancesRaw(owner:UserId,records:List<CloudRecord>,wallets:List<CloudRecord>,walletIds:Set<String>?=null):Map<String,BigInteger>? {
    val acceptedWallets=mutableListOf<LedgerWalletRecord>()
    for(raw in wallets) {
        if(!raw.financeRawIdentity(owner,CloudEntity.LEDGER_WALLET)) continue
        val deleted=raw.financeRawDeleted();val archived=raw.payload.financeRawArchived()
        val kind=raw.payload.financeRawString("kind_raw_value")?.let(WalletKind::fromWireValue)
        if(deleted==true || archived==true) continue
        if(kind==WalletKind.CREDIT_CARD) {
            // Only its currency can be consumed by an incoming legacy pair, never its opening or liability.
            if(deleted==false && archived==false) acceptedWallets+=LedgerWalletRecord.fromCloudRecord(raw.copy(payload=JsonObject(raw.payload+("opening_balance_minor" to JsonPrimitive(0)))))
            continue
        }
        if(walletIds!=null && financeRawUuid(raw.id) !in walletIds) {
            if(deleted==false && archived==false) acceptedWallets+=LedgerWalletRecord.fromCloudRecord(raw.copy(payload=JsonObject(raw.payload+("opening_balance_minor" to JsonPrimitive(0)))))
            continue
        }
        if(deleted==null || archived==null || kind==null) return null
        raw.payload.financeRawLong("opening_balance_minor") ?: return null
        acceptedWallets+=LedgerWalletRecord.fromCloudRecord(raw)
    }
    val ids=acceptedWallets.filter {it.kind!=WalletKind.CREDIT_CARD && (walletIds==null || it.id in walletIds)}.map {it.id}.toSet()
    val acceptedRecords=mutableListOf<LedgerTransactionRecord>()
    for(raw in records) {
        if(!raw.financeRawIdentity(owner,CloudEntity.LEDGER_TRANSACTION)) continue
        val deleted=raw.financeRawDeleted();val archived=raw.payload.financeRawArchived()
        val status=raw.payload.financeRawString("entry_status_raw_value")?.let(TransactionEntryStatus::fromWireValue)
        if(deleted==true || archived==true || status==TransactionEntryStatus.DRAFT) continue
        val source=raw.payload.financeRawReference("source_wallet_id");val destination=raw.payload.financeRawReference("destination_wallet_id")
        val sourcePossible=source.mayReferTo(ids);val destinationPossible=destination.mayReferTo(ids)
        if(!sourcePossible && !destinationPossible) continue
        val kind=raw.payload.financeRawString("primary_kind_raw_value")?.let(TransactionPrimaryKind::fromWireValue) ?: return null
        if(kind!=TransactionPrimaryKind.TRANSFER && !sourcePossible) continue
        val subtype=if(kind==TransactionPrimaryKind.TRANSFER) {
            val value=raw.payload["transfer_subtype_raw_value"]
            if(value==null || value==JsonNull) continue
            raw.payload.financeRawString("transfer_subtype_raw_value")?.let(TransactionTransferSubtype::fromWireValue) ?: return null
        } else null
        if(subtype!=TransactionTransferSubtype.INTERNAL_TRANSFER && !sourcePossible) continue
        val role=raw.payload.financeRawString("settlement_role_raw_value")
        if(subtype==TransactionTransferSubtype.DEBT && role in setOf("sharedExpenseReceivable","sharedExpensePayable")) continue
        val intent=if(subtype==TransactionTransferSubtype.DEBT) {
            val value=raw.payload["debt_intent_raw_value"]
            if(value==null || value==JsonNull) continue
            raw.payload.financeRawString("debt_intent_raw_value")?.let(TransactionDebtIntent::fromWireValue) ?: return null
        } else null
        if(deleted==null || archived==null || status==null) return null
        if(sourcePossible && !source.readable) return null
        if(subtype in setOf(TransactionTransferSubtype.INTERNAL_TRANSFER,TransactionTransferSubtype.FAMILY_TRANSFER) && !destination.readable) return null
        if(subtype==TransactionTransferSubtype.DEBT && raw.payload["settlement_role_raw_value"]!=null && raw.payload["settlement_role_raw_value"]!=JsonNull && role==null) return null
        val resale=subtype==TransactionTransferSubtype.DEBT && intent==TransactionDebtIntent.LEND && role=="resaleReceivable"
        val incoming=subtype==TransactionTransferSubtype.INTERNAL_TRANSFER && destination.id in ids
        val explicitIncoming=raw.payload["destination_amount_minor"].let {it!=null && it!=JsonNull}
        val destinationMinor=if(incoming && explicitIncoming) raw.payload.financeRawLong("destination_amount_minor") ?: return null else null
        val amount=if(!resale && (source.id in ids || (incoming && !explicitIncoming))) raw.payload.financeRawLong("amount_minor") ?: return null else 0L
        val sourceCurrency=raw.payload["source_currency_code"]
        if(incoming && !explicitIncoming && amount!=0L && sourceCurrency!=null && sourceCurrency!=JsonNull && raw.payload.financeRawString("source_currency_code")==null) return null
        val expense=if(resale) {
            val value=raw.payload["reporting_expense_minor"]
            if(value==null || value==JsonNull) null else raw.payload.financeRawLong("reporting_expense_minor") ?: return null
        } else null
        // Noncash fields are deliberately absent. An unused malformed value is never defaulted into a consumed leg.
        val cashPayload=buildJsonObject {
            put("id",financeRawUuid(raw.id)!!);put("user_id",owner.value);put("primary_kind_raw_value",kind.wireValue);put("entry_status_raw_value","posted");put("amount_minor",amount)
            subtype?.let {put("transfer_subtype_raw_value",it.wireValue)};intent?.let {put("debt_intent_raw_value",it.wireValue)};role?.let {put("settlement_role_raw_value",it)}
            source.id?.let {put("source_wallet_id",it)};destination.id?.let {put("destination_wallet_id",it)}
            destinationMinor?.let {put("destination_amount_minor",it)};expense?.let {put("reporting_expense_minor",it)}
            raw.payload.financeRawString("source_currency_code")?.let {put("source_currency_code",it)}
        }
        acceptedRecords+=LedgerTransactionRecord.fromCloudRecord(raw.copy(payload=cashPayload,deletedAt=null))
    }
    return financeWalletBalancesExact(owner,acceptedWallets,acceptedRecords,walletIds)
}

fun financeWalletCashTotalRaw(owner:UserId,records:List<CloudRecord>,wallets:List<CloudRecord>,currency:String,
    rates:List<ExchangeRateSnapshot> = emptyList(),inventoryCost:BigInteger?=BigInteger.ZERO,inventoryCurrency:String?=currency):BigInteger? {
    val balances=financeWalletBalancesRaw(owner,records,wallets) ?: return null
    val cost=inventoryCost ?: return null
    var total=if(cost.signum()==0) BigInteger.ZERO else overviewMoneyMinorExact(cost,inventoryCurrency ?: return null,currency,rates) ?: return null
    for((id,amount) in balances) {
        val wallet=wallets.last {financeRawUuid(it.id)==id && it.financeRawIdentity(owner,CloudEntity.LEDGER_WALLET)}
        total+=overviewMoneyMinorExact(amount,wallet.payload.financeRawString("currency_code").orEmpty(),currency,rates) ?: return null
    }
    return total
}
