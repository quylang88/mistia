package vn.com.quyln.mistia.core.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.TrendingDown
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import vn.com.quyln.mistia.core.model.TransactionCategoryKind

@Composable
fun CategoryIcon(
    symbolName: String,
    kind: TransactionCategoryKind?,
    colorHex: String,
    modifier: Modifier = Modifier,
) {
    val iconCatalog = CategoryIconCatalog.load(LocalContext.current)
    Box(
        modifier = modifier.clip(CircleShape).background(categoryColorFromHex(colorHex).copy(alpha = 0.18f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            categoryIcon(symbolName, kind, iconCatalog.option(symbolName)?.fallbackIcon ?: symbolName),
            contentDescription = null,
            tint = categoryColorFromHex(colorHex),
            modifier = Modifier.size(24.dp),
        )
    }
}

private fun categoryIcon(
    symbolName: String,
    kind: TransactionCategoryKind?,
    fallbackIcon: String?,
): ImageVector = when (symbolName) {
    "mistia.flow.expense" -> Icons.AutoMirrored.Filled.TrendingDown
    "mistia.flow.income" -> Icons.AutoMirrored.Filled.TrendingUp
    else -> when (categoryIconFamily(fallbackIcon, kind)) {
        CategoryIconFamily.FOOD -> Icons.Default.Restaurant
        CategoryIconFamily.HOME -> Icons.Default.Home
        CategoryIconFamily.TRANSPORT -> Icons.Default.DirectionsCar
        CategoryIconFamily.SHOPPING -> Icons.Default.ShoppingBag
        CategoryIconFamily.HEALTH -> Icons.Default.MedicalServices
        CategoryIconFamily.WORK -> Icons.Default.Work
        CategoryIconFamily.GIFT -> Icons.Default.CardGiftcard
        CategoryIconFamily.INCOME -> Icons.AutoMirrored.Filled.TrendingUp
        CategoryIconFamily.OTHER -> Icons.Default.MoreHoriz
    }
}

fun categoryColorFromHex(raw: String): Color {
    val value = raw.removePrefix("#").toLongOrNull(16) ?: 0x8A8A8E
    return Color(red = ((value shr 16) and 255) / 255f, green = ((value shr 8) and 255) / 255f, blue = (value and 255) / 255f)
}
