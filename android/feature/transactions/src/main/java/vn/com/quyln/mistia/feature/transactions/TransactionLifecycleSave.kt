package vn.com.quyln.mistia.feature.transactions

import vn.com.quyln.mistia.core.model.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

internal class TransactionReceiptCleanupRequired(val deleted:LedgerTransactionRecord,cause:Throwable):Exception("Transaction deleted; receipt retained",cause)

internal data class TransactionLifecycleReceiptSnapshot(val ownerUserId:String,val transactionId:String,val operationAt:String,
    val receipt:TransactionReceiptImageRecord?)

internal suspend fun captureTransactionLifecycleReceiptSnapshot(owner:UserId,request:TransactionInvestmentLifecycleRequest,deviceId:String,now:String,
    repository:FinanceRepository,receipts:TransactionReceiptImageRepository):TransactionLifecycleReceiptSnapshot {
    currentCoroutineContext().ensureActive()
    require(request.action==TransactionLifecycleAction.DELETE)
    repository.prepareTransactionLifecycle(owner,request,deviceId,now).getOrThrow()
    val stored=receipts.receipt(request.expected.id)?.also {
        require(it.ownerUserId==owner.value && it.transactionId==request.expected.id){"Lifecycle receipt ownership mismatch"}
    }
    currentCoroutineContext().ensureActive()
    return TransactionLifecycleReceiptSnapshot(owner.value,request.expected.id,request.operationAt,stored)
}

internal suspend fun saveTransactionLifecycleWithReceipt(owner:UserId,request:TransactionInvestmentLifecycleRequest,deviceId:String,now:String,
    repository:FinanceRepository,receipts:TransactionReceiptImageRepository,receiptSnapshot:TransactionLifecycleReceiptSnapshot?=null):Result<LedgerTransactionRecord> {
    try {
        currentCoroutineContext().ensureActive()
        suspend fun prepare()=repository.prepareTransactionLifecycle(owner,request,deviceId,now).getOrThrow().also {
            require(it.record.id==request.expected.id && it.record.ownerUserId==owner.value){"Lifecycle result identity changed"}
        }
        val prepared=prepare() // Consent and financial admission precede any receipt access.
        suspend fun ownedReceipt():TransactionReceiptImageRecord?=receipts.receipt(request.expected.id)?.also {
            require(it.ownerUserId==owner.value && it.transactionId==request.expected.id){"Lifecycle receipt ownership mismatch"}
        }
        val deleting=request.action==TransactionLifecycleAction.DELETE
        val original=if(deleting)requireNotNull(receiptSnapshot){"Deletion requires its original receipt snapshot"}.also {
            require(it.ownerUserId==owner.value && it.transactionId==request.expected.id && it.operationAt==request.operationAt){"Lifecycle receipt snapshot scope changed"}
            val current=ownedReceipt()
            require(current==null || current==it.receipt){"Lifecycle receipt changed before deletion"}
        }.receipt else null
        val result=if(prepared.mutations.isEmpty())Result.success(prepared.record) else
            try{repository.saveTransactionLifecycle(owner,request,deviceId,now)}catch(error:Throwable){Result.failure(error)}
        val failure=result.exceptionOrNull()
        if(failure is CancellationException)throw failure // Leave durable images for an explicit retry.
        var saved=result.getOrNull()
        if(failure!=null) {
            val recovered=try{prepare().takeIf{it.mutations.isEmpty()}?.record}
            catch(cancelled:CancellationException){throw cancelled}
            catch(proof:Throwable){if(proof!==failure)failure.addSuppressed(proof);null}
            if(recovered==null)return Result.failure(failure)
            saved=recovered
        }
        currentCoroutineContext().ensureActive()
        if(deleting) {
            // Re-prove the owned committed tombstone immediately before unlinking its image.
            val proof=prepare()
            require(proof.mutations.isEmpty()){ "Lifecycle deletion is not durably complete" }
            saved=proof.record
            try {
                val current=ownedReceipt()
                require(current==null || current==original){"Lifecycle receipt changed during deletion"}
                if(current!=null)receipts.deleteReceiptIfUnchanged(owner,requireNotNull(original)).getOrThrow()
                currentCoroutineContext().ensureActive()
            } catch(cancelled:CancellationException){throw cancelled}
              catch(error:Throwable){throw TransactionReceiptCleanupRequired(proof.record,error)}
        }
        return Result.success(requireNotNull(saved))
    } catch(cancelled:CancellationException){throw cancelled}
      catch(error:Throwable){return Result.failure(error)}
}
