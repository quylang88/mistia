package vn.com.quyln.mistia.core.designsystem

import android.os.Build
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

object MistiaColors {
    val Purple = Color(0xFF7556D8)
    val PurpleDark = Color(0xFFB9A6FF)
    val Lavender = Color(0xFFECE7FF)
    val GroupedLight = Color(0xFFF5F3FA)
    val GroupedDark = Color(0xFF111016)
    val CardDark = Color(0xFF211F29)
    val Positive = Color(0xFF2D8B67)
    val Negative = Color(0xFFD04D5D)
}

private val LightColors = lightColorScheme(
    primary = MistiaColors.Purple,
    onPrimary = Color.White,
    primaryContainer = MistiaColors.Lavender,
    onPrimaryContainer = Color(0xFF241050),
    secondary = Color(0xFF5262A7),
    background = MistiaColors.GroupedLight,
    surface = Color.White,
    surfaceVariant = Color(0xFFEAE7F0),
    error = MistiaColors.Negative,
)

private val DarkColors = darkColorScheme(
    primary = MistiaColors.PurpleDark,
    onPrimary = Color(0xFF2D1768),
    primaryContainer = Color(0xFF49358D),
    onPrimaryContainer = Color(0xFFE8DFFF),
    secondary = Color(0xFFBAC3FF),
    background = MistiaColors.GroupedDark,
    surface = MistiaColors.CardDark,
    surfaceVariant = Color(0xFF373440),
    error = Color(0xFFFFB3BA),
)

@Composable
fun MistiaTheme(
    darkTheme: Boolean,
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = Typography(),
        content = content,
    )
}

val MistiaSpring = spring<Float>(
    dampingRatio = 0.88f,
    stiffness = Spring.StiffnessMediumLow,
)

@Composable
fun MistiaGlassCard(
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(16.dp),
    content: @Composable (PaddingValues) -> Unit,
) {
    val shape = RoundedCornerShape(22.dp)
    val color = if (Build.VERSION.SDK_INT >= 31) {
        MaterialTheme.colorScheme.surface.copy(alpha = 0.84f)
    } else {
        MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.96f)
    }
    Card(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(color)
            .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.55f), shape),
        shape = shape,
        colors = CardDefaults.cardColors(containerColor = color),
        elevation = CardDefaults.cardElevation(defaultElevation = if (Build.VERSION.SDK_INT >= 31) 2.dp else 0.dp),
    ) {
        content(contentPadding)
    }
}
