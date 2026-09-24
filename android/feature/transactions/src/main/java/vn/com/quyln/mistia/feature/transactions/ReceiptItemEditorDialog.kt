package vn.com.quyln.mistia.feature.transactions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.BillItemAnalysisItem
import vn.com.quyln.mistia.core.model.BillItemLineType

@Composable
internal fun ReceiptItemEditorDialog(
    billId: String,
    item: BillItemAnalysisItem,
    currencyCode: String,
    onDismiss: () -> Unit,
    onDelete: () -> Unit,
    onSave: (BillItemAnalysisItem) -> Unit,
) {
    var draft by remember(billId, item.lineId) {
        mutableStateOf(ReceiptItemEditorState.from(item, currencyCode))
    }
    val reviewedItem = draft.reviewedItem()
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.transactions_aibill_edit_item)) },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 520.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(
                    text = stringResource(R.string.transactions_aibill_item_details),
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                )
                OutlinedTextField(
                    value = draft.originalName,
                    onValueChange = { draft = draft.copy(originalName = it) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.transactions_aibill_original_name)) },
                    isError = draft.originalName.isBlank(),
                )
                OutlinedTextField(
                    value = draft.translatedName,
                    onValueChange = { draft = draft.copy(translatedName = it) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.transactions_aibill_translated_name)) },
                )
                Text(
                    text = stringResource(R.string.transactions_aibill_line_type),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = draft.lineType == BillItemLineType.PURCHASE,
                        onClick = { draft = draft.copy(lineType = BillItemLineType.PURCHASE) },
                        label = { Text(stringResource(R.string.transactions_aibill_purchase_line)) },
                    )
                    FilterChip(
                        selected = draft.lineType == BillItemLineType.DISCOUNT,
                        onClick = { draft = draft.copy(lineType = BillItemLineType.DISCOUNT) },
                        label = { Text(stringResource(R.string.transactions_aibill_discount_line)) },
                    )
                }
                if (draft.lineType == BillItemLineType.PURCHASE) {
                    OutlinedTextField(
                        value = draft.quantityText,
                        onValueChange = { draft = draft.copy(quantityText = it) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.transactions_aibill_quantity)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = draft.originalAmountText,
                        onValueChange = { draft = draft.copy(originalAmountText = it) },
                        modifier = Modifier.fillMaxWidth(),
                        label = {
                            Text(
                                "${stringResource(R.string.transactions_aibill_original_row_amount)} " +
                                    "($currencyCode)",
                            )
                        },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true,
                    )
                }
                OutlinedTextField(
                    value = draft.discountAmountText,
                    onValueChange = { draft = draft.copy(discountAmountText = it) },
                    modifier = Modifier.fillMaxWidth(),
                    label = {
                        Text(
                            "${stringResource(R.string.transactions_aibill_discount_amount)} " +
                                "($currencyCode)",
                        )
                    },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                )
                reviewedItem?.let { reviewed ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(stringResource(R.string.transactions_aibill_final_row_amount))
                        Text(
                            text = formatMinorUnits(reviewed.finalAmountMinor, currencyCode),
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
                Text(
                    text = stringResource(R.string.transactions_aibill_row_amount_help),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                item.rawLineText?.let { rawLineText ->
                    Text(
                        text = stringResource(R.string.transactions_aibill_printed_text),
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = rawLineText,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                TextButton(onClick = onDelete) {
                    Text(
                        text = stringResource(R.string.transactions_aibill_remove_item),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.common_cancel))
            }
        },
        confirmButton = {
            TextButton(
                onClick = { reviewedItem?.let(onSave) },
                enabled = reviewedItem != null,
            ) {
                Text(stringResource(R.string.common_save))
            }
        },
    )
}
