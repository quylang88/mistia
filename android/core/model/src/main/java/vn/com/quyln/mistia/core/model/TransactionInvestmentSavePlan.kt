package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.json.*

data class TransactionCreationIdentity(val id:String,val createdAt:String)
data class TransactionInvestmentSaveRequest(val draft:TransactionDraft,val creation:TransactionCreationIdentity?,val consent:InvestmentFundUsageConsent?,val adjustmentTitle:String,val accountingCurrency:String)
data class TransactionInvestmentSavePlan(val record:LedgerTransactionRecord,val mutations:List<Pair<CloudRecord,PendingMutation>>)

fun planTransactionInvestmentSave(snapshot:TransactionInvestmentSaveSnapshot,request:TransactionInvestmentSaveRequest,deviceId:String,now:String,
    statementZone:ZoneId=ZoneId.systemDefault()):TransactionInvestmentSavePlan {
    snapshot.requireValid()
    val ordinary=snapshot.transactionSnapshot()
    val wallets=ordinary.active(CloudEntity.LEDGER_WALLET).map(LedgerWalletRecord::fromCloudRecord)
    val categories=ordinary.active(CloudEntity.TRANSACTION_CATEGORY).map(TransactionCategoryRecord::fromCloudRecord)
    val transactions=ordinary.active(CloudEntity.LEDGER_TRANSACTION).map(LedgerTransactionRecord::fromCloudRecord)
    val profiles=ordinary.active(CloudEntity.CREDIT_CARD_PROFILE).map(CreditCardProfileRecord::fromCloudRecord)
    val occurrences=ordinary.active(CloudEntity.DUE_OCCURRENCE_RECORD)
    fun conflict():Nothing=throw InvestmentFundUsageException(InvestmentFundUsageError.EVENT_CONFLICT)
    val draft=request.draft
    val creating=draft.id==null
    val identity=if(creating)request.creation ?: conflict() else null
    if(!creating && request.creation!=null)conflict()
    val id=(draft.id ?: identity!!.id).lowercase()
    if(financeRawUuid(id)!=id || (identity!=null && (identity.id!=id || runCatching{Instant.parse(identity.createdAt)}.isFailure)))conflict()
    val old=ordinary.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).singleOrNull{it.id==id}
    if((!creating && old==null) || old?.deletedAt!=null || (old!=null && old.payload["deleted_at"]!=JsonNull))conflict()
    val existing=old?.let(LedgerTransactionRecord::fromCloudRecord)
    val mutation=draft.copy(id=id).toMutation(snapshot.owner,if(creating)null else existing,
        wallets.firstOrNull{it.id==draft.sourceWalletId?.lowercase()},wallets.firstOrNull{it.id==draft.destinationWalletId?.lowercase()},
        categories.firstOrNull{it.id==draft.categoryId?.lowercase()},deviceId,now)
    val primary=mutation.record.let{if(identity==null)it else it.copy(createdAt=Instant.parse(identity.createdAt).toString())}
    val known=primary.toPayload()
    val same=old!=null && sameOrdinaryFields(known,old.payload)
    if(creating && old!=null) {
        if(!same)conflict()
        // A completed creation is proof, never permission to repair or overwrite an occupied identity.
        val review=reviewInvestmentFundUsage(snapshot.investmentSnapshot(),request.accountingCurrency,old)
        val derived=planInvestmentFundUsage(snapshot.investmentSnapshot(),request.accountingCurrency,old,review.consent,request.adjustmentTitle,deviceId,now)
        if(derived.mutations.isNotEmpty())conflict()
        return TransactionInvestmentSavePlan(existing!!,emptyList())
    }
    requireExactOrdinaryAffordability(snapshot,primary,profiles,existing?.id)
    fun locked(record:LedgerTransactionRecord,rows:List<LedgerTransactionRecord>)=record.isLockedByPaidCreditCardStatement(
        wallets,profiles,categories,rows,occurrences,statementZone,Instant.parse(now))
    if(existing!=null && locked(existing,transactions))throw TransactionValidationException(TransactionValidationError.PAID_CREDIT_CARD_STATEMENT)
    if((primary.primaryKind==TransactionPrimaryKind.EXPENSE || (primary.transferSubtype==TransactionTransferSubtype.DEBT && primary.debtIntent==TransactionDebtIntent.LEND)) &&
        locked(primary,transactions.filterNot{it.id==id}))throw TransactionValidationException(TransactionValidationError.PAID_CREDIT_CARD_STATEMENT)
    val proposed=if(same)old!! else primary.toCloudRecord().copy(payload=JsonObject(old?.payload.orEmpty()+known))
    val derived=planInvestmentFundUsage(snapshot.investmentSnapshot(),request.accountingCurrency,proposed,request.consent,request.adjustmentTitle,deviceId,now)
    val writes=if(same)emptyList() else listOf(proposed to mutation.pending.copy(payload=proposed.payload))
    return TransactionInvestmentSavePlan(LedgerTransactionRecord.fromCloudRecord(proposed),writes+derived.mutations)
}

private val ordinaryAckFields=setOf("sync_version","updated_at","last_modified_by_device_id","last_modified_by_user_id")
private fun sameOrdinaryFields(expected:JsonObject,stored:JsonObject):Boolean=expected.filterKeys{it !in ordinaryAckFields}.all{(key,value)->
    fun normalized(v:JsonElement?):JsonElement?=if(key in setOf("created_at","occurred_at","deleted_at","archived_at") && v is JsonPrimitive && v.isString)
        runCatching{JsonPrimitive(Instant.parse(v.content).toString())}.getOrDefault(v) else v
    normalized(value)==normalized(stored[key])
}

private fun requireExactOrdinaryAffordability(snapshot:TransactionInvestmentSaveSnapshot,primary:LedgerTransactionRecord,
    profiles:List<CreditCardProfileRecord>,excludingId:String?) {
    if(primary.entryStatus!=TransactionEntryStatus.POSTED || primary.primaryKind==TransactionPrimaryKind.INCOME)return
    if(primary.primaryKind!=TransactionPrimaryKind.EXPENSE && primary.transferSubtype!=TransactionTransferSubtype.INTERNAL_TRANSFER &&
        !(primary.transferSubtype==TransactionTransferSubtype.DEBT && primary.debtIntent in setOf(TransactionDebtIntent.LEND,TransactionDebtIntent.REPAY)))return
    val source=primary.sourceWalletId ?: return
    val rawWallets=snapshot.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET)
    val wallet=rawWallets.singleOrNull{it.id==source} ?: throw TransactionValidationException(TransactionValidationError.INVALID_SOURCE_WALLET)
    val isCard=wallet.payload.financeRawString("kind_raw_value")==WalletKind.CREDIT_CARD.wireValue
    // Read-only cash projection measures card liability without Long saturation; never persist it.
    val projected=if(!isCard)rawWallets else rawWallets.map{if(it.id!=source)it else it.copy(payload=JsonObject(it.payload+buildJsonObject{put("kind_raw_value",WalletKind.CASH.wireValue);put("opening_balance_minor",0L)}))}
    val balance=financeWalletBalancesRaw(snapshot.owner,snapshot.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).filterNot{it.id==excludingId},projected,setOf(source))?.get(source)
        ?: throw InvestmentFundUsageException(InvestmentFundUsageError.UNREADABLE_SOURCE)
    val available=if(!isCard)balance else {
        val profile=profiles.singleOrNull{it.walletId==source && it.ownerUserId==snapshot.owner.value && it.deletedAt==null}
            ?: throw TransactionValidationException(TransactionValidationError.CREDIT_CARD_PROFILE_REQUIRED)
        (BigInteger.valueOf(profile.creditLimitMinor)-(-balance).max(BigInteger.ZERO)).max(BigInteger.ZERO)
    }
    if(BigInteger.valueOf(primary.amountMinor)>available)throw TransactionValidationException(if(isCard)TransactionValidationError.CREDIT_LIMIT_EXCEEDED else TransactionValidationError.INSUFFICIENT_WALLET_BALANCE)
}
