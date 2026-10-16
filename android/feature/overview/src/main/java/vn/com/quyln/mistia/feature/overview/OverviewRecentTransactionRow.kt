package vn.com.quyln.mistia.feature.overview

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SyncAlt
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import vn.com.quyln.mistia.core.designsystem.*
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.TransactionCategoryRecord

@OptIn(ExperimentalLayoutApi::class)
@Composable internal fun OverviewRecentTransactionRow(row:OverviewRecentRow,category:TransactionCategoryRecord?,reference:Instant,zone:ZoneId,modifier:Modifier=Modifier) {
    val style=overviewCashflow(row.transaction)
    val color=when(style) {
        OverviewCashflow.INCOME -> Color(0.18f,0.67f,0.62f)
        OverviewCashflow.EXPENSE -> Color(0.96f,0.36f,0.49f)
        OverviewCashflow.NEUTRAL -> if(MaterialTheme.colorScheme.surface.luminance()<0.5f) Color.White else Color(0.60f,0.60f,0.60f)
    }
    val prefix=when(style) {OverviewCashflow.INCOME -> "+";OverviewCashflow.EXPENSE -> "-";OverviewCashflow.NEUTRAL -> ""}
    val token=overviewRecentIcon(row.transaction,category)
    FlowRow(modifier.fillMaxWidth().padding(vertical=12.dp).testTag("overview.recent.${row.transaction.id}"),
        horizontalArrangement=Arrangement.SpaceBetween,verticalArrangement=Arrangement.spacedBy(8.dp),itemVerticalAlignment=Alignment.CenterVertically) {
        Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
            val iconModifier=Modifier.size(36.dp).testTag("overview.recent.icon.${row.transaction.id}.$token")
            if(token=="mistia.flow.transfer") Box(iconModifier.clip(CircleShape).background(color.copy(alpha=0.18f)),contentAlignment=Alignment.Center) {
                Icon(Icons.Default.SyncAlt,contentDescription=null,tint=color,modifier=Modifier.size(24.dp))
            } else CategoryIcon(token,category?.takeIf {it.ownerUserId==row.transaction.ownerUserId && it.id==row.transaction.categoryId}?.kind,
                String.format(Locale.ROOT,"#%06X",color.toArgb() and 0xffffff),iconModifier)
            Column(verticalArrangement=Arrangement.spacedBy(4.dp)) {
                Text(localizedTransactionTitle(row.transaction,category),fontSize=16.sp,fontWeight=FontWeight.SemiBold)
                Text(overviewRelativeTimeText(overviewRelativeTime(Instant.parse(row.transaction.occurredAt),reference,zone)),
                    fontSize=11.sp,fontWeight=FontWeight.SemiBold,color=MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier=Modifier.testTag("overview.recent.time.${row.transaction.id}"))
            }
        }
        Text(prefix+formatMinorUnits(row.money.minor,row.money.currencyCode),fontSize=15.sp,fontWeight=FontWeight.Bold,color=color,
            maxLines=1,softWrap=false,modifier=Modifier.testTag("overview.recent.amount.${row.transaction.id}"))
    }
}

@Composable private fun overviewRelativeTimeText(time:OverviewRelativeTime):String = when(time) {
    is OverviewRelativeTime.Minutes -> stringResource(R.string.shared_corelogic_mistialocalization_value_min_ago,time.count.toString())
    is OverviewRelativeTime.Hours -> stringResource(R.string.shared_corelogic_mistialocalization_value_hr_ago,time.count.toString())
    OverviewRelativeTime.Today -> stringResource(R.string.shared_corelogic_mistialocalization_today)
    OverviewRelativeTime.Yesterday -> stringResource(R.string.shared_corelogic_mistialocalization_yesterday)
    OverviewRelativeTime.TwoDaysAgo -> stringResource(R.string.shared_corelogic_mistialocalization_days_ago)
    is OverviewRelativeTime.Date -> time.value.format(DateTimeFormatter.ofPattern("dd/MM",Locale.ROOT))
}
