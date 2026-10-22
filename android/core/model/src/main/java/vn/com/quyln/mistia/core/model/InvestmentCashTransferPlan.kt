package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.time.Instant
import kotlinx.serialization.json.*

data class InvestmentCashTransferDraft(val id:String,val direction:InvestmentCashTransferDirection,val walletId:String,val amountMinor:Long,
    val note:String?,val occurredAt:String,val createdAt:String)
data class InvestmentCashTransferRequest(val expectedSystem:LedgerWalletRecord,val expectedLinked:LedgerWalletRecord,val expectedSelected:LedgerWalletRecord,
    val draft:InvestmentCashTransferDraft,val expectedPreview:InvestmentCashTransferPreview,val ledgerTitle:String)
data class InvestmentCashTransferPlan(val mutations:List<Pair<CloudRecord,PendingMutation>>)
enum class InvestmentCashTransferError { INVALID_INPUT, INVALID_WALLET, UNREADABLE_SOURCE, STALE_RECORD, EXCEEDS_LIMIT, EVENT_CONFLICT, HAS_DEPENDENTS, DIRECTION_LOCKED }
class InvestmentCashTransferException(val reason:InvestmentCashTransferError):IllegalArgumentException(reason.name)
fun planInvestmentCashTransfer(snapshot:InvestmentCashReadSnapshot,request:InvestmentCashTransferRequest,deviceId:String,now:String):InvestmentCashTransferPlan {
    fun fail(reason:InvestmentCashTransferError):Nothing=throw InvestmentCashTransferException(reason)
    fun invalid():Nothing=fail(InvestmentCashTransferError.INVALID_INPUT)
    fun unreadable():Nothing=fail(InvestmentCashTransferError.UNREADABLE_SOURCE)
    fun identity(value:String)=financeRawUuid(value)?.takeIf{it==value} ?: invalid()
    fun instant(value:String)=runCatching{Instant.parse(value)}.getOrElse{invalid()}
    val draft=request.draft;val owner=snapshot.owner
    identity(deviceId);identity(draft.id);identity(draft.walletId)
    instant(now);instant(draft.occurredAt);instant(draft.createdAt)
    if(draft.amountMinor<=0 || request.ledgerTitle.isBlank())invalid()
    try{snapshot.requireScoped()}catch(_:InvestmentCashReadException){unreadable()}
    fun raw(entity:CloudEntity,id:String)=snapshot.rows.singleOrNull{it.entity==entity.table && it.id==id}
    fun wallet(id:String)=raw(CloudEntity.LEDGER_WALLET,id)?.let{row ->runCatching{investmentLinkedWalletRecord(row)}.getOrElse{unreadable()}}
        ?: fail(InvestmentCashTransferError.INVALID_WALLET)
    val system=wallet(investmentSystemWalletId(owner))
    if(system.kind!=WalletKind.INVESTMENT || system.systemPurposeRawValue!="investmentProfit" || system.deletedAt!=null || system.isArchived)
        fail(InvestmentCashTransferError.INVALID_WALLET)
    val linked=wallet(system.investmentLinkedWalletId ?: fail(InvestmentCashTransferError.INVALID_WALLET))
    val selected=wallet(draft.walletId)
    val code=investmentAssetCurrency(system.currencyCode) ?: unreadable()
    for(candidate in listOf(linked,selected))if(candidate.ownerUserId!=owner.value || candidate.deletedAt!=null || candidate.isArchived ||
        candidate.kind==null || candidate.kind in setOf(WalletKind.CREDIT_CARD,WalletKind.INVESTMENT) || investmentAssetCurrency(candidate.currencyCode)!=code)
        fail(InvestmentCashTransferError.INVALID_WALLET)
    fun visible(expected:LedgerWalletRecord,current:LedgerWalletRecord) {
        if(expected.ownerUserId!=owner.value || expected.id!=current.id)fail(InvestmentCashTransferError.INVALID_WALLET)
        if(!runCatching{expected.matchesVisibleInvestmentWallet(current)}.getOrElse{unreadable()})fail(InvestmentCashTransferError.STALE_RECORD)
    }
    visible(request.expectedSystem,system);visible(request.expectedLinked,linked);visible(request.expectedSelected,selected)
    val deposit=draft.direction==InvestmentCashTransferDirection.DEPOSIT
    val source=if(deposit)selected else linked
    val destination=if(deposit)linked else selected
    val postingId=investmentLedgerIdentity(draft.id,"cash-transfer-posting")
    val signed=if(deposit)draft.amountMinor else -draft.amountMinor
    val note=investmentCashTrimmedText(draft.note)
    val ledgerFields=buildJsonObject {
        put("primary_kind_raw_value","transfer");put("transfer_subtype_raw_value","internalTransfer");put("entry_status_raw_value","posted")
        put("title",request.ledgerTitle);put("amount_minor",draft.amountMinor);put("source_wallet_id",source.id);put("destination_wallet_id",destination.id)
        put("source_currency_code",code);put("destination_currency_code",code);put("destination_amount_minor",draft.amountMinor)
        put("reporting_currency_code",code);put("reporting_amount_minor",draft.amountMinor);put("reporting_expense_minor",0L);put("reporting_income_minor",0L)
        put("settlement_role_raw_value",if(deposit)"investmentCashDeposit" else "investmentCashWithdrawal");put("occurred_at",draft.occurredAt);put("is_archived",false)
        put("created_by_user_id",owner.value);put("last_modified_by_user_id",owner.value);put("note",note?.let(::JsonPrimitive) ?: JsonNull)
        for(key in listOf("debt_intent_raw_value","category_id","settlement_group_id","settlement_obligation_id","archived_at",
            "conversion_mode_raw_value","exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","counterparty_name","normalized_counterparty_key"))put(key,JsonNull)
    }
    val postingFields=buildJsonObject {
        put("event_id",draft.id);put("trade_id",JsonNull);put("asset_id",JsonNull);put("wallet_id",linked.id)
        put("ledger_transaction_id",draft.id);put("role_raw_value","cashTransfer");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","manual")
        put("amount_minor",signed);put("currency_code",code);put("accounting_amount_minor",signed);put("accounting_currency_code",code);put("occurred_at",draft.occurredAt)
    }
    if(snapshot.rows.any{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.id!=postingId && it.payload.financeRawReference("event_id").id==draft.id})
        fail(InvestmentCashTransferError.EVENT_CONFLICT)
    val existingLedger=raw(CloudEntity.LEDGER_TRANSACTION,draft.id)
    val existingPosting=raw(CloudEntity.INVESTMENT_POSTING,postingId)
    if(existingLedger!=null || existingPosting!=null) {
        fun matches(row:CloudRecord?,fields:JsonObject):Boolean = row!=null && runCatching {
            investmentAssetVersion(row)
            require(row.financeRawDeleted(true)==false && row.payload["deleted_at"]==JsonNull)
            for(key in listOf("created_at","updated_at"))Instant.parse(requireNotNull(row.payload.financeRawString(key)))
            require(row.updatedAt!=null && Instant.parse(row.updatedAt)==Instant.parse(row.payload.financeRawString("updated_at")))
            require(fields.all{(key,value)->if(key=="occurred_at")Instant.parse(row.payload.financeRawString(key))==Instant.parse(draft.occurredAt) else row.payload[key]==value})
            if(row.entity==CloudEntity.LEDGER_TRANSACTION.table)require(Instant.parse(row.payload.financeRawString("created_at"))==Instant.parse(draft.createdAt))
        }.isSuccess
        if(matches(existingLedger,ledgerFields) && matches(existingPosting,postingFields))return InvestmentCashTransferPlan(emptyList())
        fail(InvestmentCashTransferError.EVENT_CONFLICT)
    }
    val preview=cashTransferCapacity(snapshot,system,linked,selected,draft.direction,draft.amountMinor)
    if(request.expectedPreview!=preview)fail(InvestmentCashTransferError.STALE_RECORD)
    if(!preview.isValid)fail(InvestmentCashTransferError.EXCEEDS_LIMIT)
    fun create(entity:CloudEntity,id:String,createdAt:String,fields:JsonObject):CloudRecord = CloudRecord(entity.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("created_at",createdAt);put("updated_at",now);put("deleted_at",JsonNull)
        put("sync_version",0L);put("last_modified_by_device_id",deviceId);fields.forEach{put(it.key,it.value)}
    },now,null,0L)
    val records=listOf(create(CloudEntity.LEDGER_TRANSACTION,draft.id,draft.createdAt,ledgerFields),create(CloudEntity.INVESTMENT_POSTING,postingId,now,postingFields))
    return InvestmentCashTransferPlan(records.map{row ->row to PendingMutation(requireNotNull(CloudEntity.fromTable(row.entity)),row.id,owner.value,
        MutationKind.UPSERT,row.payload,now,row.syncVersion,deviceId)})
}

data class InvestmentCashTransferReadView(val system:LedgerWalletRecord,val linked:LedgerWalletRecord,val selected:LedgerWalletRecord,
    val eligibleWallets:List<LedgerWalletRecord>,val preview:InvestmentCashTransferPreview)
fun readInvestmentCashTransfer(snapshot:InvestmentCashReadSnapshot,direction:InvestmentCashTransferDirection,walletId:String?,requestedMinor:Long):InvestmentCashTransferReadView {
    fun invalid():Nothing=throw InvestmentCashTransferException(InvestmentCashTransferError.INVALID_WALLET)
    try{snapshot.requireScoped()}catch(_:InvestmentCashReadException){throw InvestmentCashTransferException(InvestmentCashTransferError.UNREADABLE_SOURCE)}
    val wallets=try{investmentLinkedWalletView(snapshot.walletSnapshot())}catch(error:InvestmentWalletLinkException){
        throw InvestmentCashTransferException(if(error.reason==InvestmentWalletLinkError.INVALID_WALLET)InvestmentCashTransferError.INVALID_WALLET else InvestmentCashTransferError.UNREADABLE_SOURCE)
    }
    val eligible=wallets.eligibleWallets
    val linked=wallets.linkedWallet?.takeIf{linked ->eligible.any{it.id==linked.id}} ?: invalid()
    val selected=if(walletId!=null)eligible.singleOrNull{it.id==walletId} ?: invalid()
        else if(direction==InvestmentCashTransferDirection.WITHDRAWAL)linked else eligible.firstOrNull() ?: invalid()
    val preview=cashTransferCapacity(snapshot,wallets.system,linked,selected,direction,requestedMinor)
    return InvestmentCashTransferReadView(wallets.system,linked,selected,eligible,preview)
}

private fun cashTransferCapacity(snapshot:InvestmentCashReadSnapshot,system:LedgerWalletRecord,linked:LedgerWalletRecord,selected:LedgerWalletRecord,
    direction:InvestmentCashTransferDirection,requestedMinor:Long):InvestmentCashTransferPreview {
    fun unreadable():Nothing=throw InvestmentCashTransferException(InvestmentCashTransferError.UNREADABLE_SOURCE)
    val owner=snapshot.owner
    val code=investmentAssetCurrency(system.currencyCode) ?: unreadable()
    val source=if(direction==InvestmentCashTransferDirection.DEPOSIT)selected else linked
    val allocation=runCatching{investmentCashAllocation(snapshot.walletSnapshot(),code)}.getOrElse{unreadable()}
    val sourceLocation=allocation.locations.singleOrNull{it.walletId==source.id}
    val linkedLocation=allocation.locations.singleOrNull{it.walletId==linked.id}
    if(listOfNotNull(sourceLocation,linkedLocation).any{it.currencyCode!=code})unreadable()
    val actual=financeWalletBalancesRaw(owner,snapshot.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},
        snapshot.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table},setOf(source.id))?.get(source.id) ?: unreadable()
    val profit=investmentPersistedProfit(owner,snapshot.rows.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table},code) ?: unreadable()
    val preview=investmentCashTransferPreview(direction,requestedMinor,profit,allocation.totalMinor,linkedLocation?.bookedMinor ?: BigInteger.ZERO,
        actual,sourceLocation?.originalTotalMinor ?: BigInteger.ZERO)
    return preview
}

/** Swift CharacterSet.whitespacesAndNewlines without collapsing internal text. */
fun investmentCashTrimmedText(value:String?):String?=value?.trim{it.isInvestmentWhitespace()}?.takeIf{it.isNotEmpty()}
