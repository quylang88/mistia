package vn.com.quyln.mistia.core.designsystem

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Currency
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull
import vn.com.quyln.mistia.core.model.CloudRecord

fun CloudRecord.string(field: String): String? =
    (payload[field] as? JsonPrimitive)?.contentOrNull?.takeUnless { it.isBlank() }

fun CloudRecord.long(field: String): Long? =
    (payload[field] as? JsonPrimitive)?.longOrNull

fun formatMinorUnits(minor: Long, currencyCode: String): String {
    val currency = runCatching { Currency.getInstance(currencyCode) }.getOrNull()
    val fractionDigits = currency?.defaultFractionDigits?.coerceAtLeast(0) ?: 0
    val value = BigDecimal.valueOf(minor).movePointLeft(fractionDigits)
    return runCatching {
        NumberFormat.getCurrencyInstance().apply { this.currency = currency }.format(value)
    }.getOrElse { "$value $currencyCode" }
}

@Composable
fun MistiaRecordRow(
    title: String,
    subtitle: String? = null,
    trailing: String? = null,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.fillMaxWidth().padding(vertical = 10.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (!subtitle.isNullOrBlank()) {
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (!trailing.isNullOrBlank()) {
            Spacer(Modifier.width(12.dp))
            Text(text = trailing, style = MaterialTheme.typography.labelLarge)
        }
    }
}

@Composable
fun MistiaSectionCard(
    title: String,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    MistiaGlassCard(modifier = modifier) { padding: PaddingValues ->
        Column(Modifier.padding(padding)) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            content()
        }
    }
}
