package vn.com.quyln.mistia.feature.transactions

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.time.Instant
import java.util.UUID
import java.util.concurrent.CancellationException
import vn.com.quyln.mistia.core.designsystem.MistiaGlassCard
import vn.com.quyln.mistia.core.designsystem.MistiaRecordRow
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.FinanceRepository
import vn.com.quyln.mistia.core.model.ExchangeRateRepository
import vn.com.quyln.mistia.core.model.ReceiptAnalysisClient
import vn.com.quyln.mistia.core.model.TransactionReceiptImageRepository
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.isLockedByPaidCreditCardStatement
import vn.com.quyln.mistia.core.model.transactionDisplayMoney

@Composable
fun TransactionsScreen(
    ownerUserId: UserId,
    repository: FinanceRepository,
    exchangeRateRepository: ExchangeRateRepository,
    receiptAnalysisClient: ReceiptAnalysisClient,
    receiptImageRepository: TransactionReceiptImageRepository,
    accessTokenProvider: suspend () -> String?,
    deviceIdProvider: suspend () -> String,
    modifier: Modifier = Modifier,
) {
    val records by repository.observeTransactions(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val wallets by repository.observeWallets(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val categories by repository.observeCategories(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val creditCardProfiles by repository.observeCreditCardProfiles(ownerUserId)
        .collectAsStateWithLifecycle(emptyList())
    val dueOccurrences by repository.observe(CloudEntity.DUE_OCCURRENCE_RECORD, ownerUserId)
        .collectAsStateWithLifecycle(emptyList())
    val exchangeRates by exchangeRateRepository.rates.collectAsStateWithLifecycle()
    LaunchedEffect(exchangeRateRepository) {
        exchangeRateRepository.refreshIfStale()
    }
    var editorOpen by rememberSaveable { mutableStateOf(false) }
    var editorTransactionId by rememberSaveable { mutableStateOf<String?>(null) }
    var editorInitialState by remember { mutableStateOf<TransactionEditorState?>(null) }
    var editorReceiptState by rememberSaveable(stateSaver = TransactionReceiptEditorState.Saver) {
        mutableStateOf(TransactionReceiptEditorState.none())
    }
    var editorReceiptLoading by remember { mutableStateOf(false) }
    var editorReceiptLoadFailed by remember { mutableStateOf(false) }
    var receiptOpen by rememberSaveable { mutableStateOf(false) }
    val walletCurrencies = wallets.associate { it.id to it.currencyCode }
    LaunchedEffect(editorOpen, editorTransactionId, editorReceiptState.deleteStoredOnSave) {
        val transactionId = editorTransactionId
        if (!editorOpen || transactionId == null || editorReceiptState.deleteStoredOnSave ||
            editorReceiptState.preview != null
        ) {
            editorReceiptLoading = false
            return@LaunchedEffect
        }
        editorReceiptLoading = true
        editorReceiptLoadFailed = false
        try {
            val loadResult = loadStoredReceiptEditorState(
                transactionId = transactionId,
                initialState = editorReceiptState,
                loadRecord = receiptImageRepository::receipt,
                loadImageData = receiptImageRepository::imageData,
                loadThumbnailData = receiptImageRepository::thumbnailData,
            )
            editorReceiptState = loadResult.state
            editorReceiptLoadFailed = loadResult.error != null
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (_: Throwable) {
            editorReceiptLoadFailed = true
        } finally {
            editorReceiptLoading = false
        }
    }
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = stringResource(R.string.app_roottab_transactions),
                    style = MaterialTheme.typography.headlineMedium,
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    OutlinedButton(
                        onClick = { receiptOpen = true },
                        modifier = Modifier.weight(1f),
                    ) {
                        Text(stringResource(R.string.transactions_aibill_ai_bill))
                    }
                    Button(
                        onClick = {
                            editorTransactionId = null
                            editorInitialState = null
                            editorReceiptState = TransactionReceiptEditorState.none()
                            editorReceiptLoadFailed = false
                            editorOpen = true
                        },
                        modifier = Modifier.weight(1f),
                    ) {
                        Text(stringResource(R.string.shared_sync_mistiasynccoordinator_new_transaction))
                    }
                }
            }
        }
        if (records.isEmpty()) {
            item {
                MistiaGlassCard { padding ->
                    Text(
                        text = stringResource(R.string.transactions_transactions_no_transactions_yet),
                        modifier = Modifier.padding(padding),
                    )
                }
            }
        } else {
            items(records, key = { it.id }) { record ->
                val isLockedByPaidStatement = record.isLockedByPaidCreditCardStatement(
                    wallets = wallets,
                    creditCardProfiles = creditCardProfiles,
                    categories = categories,
                    transactions = records,
                    dueOccurrences = dueOccurrences,
                )
                val isEditable = record.supportsNativeTransactionEditor() && !isLockedByPaidStatement
                MistiaGlassCard(
                    modifier = Modifier.clickable(enabled = isEditable) {
                        editorTransactionId = record.id
                        editorInitialState = null
                        editorReceiptState = TransactionReceiptEditorState.none()
                        editorReceiptLoadFailed = false
                        editorOpen = true
                    },
                ) { padding ->
                    val money = record.transactionDisplayMoney(
                        walletCurrencies[record.sourceWalletId],
                        walletCurrencies[record.destinationWalletId],
                    )
                    MistiaRecordRow(
                        title = record.title.ifBlank {
                            stringResource(R.string.shared_corelogic_transaction_unknown_name)
                        },
                        subtitle = if (isLockedByPaidStatement) {
                            stringResource(
                                R.string.transactions_transactioneditor_this_transaction_is_part_of_a_paid
                            )
                        } else {
                            record.occurredAt
                        },
                        trailing = formatMinorUnits(money.minor, money.currencyCode),
                        modifier = Modifier.padding(padding),
                    )
                }
            }
        }
    }

    if (receiptOpen) {
        ReceiptAnalysisSheet(
            ownerUserId = ownerUserId.value,
            categories = categories,
            wallets = wallets,
            client = receiptAnalysisClient,
            accessTokenProvider = accessTokenProvider,
            onCreateTransaction = { launch ->
                val currencyCode = wallets.firstOrNull { it.id == launch.draft.walletId }?.currencyCode
                val prefill = currencyCode?.let(launch.draft::toExpenseEditorState)
                if (prefill != null) {
                    receiptOpen = false
                    editorTransactionId = null
                    editorInitialState = prefill
                    editorReceiptState = TransactionReceiptEditorState.pending(launch.receiptImage)
                    editorReceiptLoadFailed = false
                    editorOpen = true
                }
            },
            onDismiss = { receiptOpen = false },
        )
    }

    if (editorOpen) {
        val transaction = editorTransactionId?.let { id -> records.firstOrNull { it.id == id } }
        if (editorTransactionId == null || transaction != null) {
            TransactionEditorSheet(
                transaction = transaction,
                wallets = wallets,
                categories = categories,
                exchangeRates = exchangeRates,
                now = Instant.now().toString(),
                initialState = editorInitialState,
                receiptState = editorReceiptState,
                receiptLoading = editorReceiptLoading,
                receiptLoadFailed = editorReceiptLoadFailed,
                onRemoveReceipt = {
                    editorReceiptState = editorReceiptState.remove()
                    editorReceiptLoadFailed = false
                },
                onDismiss = {
                    editorOpen = false
                    editorInitialState = null
                    editorReceiptState = TransactionReceiptEditorState.none()
                    editorReceiptLoadFailed = false
                },
                onSave = { draft ->
                    val now = Instant.now().toString()
                    val deviceId = deviceIdProvider()
                    editorReceiptState.newReceiptImageForSave().fold(
                        onSuccess = { receiptImage ->
                            if (receiptImage == null) {
                                if (editorReceiptState.deleteStoredOnSave) {
                                    val transactionId = draft.id
                                    if (transactionId == null) {
                                        Result.failure(
                                            IllegalStateException("Stored receipt deletion requires a transaction ID"),
                                        )
                                    } else {
                                        saveTransactionThenDeleteReceipt(
                                            transactionId = transactionId,
                                            saveTransaction = {
                                                repository.saveTransaction(
                                                    ownerUserId = ownerUserId,
                                                    draft = draft,
                                                    deviceId = deviceId,
                                                    now = now,
                                                )
                                            },
                                            deleteReceipt = receiptImageRepository::deleteReceipt,
                                        )
                                    }
                                } else {
                                    repository.saveTransaction(
                                        ownerUserId = ownerUserId,
                                        draft = draft,
                                        deviceId = deviceId,
                                        now = now,
                                    )
                                }
                            } else {
                                saveReceiptBackedTransaction(
                                    draft = draft,
                                    receiptImage = receiptImage,
                                    transactionIdProvider = { UUID.randomUUID().toString().lowercase() },
                                    persistReceipt = { transactionId, image ->
                                        receiptImageRepository.replaceReceipt(
                                            ownerUserId = ownerUserId,
                                            transactionId = transactionId,
                                            imageData = image.imageData,
                                            thumbnailData = image.thumbnailData,
                                            contentType = image.mimeType,
                                            now = now,
                                        ).map { Unit }
                                    },
                                    saveTransaction = { transactionDraft ->
                                        repository.saveTransaction(
                                            ownerUserId = ownerUserId,
                                            draft = transactionDraft,
                                            deviceId = deviceId,
                                            now = now,
                                        )
                                    },
                                    deleteReceipt = receiptImageRepository::deleteReceipt,
                                )
                            }
                        },
                        onFailure = { Result.failure(it) },
                    )
                },
            )
        }
    }
}
