package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.time.Instant
import kotlinx.serialization.json.*

enum class InvestmentCashReconciliationError { INVALID_INPUT, INVALID_WALLET, UNREADABLE_SOURCE, STALE_RECORD, EXCEEDS_BALANCE, EVENT_CONFLICT, CONFIRMATION_REQUIRED }
class InvestmentCashReconciliationException(val reason:InvestmentCashReconciliationError):IllegalArgumentException(reason.name)
data class InvestmentCashReconciliationLocation(val wallet:LedgerWalletRecord,val bookedMinor:BigInteger,val actualMinor:BigInteger)
data class InvestmentCashReconciliationView(val system:LedgerWalletRecord,val linked:LedgerWalletRecord,val locations:List<InvestmentCashReconciliationLocation>)
data class InvestmentCashReconciliationTransfer(val eventId:String,val sourceWalletId:String,val amountMinor:Long)
data class InvestmentCashReconciliationRequest(val expected:InvestmentCashReconciliationView,val transfers:List<InvestmentCashReconciliationTransfer>,
    val occurredAt:String,val createdAt:String,val ledgerTitle:String,val confirmedRealTransfer:Boolean)
data class InvestmentCashReconciliationPlan(val mutations:List<Pair<CloudRecord,PendingMutation>>)

private fun reconciliationFail(reason:InvestmentCashReconciliationError=InvestmentCashReconciliationError.UNREADABLE_SOURCE):Nothing=throw InvestmentCashReconciliationException(reason)

fun readInvestmentCashReconciliation(snapshot:InvestmentCashReadSnapshot):InvestmentCashReconciliationView {
    try{snapshot.requireScoped()}catch(_:Exception){reconciliationFail()}
    snapshot.rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.financeRawDeleted(true)!=true && it.payload.financePresent("cash_bucket_raw_value")}.forEach{raw->
        val p=raw.payload
        if(raw.financeRawDeleted(true)!=false || p.financeRawString("role_raw_value") !in setOf("funding","capitalReturn","realizedProfit","transferOut","transferIn","cashAccrual","cashTransfer","cashConsumption","cashReconciliation","cashCorrection") ||
            p.financeRawString("cash_origin_raw_value") !in setOf("manual","derived") ||
            listOf("event_id","wallet_id","ledger_transaction_id").any{p.financeRawReference(it).let{ref->!ref.readable || ref.id==null}} ||
            runCatching{Instant.parse(p.financeRawString("occurred_at"));Instant.parse(p.financeRawString("created_at"))}.isFailure)reconciliationFail()
    }
    val walletView=try{investmentLinkedWalletView(snapshot.walletSnapshot())}catch(_:Exception){reconciliationFail(InvestmentCashReconciliationError.INVALID_WALLET)}
    val system=walletView.system
    val linked=walletView.linkedWallet?.takeIf{linked->walletView.eligibleWallets.any{it.id==linked.id}} ?: reconciliationFail(InvestmentCashReconciliationError.INVALID_WALLET)
    val allocation=try{investmentCashAllocation(snapshot.walletSnapshot(),system.currencyCode)}catch(_:Exception){reconciliationFail()}
    val locations=allocation.locations.filter{it.walletId!=linked.id && it.bookedMinor.signum()>0}.mapNotNull{location ->
        val wallet=walletView.eligibleWallets.singleOrNull{it.id==location.walletId} ?: return@mapNotNull null
        if(location.currencyCode!=wallet.currencyCode || location.originalBookedMinor!=location.bookedMinor)reconciliationFail()
        wallet to location.bookedMinor
    }
    val balances=financeWalletBalancesRaw(snapshot.owner,snapshot.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},
        snapshot.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table},locations.map{it.first.id}.toSet()) ?: reconciliationFail()
    return InvestmentCashReconciliationView(system,linked,locations.map{(wallet,booked)->InvestmentCashReconciliationLocation(wallet,booked,balances[wallet.id] ?: reconciliationFail())}.sortedBy{it.wallet.id})
}

fun planInvestmentCashReconciliation(snapshot:InvestmentCashReadSnapshot,request:InvestmentCashReconciliationRequest,deviceId:String,now:String):InvestmentCashReconciliationPlan {
    fun invalid():Nothing=reconciliationFail(InvestmentCashReconciliationError.INVALID_INPUT)
    fun identity(value:String){if(financeRawUuid(value)!=value)invalid()}
    fun instant(value:String)=runCatching{Instant.parse(value)}.getOrElse{invalid()}
    identity(deviceId);instant(now);instant(request.createdAt);instant(request.occurredAt)
    if(!request.confirmedRealTransfer)reconciliationFail(InvestmentCashReconciliationError.CONFIRMATION_REQUIRED)
    if(request.transfers.isEmpty() || request.ledgerTitle.isBlank() || request.transfers.any{it.amountMinor<=0} ||
        request.transfers.map{it.eventId}.distinct().size!=request.transfers.size || request.transfers.map{it.sourceWalletId}.distinct().size!=request.transfers.size)invalid()
    try{snapshot.requireScoped()}catch(_:Exception){reconciliationFail()}
    val expected=request.expected;val owner=snapshot.owner
    val code=investmentAssetCurrency(expected.system.currencyCode) ?: invalid()
    if(expected.system.id!=investmentSystemWalletId(owner) || expected.system.ownerUserId!=owner.value || expected.system.kind!=WalletKind.INVESTMENT ||
        expected.system.systemPurposeRawValue!="investmentProfit" || expected.system.investmentLinkedWalletId!=expected.linked.id ||
        expected.linked.ownerUserId!=owner.value || expected.linked.kind in setOf(null,WalletKind.CREDIT_CARD,WalletKind.INVESTMENT) ||
        expected.linked.currencyCode!=code || expected.linked.deletedAt!=null || expected.linked.isArchived)invalid()
    val wallets=snapshot.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table}
    fun requireWallet(expectedWallet:LedgerWalletRecord) {
        identity(expectedWallet.id)
        val raw=wallets.singleOrNull{it.id==expectedWallet.id} ?: reconciliationFail(InvestmentCashReconciliationError.STALE_RECORD)
        val current=try{investmentLinkedWalletRecord(raw)}catch(_:Exception){reconciliationFail()}
        if(expectedWallet.ownerUserId!=owner.value || !expectedWallet.matchesVisibleInvestmentWallet(current))reconciliationFail(InvestmentCashReconciliationError.STALE_RECORD)
    }
    requireWallet(expected.system);requireWallet(expected.linked)
    if(expected.locations.map{it.wallet.id}.distinct().size!=expected.locations.size)invalid()
    val desired=mutableListOf<CloudRecord>()
    val eventIds=request.transfers.map{it.eventId}.toSet()
    for(transfer in request.transfers) {
        identity(transfer.eventId);identity(transfer.sourceWalletId)
        val source=expected.locations.singleOrNull{it.wallet.id==transfer.sourceWalletId} ?: invalid()
        if(source.wallet.currencyCode!=code || source.wallet.kind in setOf(null,WalletKind.CREDIT_CARD,WalletKind.INVESTMENT) ||
            source.wallet.deletedAt!=null || source.wallet.isArchived || source.bookedMinor.signum()<=0 || source.wallet.id==expected.linked.id)invalid()
        requireWallet(source.wallet)
        val amount=transfer.amountMinor
        val booked=source.bookedMinor.min(BigInteger.valueOf(amount)).longValueExact()
        val ledgerId=investmentLedgerIdentity(transfer.eventId,"cash-reconciliation")
        fun row(entity:CloudEntity,id:String,fields:JsonObject)=CloudRecord(entity.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("created_at",request.createdAt);put("updated_at",now);put("deleted_at",JsonNull)
            put("sync_version",0L);put("last_modified_by_device_id",deviceId);fields.forEach{put(it.key,it.value)}
        },now,null,0)
        desired+=row(CloudEntity.LEDGER_TRANSACTION,ledgerId,buildJsonObject {
            put("primary_kind_raw_value","transfer");put("transfer_subtype_raw_value","internalTransfer");put("entry_status_raw_value","posted")
            put("title",request.ledgerTitle);put("amount_minor",amount);put("source_wallet_id",source.wallet.id);put("destination_wallet_id",expected.linked.id)
            put("source_currency_code",code);put("destination_currency_code",code);put("destination_amount_minor",amount)
            put("reporting_currency_code",code);put("reporting_amount_minor",amount);put("reporting_expense_minor",0L);put("reporting_income_minor",0L)
            put("settlement_role_raw_value","investmentReconciliation");put("occurred_at",request.occurredAt);put("is_archived",false)
            put("created_by_user_id",owner.value);put("last_modified_by_user_id",owner.value)
            for(key in listOf("debt_intent_raw_value","category_id","settlement_group_id","settlement_obligation_id","archived_at","note",
                "conversion_mode_raw_value","exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","counterparty_name","normalized_counterparty_key"))put(key,JsonNull)
        })
        for((component,wallet,delta) in listOf(Triple("holder-cash-posting",source.wallet.id,-booked),Triple("linked-cash-posting",expected.linked.id,booked))) {
            desired+=row(CloudEntity.INVESTMENT_POSTING,investmentLedgerIdentity(transfer.eventId,component),buildJsonObject {
                put("event_id",transfer.eventId);put("trade_id",JsonNull);put("asset_id",JsonNull);put("wallet_id",wallet);put("ledger_transaction_id",ledgerId)
                put("role_raw_value","cashReconciliation");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","manual")
                put("amount_minor",delta);put("accounting_amount_minor",delta);put("currency_code",code);put("accounting_currency_code",code);put("occurred_at",request.occurredAt)
            })
        }
    }
    val keys=desired.map{it.entity to it.id}.toSet()
    if(keys.size!=desired.size)invalid()
    if(snapshot.rows.any{row->
        (row.entity==CloudEntity.INVESTMENT_POSTING.table && row.payload.financeRawReference("event_id").id in eventIds && (row.entity to row.id) !in keys) ||
        (row.entity==CloudEntity.INVESTMENT_TRADE.table && row.id in eventIds) ||
        (row.entity==CloudEntity.LEDGER_TRANSACTION.table && row.id in eventIds)
    })reconciliationFail(InvestmentCashReconciliationError.EVENT_CONFLICT)
    val existing=desired.map{target->snapshot.rows.singleOrNull{it.entity==target.entity && it.id==target.id}}
    if(existing.any{it!=null}) {
        fun matches(actual:CloudRecord?,wanted:CloudRecord):Boolean=actual!=null && runCatching {
            investmentAssetVersion(actual)
            require(actual.financeRawDeleted(true)==false && actual.payload["deleted_at"]==JsonNull)
            require(actual.updatedAt!=null && Instant.parse(actual.updatedAt)==Instant.parse(actual.payload.financeRawString("updated_at")))
            wanted.payload.forEach{(key,value)->
                when(key) {
                    "sync_version","last_modified_by_device_id","updated_at"->Unit
                    "created_at","occurred_at"->require(Instant.parse(actual.payload.financeRawString(key))==Instant.parse(value.jsonPrimitive.content))
                    else->require(actual.payload[key]==value)
                }
            }
        }.isSuccess
        if(existing.zip(desired).all{(actual,target)->matches(actual,target)})return InvestmentCashReconciliationPlan(emptyList())
        reconciliationFail(InvestmentCashReconciliationError.EVENT_CONFLICT)
    }
    val current=readInvestmentCashReconciliation(snapshot)
    for(transfer in request.transfers) {
        val before=expected.locations.single{it.wallet.id==transfer.sourceWalletId}
        val location=current.locations.singleOrNull{it.wallet.id==transfer.sourceWalletId} ?: reconciliationFail(InvestmentCashReconciliationError.STALE_RECORD)
        if(before.bookedMinor!=location.bookedMinor || before.actualMinor!=location.actualMinor)reconciliationFail(InvestmentCashReconciliationError.STALE_RECORD)
        if(BigInteger.valueOf(transfer.amountMinor)>location.actualMinor)reconciliationFail(InvestmentCashReconciliationError.EXCEEDS_BALANCE)
    }
    return InvestmentCashReconciliationPlan(desired.map{row->row to PendingMutation(requireNotNull(CloudEntity.fromTable(row.entity)),row.id,owner.value,
        MutationKind.UPSERT,row.payload,now,row.syncVersion,deviceId)})
}
