package vn.com.quyln.mistia.feature.overview

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import vn.com.quyln.mistia.core.designsystem.*
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@Composable
internal fun OverviewUpcomingDues(rows:List<UpcomingRecurringDueAlert>?,failed:Boolean,onRetry:()->Unit,onSelect:(UpcomingRecurringDueAlert)->Unit,enabled:Boolean,zone:ZoneId) {
    val dark=MaterialTheme.colorScheme.surface.luminance()<0.5f
    val locale=LocalConfiguration.current.locales[0]
    Column(Modifier.fillMaxWidth().testTag("overview.due.section"),verticalArrangement=Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.overview_overview_upcoming_due_items).uppercase(locale),fontSize=13.sp,lineHeight=16.sp,letterSpacing=0.6.sp,
            fontWeight=FontWeight.Bold,color=if(dark) Color.White.copy(alpha=0.66f) else Color(0.36f,0.37f,0.43f))
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(if(dark) Color(0xFF1C1C1E) else Color.White).testTag("overview.due.card")) {
            if(rows==null) Text(stringResource(R.string.overview_overview_reporting_amount_unavailable),Modifier.padding(14.dp).testTag("overview.due.unavailable"),
                style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            if(failed) TextButton(onClick=onRetry,modifier=Modifier.padding(horizontal=14.dp).testTag("overview.due.retry")) {Text(stringResource(R.string.planning_installment_retry))}
            rows.orEmpty().forEachIndexed {index,row ->
                OverviewUpcomingDueRow(row,enabled,zone) {onSelect(row)}
                if(index<rows.orEmpty().lastIndex) HorizontalDivider(Modifier.padding(start=48.dp))
            }
        }
    }
}

@Composable
private fun OverviewUpcomingDueRow(row:UpcomingRecurringDueAlert,enabled:Boolean,zone:ZoneId,onSelect:()->Unit) {
    val locale=LocalConfiguration.current.locales[0]
    val hex=if(row.urgent) "#F45C7E" else "#5B7BFF"
    val tint=categoryColorFromHex(hex)
    val amount=row.amountMinor?.let {formatMinorUnits(it,row.currencyCode)} ?: stringResource(R.string.overview_overview_no_amount_yet)
    val size=if(row.amountMinor==null) 11.sp else 16.sp
    val style=TextStyle(fontSize=size,lineHeight=if(row.amountMinor==null) 14.sp else 20.sp,fontWeight=if(row.amountMinor==null) FontWeight.SemiBold else FontWeight.Bold)
    val measured=rememberTextMeasurer().measure(AnnotatedString(amount),style=style)
    val density=LocalDensity.current
    val day=if(row.dayDelta==0) stringResource(R.string.overview_overview_due_today) else stringResource(R.string.overview_overview_value_days_left,row.dayDelta.toString())
    val date=row.alertDate.atZone(zone).toLocalDate().format(DateTimeFormatter.ofLocalizedDate(FormatStyle.SHORT).withLocale(locale))
    val amountContent:@Composable ()->Unit={Text(amount,Modifier.testTag("overview.due.amount.${row.id}"),style=style,
        color=if(row.amountMinor==null) MaterialTheme.colorScheme.onSurfaceVariant else if(row.urgent) tint else MaterialTheme.colorScheme.onSurface)}
    BoxWithConstraints(Modifier.fillMaxWidth().clickable(enabled=enabled,onClick=onSelect).testTag("overview.due.row.${row.id}").padding(horizontal=14.dp,vertical=12.dp)) {
        val stacked=measured.size.width>with(density){(maxWidth-54.dp).toPx()*0.6f}
        Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(12.dp),verticalAlignment=Alignment.CenterVertically) {
            val option=CategoryIconCatalog.load(LocalContext.current).option(row.icon)
            CategoryIcon(row.icon,TransactionCategoryKind.EXPENSE,option?.colorHex ?: hex,Modifier.size(30.dp).testTag("overview.due.icon.${row.id}"),
                shape=RoundedCornerShape(9.6.dp),glyphSize=if(option==null) 11.4.dp else 12.6.dp,backgroundAlpha=0.14f)
            Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(4.dp)) {
                Text(row.name,fontSize=16.sp,lineHeight=20.sp,fontWeight=FontWeight.SemiBold)
                Text("$date • $day",Modifier.testTag("overview.due.detail.${row.id}"),fontSize=11.sp,lineHeight=14.sp,fontWeight=FontWeight.SemiBold,
                    color=if(row.urgent) tint else MaterialTheme.colorScheme.onSurfaceVariant)
                if(stacked) amountContent()
            }
            if(!stacked) amountContent()
        }
    }
}
