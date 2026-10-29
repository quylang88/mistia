package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlinx.serialization.json.*

data class CreditCardStatementPaymentSnapshot(val money:TransactionInvestmentSaveSnapshot) {
    val owner get()=money.owner
    fun requireCoherent() {
        money.requireValid()
        for((entity,rows) in money.recordsByEntity)for(row in rows)require(row.financeRawIdentity(owner,entity,true) &&
            row.updatedAt==row.payload.financeRawString("updated_at") && row.deletedAt==row.payload.financeRawString("deleted_at") && row.financeRawDeleted(true)!=null)
    }
    fun requireUnchanged(current:CreditCardStatementPaymentSnapshot) {requireCoherent();current.requireCoherent();money.requireUnchanged(current.money)}
}
data class CreditCardStatementPaymentRequest(val expected:CreditCardStatement,val context:BillInvestmentOperationContext,val title:String)
data class SavedCreditCardStatementPayment(val transaction:LedgerTransactionRecord,val occurrence:DueOccurrenceRecord)
data class CreditCardStatementPaymentPlan(val payment:SavedCreditCardStatementPayment,val mutations:List<Pair<CloudRecord,PendingMutation>>)
enum class CreditCardStatementPaymentError {NOT_FOUND,SOURCE_CHANGED,NOT_PAYABLE,MISSING_LINKED_WALLET,INVALID_WALLET,CURRENCY_MISMATCH,CYCLE_CONFLICT,IDENTITY_CONFLICT}
class CreditCardStatementPaymentException(val reason:CreditCardStatementPaymentError):IllegalArgumentException(reason.name)
fun creditCardPaymentCurrenciesMatch(card:String,wallet:String):Boolean {
    val a=card.trim().uppercase(java.util.Locale.ROOT);val b=wallet.trim().uppercase(java.util.Locale.ROOT)
    return a.matches(Regex("[A-Z]{3}")) && a==b
}
fun planCreditCardStatementPayment(source:CreditCardStatementPaymentSnapshot,request:CreditCardStatementPaymentRequest,
    deviceId:String,now:String,zone:ZoneId=ZoneId.systemDefault()):CreditCardStatementPaymentPlan {
    source.requireCoherent()
    fun fail(reason:CreditCardStatementPaymentError):Nothing=throw CreditCardStatementPaymentException(reason)
    val expected=request.expected;val context=request.context;val proposedCreation=context.creation
    val creation=proposedCreation.copy(createdAt=cashEventInstant(proposedCreation.createdAt).toString())
    require(financeRawUuid(deviceId)==deviceId && financeRawUuid(creation.id)==creation.id && request.title.isNotBlank() && context.adjustmentTitle.isNotBlank())
    val at=Instant.parse(creation.createdAt);val clock=Instant.parse(now);require(Instant.parse(proposedCreation.createdAt)<=clock)
    val rows=source.money.recordsByEntity
    val wallets=rows.getValue(CloudEntity.LEDGER_WALLET).map(LedgerWalletRecord::fromCloudRecord)
    val profiles=rows.getValue(CloudEntity.CREDIT_CARD_PROFILE).map(CreditCardProfileRecord::fromCloudRecord)
    val transactions=rows.getValue(CloudEntity.LEDGER_TRANSACTION).map(LedgerTransactionRecord::fromCloudRecord)
    val occurrences=rows.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).map(DueOccurrenceRecord::fromCloudRecord)
    val categories=rows.getValue(CloudEntity.TRANSACTION_CATEGORY).map(TransactionCategoryRecord::fromCloudRecord)
    val card=wallets.singleOrNull{it.id==expected.account.wallet.id && it.deletedAt==null && !it.isArchived && it.kind==WalletKind.CREDIT_CARD}
        ?: fail(CreditCardStatementPaymentError.NOT_FOUND)
    val profile=profiles.singleOrNull{it.walletId==card.id && it.deletedAt==null} ?: fail(CreditCardStatementPaymentError.NOT_FOUND)
    val linked=profile.paymentSourceWalletId ?: fail(CreditCardStatementPaymentError.MISSING_LINKED_WALLET)
    if(paymentBusiness(card.toPayload())!=paymentBusiness(expected.account.wallet.toPayload()) ||
        paymentBusiness(profile.toPayload())!=paymentBusiness(expected.account.profile.toPayload()))fail(CreditCardStatementPaymentError.SOURCE_CHANGED)
    val wallet=wallets.singleOrNull{it.id==linked && it.deletedAt==null && !it.isArchived && it.kind!=null &&
        it.kind !in setOf(WalletKind.CREDIT_CARD,WalletKind.INVESTMENT) && it.systemPurposeRawValue==null}
        ?: fail(CreditCardStatementPaymentError.INVALID_WALLET)
    if(!creditCardPaymentCurrenciesMatch(card.currencyCode,wallet.currencyCode))fail(CreditCardStatementPaymentError.CURRENCY_MISMATCH)
    val current=creditCardStatementItems(source.owner,listOf(CreditCardAccount(card,profile)),transactions,occurrences,listOf(expected.month),clock,zone,categories).singleOrNull()
        ?: fail(CreditCardStatementPaymentError.NOT_FOUND)
    if(current.amountMinor!=expected.amountMinor || current.closingDate!=expected.closingDate || current.dueDate!=expected.dueDate)
        fail(CreditCardStatementPaymentError.SOURCE_CHANGED)
    if(current.amountMinor<=0 || clock.atZone(zone).toLocalDate()<current.closingDate.atZone(zone).toLocalDate())fail(CreditCardStatementPaymentError.NOT_PAYABLE)
    require(at>=current.closingDate){"Payment date precedes statement closing"}
    val legacyMonth=java.time.YearMonth.from(current.dueDate.atZone(zone)).toString()
    val related=occurrences.filter{it.sourceId==card.id && it.sourceKind==DueSourceKind.CREDIT_CARD &&
        (it.selectedMonthKey==current.month.toString() || it.selectedMonthKey==legacyMonth && Instant.parse(it.scheduledDate)==current.dueDate)}
    val live=related.filter{it.deletedAt==null}
    if(live.size>1)fail(CreditCardStatementPaymentError.CYCLE_CONFLICT)
    val previous=live.singleOrNull()
    val old=transactions.singleOrNull{it.id==creation.id}
    val known=previous?.status==DueStatus.PAID && previous.linkedTransactionId==creation.id && old?.deletedAt==null && old!=null
    if(!current.isPayable && !known)fail(CreditCardStatementPaymentError.NOT_PAYABLE)
    if(previous!=null && !known && (previous.status !in setOf(DueStatus.PENDING,DueStatus.SKIPPED) || previous.linkedTransactionId!=null || previous.paidAt!=null))
        fail(CreditCardStatementPaymentError.CYCLE_CONFLICT)
    if(occurrences.any{it.deletedAt==null && it.linkedTransactionId==creation.id && it.id!=previous?.id})fail(CreditCardStatementPaymentError.IDENTITY_CONFLICT)
    if(old!=null && !known)fail(CreditCardStatementPaymentError.IDENTITY_CONFLICT)
    for(history in related.filter{it.deletedAt!=null && (it.status==DueStatus.PAID || it.linkedTransactionId!=null || it.paidAt!=null)}) {
        val ledger=transactions.singleOrNull{it.id==history.linkedTransactionId}
        if(ledger==null || ledger.deletedAt==null || !at.isAfter(Instant.parse(history.deletedAt)) || !at.isAfter(Instant.parse(ledger.deletedAt)))
            fail(CreditCardStatementPaymentError.CYCLE_CONFLICT)
    }
    val draft=TransactionDraft(primaryKind=TransactionPrimaryKind.TRANSFER,transferSubtype=TransactionTransferSubtype.INTERNAL_TRANSFER,
        title=request.title,amountMinor=current.amountMinor,occurredAt=at.toString(),sourceWalletId=wallet.id,destinationWalletId=card.id)
    val financialRequest=TransactionInvestmentSaveRequest(draft,creation,null,context.adjustmentTitle,context.accountingCurrency)
    val probe=try{planTransactionInvestmentSave(source.money,financialRequest,deviceId,now,zone)}catch(required:InvestmentFundUsageConfirmationRequired){
        if(known)throw required
        null
    }
    if(known) {
        if(probe==null || probe.mutations.isNotEmpty() || previous!!.amountMinorSnapshot!=current.amountMinor ||
            cashEventInstant(previous.paidAt)!=cashEventInstant(at.toString()) || Instant.parse(previous.scheduledDate)!=current.dueDate ||
            cashEventInstant(probe.record.createdAt)!=cashEventInstant(at.toString()) || cashEventInstant(probe.record.occurredAt)!=cashEventInstant(at.toString()))
            fail(CreditCardStatementPaymentError.CYCLE_CONFLICT)
        return CreditCardStatementPaymentPlan(SavedCreditCardStatementPayment(probe.record,previous),emptyList())
    }
    val occurrenceId=previous?.id ?: UUID.nameUUIDFromBytes("vn.com.quyln.mistia.card-statement.${source.owner.value}.${card.id}.${current.month}.${creation.id}".toByteArray(Charsets.UTF_8)).toString()
    if(previous==null && occurrences.any{it.id==occurrenceId})fail(CreditCardStatementPaymentError.IDENTITY_CONFLICT)
    val paid=DueOccurrenceRecord(occurrenceId,source.owner.value,"creditCard",card.id,current.month.toString(),current.dueDate.toString(),current.amountMinor,"paid",at.toString(),creation.id,
        previous?.createdAt ?: at.toString(),now,null,previous?.syncVersion ?: 0,deviceId)
    // Build only a read proof while deriving the consent. Nothing is persisted
    // until the full payment plan is recomputed in the owned Room transaction.
    val primary=probe?.record?.toCloudRecord() ?: draft.copy(id=creation.id).toMutation(source.owner,null,wallet,card,null,deviceId,now).record.copy(createdAt=at.toString()).toCloudRecord()
    val baseReview=reviewInvestmentFundUsage(source.money.investmentSnapshot(),context.accountingCurrency,primary)
    val consent=baseReview.consent.copy(
        sourceToken=RecordConflictResolver.semanticFingerprint(buildJsonObject {
            put("base",baseReview.consent.sourceToken);put("owner",source.owner.value);put("month",current.month.toString())
            put("rows",JsonArray(rows.values.flatten().sortedWith(compareBy(CloudRecord::entity,CloudRecord::id)).map{row->buildJsonObject{put("entity",row.entity);put("body",paymentBusiness(row.payload))}}))
        }),
        proposalToken=RecordConflictResolver.semanticFingerprint(buildJsonObject {
            put("base",baseReview.consent.proposalToken);put("marker",paymentBusiness(paid.toPayload()))
        }))
    if(context.consent!=null && context.consent!=consent)throw InvestmentFundUsageException(InvestmentFundUsageError.STALE_CONSENT)
    if(context.consent==null && baseReview.requiresConfirmation)throw InvestmentFundUsageConfirmationRequired(baseReview.copy(consent=consent))
    val financial=probe ?: planTransactionInvestmentSave(source.money,financialRequest.copy(consent=baseReview.consent),deviceId,now,zone)
    val oldMarker=rows.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).singleOrNull{it.id==occurrenceId}
    val marker=paid.toCloudRecord().let{it.copy(payload=JsonObject(oldMarker?.payload.orEmpty()+it.payload))}
    val q=paid.pendingMutation().copy(payload=marker.payload)
    return CreditCardStatementPaymentPlan(SavedCreditCardStatementPayment(financial.record,paid),financial.mutations+listOf(marker to q))
}

/** Same financial target across ordinary ACK audit fields and Postgres timestamp precision. */
fun creditCardStatementPaymentSourceMatches(a:CreditCardStatement,b:CreditCardStatement):Boolean =
    a.month==b.month && a.amountMinor==b.amountMinor && a.closingDate==b.closingDate && a.dueDate==b.dueDate &&
        creditCardStatementPaymentWalletMatches(a.account.wallet,b.account.wallet) && paymentBusiness(a.account.profile.toPayload())==paymentBusiness(b.account.profile.toPayload())
fun creditCardStatementPaymentWalletMatches(a:LedgerWalletRecord,b:LedgerWalletRecord):Boolean = paymentBusiness(a.toPayload())==paymentBusiness(b.toPayload())

private fun paymentBusiness(payload:JsonObject)=JsonObject(payload.filterKeys{it !in setOf("sync_version","updated_at","last_modified_by_device_id","last_modified_by_user_id")}.mapValues{(key,value)->
    if(value!=JsonNull && key in setOf("created_at","occurred_at","deleted_at","archived_at","scheduled_date","paid_at"))
        JsonPrimitive(cashEventInstant(value.jsonPrimitive.content).toString()) else value
})

interface CreditCardStatementPaymentRepository {
    suspend fun payCreditCardStatement(owner:UserId,request:CreditCardStatementPaymentRequest,deviceId:String,now:String):Result<SavedCreditCardStatementPayment> =
        Result.failure(UnsupportedOperationException("Statement payment persistence unavailable"))
}
