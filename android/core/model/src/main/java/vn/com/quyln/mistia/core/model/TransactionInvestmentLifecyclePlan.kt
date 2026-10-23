package vn.com.quyln.mistia.core.model

import java.time.ZoneId
import java.time.Instant
import java.time.YearMonth
import kotlinx.serialization.json.*

enum class TransactionLifecycleAction { ARCHIVE, RESTORE, DELETE }
data class TransactionInvestmentLifecycleRequest(val expected:LedgerTransactionRecord,val action:TransactionLifecycleAction,
    val operationAt:String,val accountingCurrency:String,val adjustmentTitle:String,val consent:InvestmentFundUsageConsent?)

fun planTransactionInvestmentLifecycle(snapshot:TransactionInvestmentSaveSnapshot,request:TransactionInvestmentLifecycleRequest,
    deviceId:String,now:String,statementZone:ZoneId=ZoneId.systemDefault()):TransactionInvestmentSavePlan {
    snapshot.requireValid()
    fun conflict():Nothing=throw InvestmentFundUsageException(InvestmentFundUsageError.EVENT_CONFLICT)
    val expected=request.expected
    if(expected.ownerUserId!=snapshot.owner.value || financeRawUuid(deviceId)!=deviceId || financeRawUuid(expected.id)!=expected.id)conflict()
    val at=try{Instant.parse(request.operationAt).also{require(it<=Instant.parse(now))}.toString()}catch(_:Exception){conflict()}
    if(!expected.supportsOrdinaryTransactionLifecycle() || expected.deletedAt!=null)conflict()
    if((request.action==TransactionLifecycleAction.ARCHIVE)==expected.isArchived)conflict()
    val raw=snapshot.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).singleOrNull{it.id==expected.id} ?: conflict()
    val bodyDeletion=raw.payload["deleted_at"]
    val declaredDeletion=if(bodyDeletion==null || bodyDeletion==JsonNull)null else {
        if(bodyDeletion !is JsonPrimitive || !bodyDeletion.isString)conflict()
        try{Instant.parse(bodyDeletion.content).toString()}catch(_:Exception){conflict()}
    }
    val envelopeDeletion=raw.deletedAt?.let{try{Instant.parse(it).toString()}catch(_:Exception){conflict()}}
    if(declaredDeletion!=envelopeDeletion)conflict()
    val fields=buildJsonObject {
        if(request.action==TransactionLifecycleAction.DELETE)put("deleted_at",at)
        else {put("is_archived",request.action==TransactionLifecycleAction.ARCHIVE);put("archived_at",if(request.action==TransactionLifecycleAction.ARCHIVE)JsonPrimitive(at) else JsonNull)}
    }
    val desired=JsonObject(expected.toPayload()+fields)
    val original=matchesLifecycleFields(expected.toPayload(),raw.payload)
    if(!original) {
        if(!matchesLifecycleFields(desired,raw.payload))conflict()
        // A complete known result is proof, never permission to repair an occupied or partially saved event.
        // The comparison API intentionally cannot replace a tombstone. An already archived row
        // has no cash effect, so its live archived projection proves the same deleted result.
        val proofSource=if(request.action==TransactionLifecycleAction.DELETE) snapshot.investmentSnapshot().let{source->
            source.copy(rows=source.rows.map{if(it.entity==raw.entity && it.id==raw.id)it.copy(deletedAt=null,payload=JsonObject(it.payload+("deleted_at" to JsonNull)))else it})
        } else snapshot.investmentSnapshot()
        val review=reviewInvestmentFundUsage(proofSource,request.accountingCurrency,raw)
        val derived=planInvestmentFundUsage(proofSource,request.accountingCurrency,raw,review.consent,request.adjustmentTitle,deviceId,now)
        if(derived.mutations.isNotEmpty())conflict()
        return TransactionInvestmentSavePlan(LedgerTransactionRecord.fromCloudRecord(raw),emptyList())
    }
    if(raw.financeRawDeleted(true)!=false || raw.deletedAt!=null)conflict()
    val ordinary=snapshot.transactionSnapshot()
    val wallets=ordinary.active(CloudEntity.LEDGER_WALLET).map(LedgerWalletRecord::fromCloudRecord)
    val categories=ordinary.active(CloudEntity.TRANSACTION_CATEGORY).map(TransactionCategoryRecord::fromCloudRecord)
    val profiles=ordinary.active(CloudEntity.CREDIT_CARD_PROFILE).map(CreditCardProfileRecord::fromCloudRecord)
    val transactions=ordinary.active(CloudEntity.LEDGER_TRANSACTION).map(LedgerTransactionRecord::fromCloudRecord)
    val current=LedgerTransactionRecord.fromCloudRecord(raw)
    val checking=if(request.action==TransactionLifecycleAction.RESTORE)current.copy(isArchived=false,archivedAt=null) else current
    if(request.action!=TransactionLifecycleAction.DELETE && checking.isLockedByPaidCreditCardStatement(wallets,profiles,categories,transactions,
            ordinary.active(CloudEntity.DUE_OCCURRENCE_RECORD),statementZone,Instant.parse(now)))
        throw TransactionValidationException(TransactionValidationError.PAID_CREDIT_CARD_STATEMENT)
    if(request.action==TransactionLifecycleAction.RESTORE) {
        val draft=TransactionDraft(id=current.id,primaryKind=requireNotNull(current.primaryKind),transferSubtype=current.transferSubtype,debtIntent=current.debtIntent,
            counterpartyName=current.counterpartyName,entryStatus=requireNotNull(current.entryStatus),title=current.title,note=current.note,amountMinor=current.amountMinor,
            occurredAt=current.occurredAt,sourceWalletId=current.sourceWalletId,destinationWalletId=current.destinationWalletId,categoryId=current.categoryId,
            destinationAmountMinor=current.destinationAmountMinor,conversionMode=CurrencyConversionMode.fromWireValue(current.conversionModeWireValue),
            exchangeRateDecimalString=current.exchangeRateDecimalString,exchangeRateProvider=current.exchangeRateProvider,exchangeRateDate=current.exchangeRateDate,
            reportingCurrencyCode=current.reportingCurrencyCode,reportingAmountMinor=current.reportingAmountMinor)
        val source=wallets.singleOrNull{it.id==current.sourceWalletId};val destination=wallets.singleOrNull{it.id==current.destinationWalletId}
        draft.toMutation(snapshot.owner,checking,source,destination,categories.singleOrNull{it.id==current.categoryId},deviceId,now)
        if((current.sourceCurrencyCode!=null && current.sourceCurrencyCode.financeReportingCode()!=source?.currencyCode?.financeReportingCode()) ||
            (current.destinationWalletId!=null && current.destinationCurrencyCode!=null && current.destinationCurrencyCode.financeReportingCode()!=destination?.currencyCode?.financeReportingCode()))conflict()
        requireExactOrdinaryAffordability(snapshot,checking,profiles,current.id)
        if(destination?.kind==WalletKind.CREDIT_CARD && current.transferSubtype==TransactionTransferSubtype.INTERNAL_TRANSFER) {
            val month=YearMonth.from(Instant.parse(current.occurredAt).atZone(statementZone))
            if(transactions.any{it.id!=current.id && !it.isArchived && it.deletedAt==null && it.entryStatus==TransactionEntryStatus.POSTED &&
                    it.transferSubtype==TransactionTransferSubtype.INTERNAL_TRANSFER && it.destinationWalletId==destination.id &&
                    YearMonth.from(Instant.parse(it.occurredAt).atZone(statementZone))==month})
                throw TransactionValidationException(TransactionValidationError.PAID_CREDIT_CARD_STATEMENT)
        }
    }
    val changed=investmentAssetChanged(raw,JsonObject(fields+("last_modified_by_user_id" to JsonPrimitive(snapshot.owner.value))),deviceId,now)
        .let{if(request.action==TransactionLifecycleAction.DELETE)it.copy(deletedAt=at)else it}
    val derived=planInvestmentFundUsage(snapshot.investmentSnapshot(),request.accountingCurrency,changed,request.consent,request.adjustmentTitle,deviceId,now)
    val mutation=PendingMutation(CloudEntity.LEDGER_TRANSACTION,changed.id,snapshot.owner.value,
        if(request.action==TransactionLifecycleAction.DELETE)MutationKind.DELETE else MutationKind.UPSERT,changed.payload,now,changed.syncVersion,deviceId)
    return TransactionInvestmentSavePlan(LedgerTransactionRecord.fromCloudRecord(changed),listOf(changed to mutation)+derived.mutations)
}

fun LedgerTransactionRecord.supportsOrdinaryTransactionLifecycle():Boolean {
    if(primaryKind==null || entryStatus==null || settlementGroupId!=null || settlementObligationId!=null || settlementRoleWireValue!=null ||
        reportingExpenseMinor!=null || reportingIncomeMinor!=null)return false
    return when(primaryKind) {
        TransactionPrimaryKind.EXPENSE,TransactionPrimaryKind.INCOME->transferSubtype==null && debtIntent==null
        TransactionPrimaryKind.TRANSFER->when(transferSubtype) {
            TransactionTransferSubtype.INTERNAL_TRANSFER->debtIntent==null
            TransactionTransferSubtype.DEBT->entryStatus==TransactionEntryStatus.POSTED && debtIntent==TransactionDebtIntent.LEND
            else->false
        }
        null->false
    }
}

private fun matchesLifecycleFields(expected:JsonObject,current:JsonObject):Boolean=expected.filterKeys{
    it !in setOf("sync_version","updated_at","last_modified_by_device_id","last_modified_by_user_id")
}.all{(key,value)->
    fun normalized(v:JsonElement?):JsonElement?=if(key in setOf("created_at","occurred_at","deleted_at","archived_at") && v is JsonPrimitive && v.isString)
        runCatching{JsonPrimitive(Instant.parse(v.content).toString())}.getOrDefault(v) else v
    normalized(value)==normalized(current[key] ?: JsonNull)
}
