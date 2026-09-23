package vn.com.quyln.mistia.feature.transactions

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import vn.com.quyln.mistia.core.designsystem.MistiaGlassCard
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.BillItemAnalysisItem
import vn.com.quyln.mistia.core.model.BillItemLineType
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.ReceiptAnalysisClient
import vn.com.quyln.mistia.core.model.ReceiptAnalysisException
import vn.com.quyln.mistia.core.model.ReceiptAnalysisFailure
import vn.com.quyln.mistia.core.model.TransactionCategoryRecord

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ReceiptAnalysisSheet(
    ownerUserId: String,
    categories: List<TransactionCategoryRecord>,
    wallets: List<LedgerWalletRecord>,
    client: ReceiptAnalysisClient,
    accessTokenProvider: suspend () -> String?,
    onDismiss: () -> Unit,
) {
    var state by remember { mutableStateOf(ReceiptReviewState()) }
    var preparationFailure by remember { mutableStateOf(false) }
    var confirmDismiss by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val locale = Locale.getDefault()
    val eligibleCategoryIds = remember(ownerUserId, categories, locale) {
        receiptAnalysisCategoryCandidates(ownerUserId, categories, locale).map { it.id }.toSet()
    }
    val eligibleWalletIds = remember(ownerUserId, wallets) {
        receiptAnalysisWalletCandidates(ownerUserId, wallets).map { it.id }.toSet()
    }
    val isAnalyzing = state.bills.any(ReceiptReviewBill::isAnalyzing)

    fun appendResult(result: ReceiptPhotoSelectionResult) {
        state = state.append(result.images) { UUID.randomUUID().toString() }
        preparationFailure = result.failures.isNotEmpty() || result.rejectedCount > 0
    }

    fun analyze(source: ReceiptReviewState = state) {
        if (source.pendingBills.isEmpty() || isAnalyzing) return
        val batch = source.beginPendingAnalysis()
        state = batch.state
        scope.launch {
            try {
                val attempts = analyzePreparedReceipts(
                    images = batch.images,
                    context = ReceiptAnalysisRequestContext(
                        ownerUserId = ownerUserId,
                        categories = categories,
                        wallets = wallets,
                        locale = locale,
                        timeZoneIdentifier = TimeZone.getDefault().id,
                    ),
                    client = client,
                    accessTokenProvider = accessTokenProvider,
                )
                state = batch.complete(attempts, eligibleCategoryIds, eligibleWalletIds)
            } catch (error: CancellationException) {
                throw error
            } catch (error: ReceiptAnalysisException) {
                state = batch.fail(error)
            } catch (_: Exception) {
                state = batch.fail(
                    ReceiptAnalysisException(ReceiptAnalysisFailure.INVALID_RESPONSE),
                )
            }
        }
    }

    fun requestDismiss() {
        if (state.hasTransientAnalysis) {
            confirmDismiss = true
        } else {
            onDismiss()
        }
    }

    ModalBottomSheet(
        onDismissRequest = { if (!isAnalyzing) requestDismiss() },
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxHeight(0.94f),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = stringResource(R.string.transactions_aibill_ai_bill),
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    TextButton(onClick = ::requestDismiss, enabled = !isAnalyzing) {
                        Text(stringResource(R.string.common_cancel))
                    }
                }
            }

            item {
                Text(
                    text = stringResource(R.string.transactions_aibill_review_before_create),
                    modifier = Modifier.padding(horizontal = 20.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    ReceiptPhotoPickerButton(
                        existingImageCount = state.bills.size,
                        onResult = ::appendResult,
                        modifier = Modifier.weight(1f),
                        enabled = !isAnalyzing,
                    )
                    ReceiptCameraButton(
                        existingImageCount = state.bills.size,
                        onResult = ::appendResult,
                        onFailure = { preparationFailure = true },
                        modifier = Modifier.weight(1f),
                        enabled = !isAnalyzing,
                    )
                }
            }

            if (preparationFailure) {
                item {
                    Text(
                        text = stringResource(
                            R.string.transactions_transactioneditor_couldn_t_process_this_receipt_image,
                        ),
                        modifier = Modifier.padding(horizontal = 20.dp),
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }

            if (state.bills.isEmpty()) {
                item {
                    MistiaGlassCard(
                        modifier = Modifier.padding(horizontal = 20.dp),
                    ) { padding ->
                        Column(
                            modifier = Modifier.padding(padding),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Text(
                                text = stringResource(R.string.transactions_aibill_no_bills_title),
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                text = stringResource(R.string.transactions_aibill_no_bills_message),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            } else {
                itemsIndexed(state.bills, key = { _, bill -> bill.id }) { index, bill ->
                    ReceiptReviewBillCard(
                        bill = bill,
                        index = index,
                        wallets = wallets,
                        onRemove = { state = state.remove(bill.id) },
                        onRetry = {
                            val retryState = state.retry(bill.id)
                            state = retryState
                            analyze(retryState)
                        },
                        modifier = Modifier.padding(horizontal = 20.dp),
                    )
                }
            }

            if (eligibleCategoryIds.isEmpty() || eligibleWalletIds.isEmpty()) {
                item {
                    Text(
                        text = stringResource(
                            R.string.transactions_transactioneditor_you_need_available_categories_before_a_i_can,
                        ),
                        modifier = Modifier.padding(horizontal = 20.dp),
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }

            item {
                Button(
                    onClick = { analyze() },
                    enabled = state.pendingBills.isNotEmpty() &&
                        !isAnalyzing &&
                        eligibleCategoryIds.isNotEmpty() &&
                        eligibleWalletIds.isNotEmpty(),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp),
                ) {
                    if (isAnalyzing) {
                        CircularProgressIndicator(
                            modifier = Modifier
                                .padding(end = 8.dp)
                                .size(18.dp),
                            strokeWidth = 2.dp,
                        )
                    }
                    Text(
                        stringResource(
                            if (isAnalyzing) {
                                R.string.transactions_aibill_analyzing
                            } else {
                                R.string.transactions_aibill_analyze
                            },
                        ),
                    )
                }
            }
        }
    }

    if (confirmDismiss) {
        AlertDialog(
            onDismissRequest = { confirmDismiss = false },
            title = { Text(stringResource(R.string.transactions_aibill_ai_bill)) },
            text = { Text(stringResource(R.string.transactions_aibill_results_will_be_lost)) },
            confirmButton = {
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.transactions_aibill_discard_analysis))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmDismiss = false }) {
                    Text(stringResource(R.string.transactions_aibill_stay_here))
                }
            },
        )
    }
}

@Composable
private fun ReceiptReviewBillCard(
    bill: ReceiptReviewBill,
    index: Int,
    wallets: List<LedgerWalletRecord>,
    onRemove: () -> Unit,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val thumbnail = remember(bill.id) {
        BitmapFactory.decodeByteArray(
            bill.image.thumbnailData,
            0,
            bill.image.thumbnailData.size,
        )
    }
    val result = bill.result
    val currencyCode = result?.currencyCode ?: "JPY"
    MistiaGlassCard(modifier = modifier) { padding ->
        Column(
            modifier = Modifier.padding(padding),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (thumbnail != null) {
                    Image(
                        bitmap = thumbnail.asImageBitmap(),
                        contentDescription = stringResource(R.string.transactions_aibill_receipt_image),
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .size(54.dp)
                            .clip(RoundedCornerShape(12.dp)),
                    )
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = result?.merchantName ?: stringResource(
                            R.string.transactions_aibill_bill_value,
                            (index + 1).toString(),
                        ),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    result?.totalMinor?.let { total ->
                        Text(
                            text = formatMinorUnits(total, currencyCode),
                            style = MaterialTheme.typography.titleLarge,
                        )
                    }
                }
                if (bill.isAnalyzing) {
                    CircularProgressIndicator(modifier = Modifier.size(22.dp), strokeWidth = 2.dp)
                }
            }

            when {
                bill.isMultipleBillImage -> ReceiptErrorText(
                    stringResource(R.string.transactions_aibill_image_contains_multiple_bills),
                )
                bill.failure != null -> ReceiptErrorText(receiptFailureMessage(bill.failure))
            }

            if (result != null) {
                val walletName = wallets.firstOrNull { it.id == bill.selectedWalletId }?.name
                if (walletName != null) {
                    Text(
                        text = walletName,
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (result.requiresReview) {
                    Text(
                        text = stringResource(R.string.transactions_aibill_needs_review),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
                result.items.forEachIndexed { itemIndex, item ->
                    if (itemIndex > 0) HorizontalDivider()
                    ReceiptAnalysisItemRow(item, currencyCode)
                }
                result.rawText?.let { rawText ->
                    Text(
                        text = stringResource(R.string.transactions_aibill_printed_text),
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = rawText,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
            ) {
                if (result == null && !bill.isAnalyzing) {
                    TextButton(onClick = onRemove) {
                        Text(stringResource(R.string.transactions_transactioneditor_remove_image))
                    }
                }
                if ((result != null || bill.failure != null || bill.isMultipleBillImage) && !bill.isAnalyzing) {
                    OutlinedButton(onClick = onRetry) {
                        Text(stringResource(R.string.transactions_aibill_analyze_again))
                    }
                }
            }
        }
    }
}

@Composable
private fun ReceiptAnalysisItemRow(
    item: BillItemAnalysisItem,
    currencyCode: String,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                text = item.originalName.ifBlank {
                    stringResource(R.string.transactions_aibill_needs_review)
                },
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
            )
            Text(
                text = formatMinorUnits(item.finalAmountMinor, currencyCode),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
            )
        }
        item.rawLineText?.let { raw ->
            Text(
                text = raw,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            item.quantity?.let { quantity ->
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = stringResource(R.string.transactions_aibill_quantity),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = quantity.toString(),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            if (item.lineType == BillItemLineType.DISCOUNT) {
                Text(
                    text = stringResource(R.string.transactions_aibill_discount_line),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
            if (item.requiresReview) {
                Text(
                    text = stringResource(R.string.transactions_aibill_needs_review),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

@Composable
private fun receiptFailureMessage(failure: ReceiptAnalysisFailure): String = when (failure) {
    ReceiptAnalysisFailure.UNAUTHORIZED -> stringResource(
        R.string.shared_sync_receiptanalysis_sign_in_to_analyze_receipts,
    )
    ReceiptAnalysisFailure.IMAGE_TOO_LARGE -> stringResource(
        R.string.shared_sync_receiptanalysis_the_receipt_image_is_too_large_choose,
    )
    ReceiptAnalysisFailure.NETWORK -> stringResource(
        R.string.shared_sync_receiptanalysis_unstable_network_try_again,
    )
    ReceiptAnalysisFailure.DAILY_LIMIT_REACHED -> stringResource(
        R.string.shared_sync_receiptanalysis_you_ve_reached_today_s_receipt_scan2,
    )
    else -> stringResource(
        R.string.shared_sync_receiptanalysis_couldn_t_analyze_this_receipt_right_now,
    )
}

@Composable
private fun ReceiptErrorText(message: String) {
    Text(
        text = message,
        color = MaterialTheme.colorScheme.error,
        style = MaterialTheme.typography.bodySmall,
    )
}
