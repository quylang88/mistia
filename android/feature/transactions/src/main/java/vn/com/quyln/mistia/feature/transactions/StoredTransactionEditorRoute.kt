package vn.com.quyln.mistia.feature.transactions

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.combine
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

private data class StoredEditorRecords(val transactions:List<CloudRecord>,val wallets:List<LedgerWalletRecord>,
    val categories:List<TransactionCategoryRecord>,val cards:List<CreditCardProfileRecord>,val occurrences:List<CloudRecord>)
private sealed interface StoredEditorLoad {
    data object Loading:StoredEditorLoad
    data class Ready(val records:StoredEditorRecords):StoredEditorLoad
    data object Failed:StoredEditorLoad
}

/** Only an owned stored identity can reach this route; it never falls back to a creation form. */
@Composable fun StoredTransactionEditorRoute(owner:UserId,recordId:String,repository:FinanceRepository,exchangeRates:ExchangeRateRepository,
    receiptImages:TransactionReceiptImageRepository,deviceIdProvider:suspend ()->String,primaryCurrencyCode:String="JPY",onDismiss:()->Unit) {
    key(owner.value,recordId) {OwnedStoredTransactionEditor(owner,recordId,repository,exchangeRates,receiptImages,deviceIdProvider,primaryCurrencyCode,onDismiss)}
}

@Composable private fun OwnedStoredTransactionEditor(owner:UserId,recordId:String,repository:FinanceRepository,exchangeRates:ExchangeRateRepository,
    receiptImages:TransactionReceiptImageRepository,deviceIdProvider:suspend ()->String,primaryCurrencyCode:String,onDismiss:()->Unit) {
    val investmentAdjustmentTitle=stringResource(R.string.investment_wallet_history_adjustment)
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    var retry by remember {mutableIntStateOf(0)}
    val load by produceState<StoredEditorLoad>(StoredEditorLoad.Loading,repository,retry,lifecycle) {
        value=StoredEditorLoad.Loading
        try {
            lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                combine(repository.observe(CloudEntity.LEDGER_TRANSACTION,owner),repository.observeWallets(owner),repository.observeCategories(owner),
                    repository.observeCreditCardProfiles(owner),repository.observe(CloudEntity.DUE_OCCURRENCE_RECORD,owner)) {transactions,wallets,categories,cards,occurrences ->
                    StoredEditorRecords(transactions,wallets.filter {it.ownerUserId==owner.value},categories.filter {it.ownerUserId==owner.value},
                        cards.filter {it.ownerUserId==owner.value},occurrences.filter {it.ownerUserId==owner.value})
                }.collect {value=StoredEditorLoad.Ready(it)}
            }
        } catch(cancelled:CancellationException) {throw cancelled}
          catch(_:Exception) {value=StoredEditorLoad.Failed}
    }
    val records=(load as? StoredEditorLoad.Ready)?.records
    val raw=records?.transactions?.singleOrNull {it.id==recordId && it.ownerUserId==owner.value && it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.deletedAt==null}
    val transaction=raw?.let {
        if((it.payload["amount_minor"] as? JsonPrimitive)?.longOrNull==null) null
        else runCatching {LedgerTransactionRecord.fromCloudRecord(it)}.getOrNull()
            ?.takeIf {record -> record.ownerUserId==owner.value && record.id==recordId && record.deletedAt==null && !record.isArchived &&
                runCatching {Instant.parse(record.occurredAt);Instant.parse(record.createdAt);true}.getOrDefault(false)}
    }
    val typedRecords=records?.transactions.orEmpty().filter {it.ownerUserId==owner.value}.mapNotNull {rawRecord ->
        runCatching {LedgerTransactionRecord.fromCloudRecord(rawRecord)}.getOrNull()?.takeIf {it.ownerUserId==owner.value && it.id==rawRecord.id}
    }
    val locked=transaction!=null && records!=null && transaction.isLockedByPaidCreditCardStatement(records.wallets,records.cards,records.categories,typedRecords,records.occurrences)
    val supported=transaction?.supportsNativeTransactionEditor()==true
    var archiveTarget by remember(repository,receiptImages){mutableStateOf<LedgerTransactionRecord?>(null)}
    archiveTarget?.let{expected->TransactionLifecycleActionDialog(owner,expected,TransactionLifecycleAction.ARCHIVE,repository,receiptImages,
        records?.wallets.orEmpty(),deviceIdProvider,primaryCurrencyCode,onDone={archiveTarget=null;onDismiss()},onDismiss={archiveTarget=null})}
    if(load !is StoredEditorLoad.Ready || transaction==null || locked || !supported) {
        if(archiveTarget==null)StoredEditorStatus(loading=load==StoredEditorLoad.Loading,failed=load==StoredEditorLoad.Failed,
            message=when {locked -> R.string.transactions_transactioneditor_this_transaction_is_part_of_a_paid
                transaction!=null && !supported -> R.string.transactions_stored_editor_unsupported
                else -> R.string.transactions_stored_editor_unavailable},onRetry={retry++},onDismiss=onDismiss)
        return
    }
    val rates by exchangeRates.rates.collectAsStateWithLifecycle()
    LaunchedEffect(exchangeRates) {exchangeRates.refreshIfStale()}
    var receipt by rememberSaveable(owner.value,recordId,stateSaver=TransactionReceiptEditorState.Saver) {mutableStateOf(TransactionReceiptEditorState.none())}
    var receiptLoading by remember {mutableStateOf(true)}
    var receiptError by remember {mutableStateOf(false)}
    LaunchedEffect(receiptImages,receipt.deleteStoredOnSave) {
        if(receipt.deleteStoredOnSave) {receiptLoading=false;return@LaunchedEffect}
        receiptLoading=true;receiptError=false
        val loaded=loadStoredReceiptEditorState(recordId,receipt,
            loadRecord={id ->
                currentCoroutineContext().ensureActive()
                val stored=receiptImages.receipt(id)
                currentCoroutineContext().ensureActive()
                stored?.also {require(it.ownerUserId==owner.value && it.transactionId==recordId) {"Receipt ownership mismatch"}}
            },loadImageData=receiptImages::imageData,loadThumbnailData=receiptImages::thumbnailData)
        currentCoroutineContext().ensureActive()
        receipt=loaded.state;receiptError=loaded.error!=null;receiptLoading=false
    }
    TransactionEditorSheet(owner.value,transaction,records.wallets,records.categories,rates,Instant.now().toString(),primaryCurrencyCode,
        receiptState=receipt,receiptLoading=receiptLoading,receiptLoadFailed=receiptError,
        onRemoveReceipt={receipt=receipt.remove();receiptError=false},onDismiss=onDismiss,
        saveSessionKey=repository to receiptImages,onArchive={archiveTarget=transaction},onSave={draft ->
            currentCoroutineContext().ensureActive()
            require(draft.id==recordId) {"Stored transaction identity changed"}
            val saved=saveInvestmentAwareEditorTransaction(owner,draft,primaryCurrencyCode,investmentAdjustmentTitle,
                deviceIdProvider(),Instant.now().toString(),repository,receiptImages,deleteStoredReceipt=receipt.deleteStoredOnSave)
            currentCoroutineContext().ensureActive()
            saved
        })
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun StoredEditorStatus(loading:Boolean,failed:Boolean,message:Int,onRetry:()->Unit,onDismiss:()->Unit) {
    ModalBottomSheet(onDismissRequest=onDismiss) {
        Column(Modifier.fillMaxWidth().padding(24.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
            if(loading) {CircularProgressIndicator();Text(stringResource(R.string.transactions_stored_editor_loading),Modifier.testTag("transaction.stored.loading"))}
            else Text(stringResource(message),Modifier.testTag("transaction.stored.unavailable"))
            if(failed) TextButton(onClick=onRetry,modifier=Modifier.testTag("transaction.stored.retry")) {Text(stringResource(R.string.planning_installment_retry))}
            TextButton(onClick=onDismiss) {Text(stringResource(R.string.common_close))}
        }
    }
}
