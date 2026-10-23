package vn.com.quyln.mistia.feature.transactions

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.first
import vn.com.quyln.mistia.core.model.*

internal suspend fun saveInvestmentAwareEditorReceiptState(owner:UserId,draft:TransactionDraft,primaryCurrency:String,adjustmentTitle:String,
    deviceId:String,now:String,repository:FinanceRepository,receipts:TransactionReceiptImageRepository,
    receiptState:TransactionReceiptEditorState):Result<LedgerTransactionRecord> {
    val image=receiptState.newReceiptImageForSave()
    if(image.isSuccess)return saveInvestmentAwareEditorTransaction(owner,draft,primaryCurrency,adjustmentTitle,deviceId,now,
        repository,receipts,image.getOrNull(),receiptState.deleteStoredOnSave)
    val missing=requireNotNull(image.exceptionOrNull())
    // Process recreation may lose only the in-memory image after both durable saves already succeeded.
    // This path proves that result; it never creates a transaction or replaces/deletes a receipt.
    val identity=draft.creationIdentity
    if(draft.id!=null || identity==null)return Result.failure(missing)
    try {
        val request=TransactionInvestmentSaveRequest(draft,identity,draft.investmentConsent,adjustmentTitle,primaryCurrency)
        val prepared=repository.prepareTransactionWithInvestmentFunds(owner,request,deviceId,now).getOrThrow()
        if(prepared.mutations.isNotEmpty())return Result.failure(missing)
        val key=identity.id
        val stored=receipts.receipt(key) ?: return Result.failure(missing)
        require(stored.ownerUserId==owner.value && stored.transactionId==key && stored.contentType=="image/jpeg"){"Completed receipt ownership/type mismatch"}
        val bytes=receipts.imageData(stored).getOrThrow();val thumbnail=receipts.thumbnailData(stored).getOrThrow()
        require(bytes.isNotEmpty() && stored.byteCount==bytes.size && thumbnail.isNotEmpty()){ "Completed receipt files are unavailable" }
        currentCoroutineContext().ensureActive()
        val current=repository.prepareTransactionWithInvestmentFunds(owner,request,deviceId,now).getOrThrow()
        require(current.mutations.isEmpty() && current.record.id==prepared.record.id){"Completed creation changed during receipt recovery"}
        return Result.success(current.record)
    } catch(error:CancellationException){throw error}
      catch(error:Throwable){if(error!==missing)missing.addSuppressed(error);return Result.failure(missing)}
}

internal suspend fun saveInvestmentAwareEditorTransaction(owner:UserId,draft:TransactionDraft,primaryCurrency:String,adjustmentTitle:String,
    deviceId:String,now:String,repository:FinanceRepository,receipts:TransactionReceiptImageRepository,
    newReceiptImage:PreparedReceiptImage?=null,deleteStoredReceipt:Boolean=false):Result<LedgerTransactionRecord> {
    try {
        currentCoroutineContext().ensureActive()
        require(draft.id!=null || draft.creationIdentity!=null){"A new editor save requires a stable creation identity"}
        val request=TransactionInvestmentSaveRequest(draft,if(draft.id==null)draft.creationIdentity else null,draft.investmentConsent,adjustmentTitle,primaryCurrency)
        suspend fun prepare()=repository.prepareTransactionWithInvestmentFunds(owner,request,deviceId,now).getOrThrow()
        val prepared=prepare() // Financial validation and fund consent precede every receipt side effect.
        suspend fun ownedReceipt(key:String):TransactionReceiptImageRecord? {
            val stored=receipts.receipt(key)
            require(stored==null || (stored.ownerUserId==owner.value && stored.transactionId==key)){"Receipt ownership mismatch"}
            return stored
        }
        if(newReceiptImage!=null) {
            require(draft.id==null && !deleteStoredReceipt){"Receipt-backed editor save only creates new transactions"}
            val key=requireNotNull(draft.creationIdentity).id
            suspend fun matchingReceipt():TransactionReceiptImageRecord? {
                val stored=ownedReceipt(key) ?: return null
                require(stored.contentType==newReceiptImage.mimeType &&
                    receipts.imageData(stored).getOrThrow().contentEquals(newReceiptImage.imageData) &&
                    receipts.thumbnailData(stored).getOrThrow().contentEquals(newReceiptImage.thumbnailData)){"Stable receipt identity contains another image"}
                return stored
            }
            suspend fun completed(plan:TransactionInvestmentSavePlan):LedgerTransactionRecord? {
                if(plan.mutations.isNotEmpty())return null
                require(matchingReceipt()!=null){"Completed transaction receipt is unavailable"}
                return plan.record
            }
            var staged:TransactionReceiptImageRecord?=null
            return saveReceiptBackedTransaction(draft,newReceiptImage,{error("Stable identity already assigned")},
                preflight={runCatching{matchingReceipt();completed(prepared)}},
                persistReceipt={_,image->runCatching {
                    if(matchingReceipt()==null)staged=receipts.createReceiptIfAbsent(owner,key,image.imageData,image.thumbnailData,image.mimeType,now).getOrThrow()
                }},
                saveTransaction={savedDraft->repository.saveTransactionWithInvestmentFunds(owner,request.copy(draft=savedDraft),deviceId,now)},
                recoverCommitted={runCatching{completed(prepare())}},
                deleteReceipt={runCatching {
                    val stagedHere=staged
                    if(stagedHere!=null) {
                        // An owner switch cannot authorize cleanup; a committed primary must retain its image even when proof is stale.
                        repository.prepareTransactionWithInvestmentFunds(owner,request,deviceId,now).exceptionOrNull()?.let{if(it is CancellationException)throw it}
                        if(repository.observeTransactions(owner).first().none{it.id==key}) {
                            val current=ownedReceipt(key)
                            require(current==null || current.id==stagedHere.id){"Staged receipt was replaced"}
                            if(current!=null)receipts.deleteReceiptIfUnchanged(owner,stagedHere).getOrThrow()
                        }
                    }
                }})
        }
        if(deleteStoredReceipt) {
            val key=requireNotNull(draft.id){"Stored receipt deletion requires an existing transaction"}
            val expected=ownedReceipt(key)
            return saveTransactionThenDeleteReceipt(key,
                saveTransaction={repository.saveTransactionWithInvestmentFunds(owner,request,deviceId,now)},
                deleteReceipt={runCatching {
                    val current=ownedReceipt(key)
                    require(current==null || (expected!=null && current.id==expected.id)){"Receipt changed during transaction save"}
                    if(current!=null)receipts.deleteReceiptIfUnchanged(owner,requireNotNull(expected)).getOrThrow()
                }})
        }
        return repository.saveTransactionWithInvestmentFunds(owner,request,deviceId,now)
    } catch(error:CancellationException){throw error}
      catch(error:Throwable){return Result.failure(error)}
}
