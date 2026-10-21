package vn.com.quyln.mistia.feature.overview

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode
import vn.com.quyln.mistia.core.designsystem.*
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@Composable
internal fun OverviewBudgetFocus(rows:List<BudgetBranchRow>?,failed:Boolean,onRetry:()->Unit) {
    val dark=MaterialTheme.colorScheme.surface.luminance()<0.5f
    val locale=LocalConfiguration.current.locales[0]
    Column(Modifier.fillMaxWidth().testTag("overview.budget.focus"),verticalArrangement=Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.overview_overview_budget_watchlist).uppercase(locale),fontSize=13.sp,lineHeight=16.sp,letterSpacing=0.6.sp,
            fontWeight=FontWeight.Bold,color=if(dark) Color.White.copy(alpha=0.66f) else Color(0.36f,0.37f,0.43f))
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(if(dark) Color(0xFF1C1C1E) else Color.White).testTag("overview.budget.card")) {
            val unavailable=stringResource(R.string.overview_overview_reporting_amount_unavailable)
            if(rows==null || rows.any {it.spentMinor==null || it.limitMinor==null || it.currencyCode==null || it.pace.health==null}) {
                Text(unavailable,Modifier.padding(horizontal=14.dp,vertical=12.dp).testTag("overview.budget.unavailable"),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if(failed) TextButton(onClick=onRetry,modifier=Modifier.padding(horizontal=14.dp).testTag("overview.budget.retry")) {Text(stringResource(R.string.planning_installment_retry))}
            rows.orEmpty().forEachIndexed {index,row ->
                OverviewBudgetAlertRow(row)
                if(index<rows.orEmpty().lastIndex) HorizontalDivider(Modifier.padding(start=52.dp))
            }
        }
    }
}

@Composable
private fun OverviewBudgetAlertRow(row:BudgetBranchRow) {
    val known=row.spentMinor!=null && row.limitMinor!=null && row.currencyCode!=null && row.pace.health!=null
    val hex=if(!known) "#8A8A8E" else when(row.pace.health) {
        BudgetHealth.EXCEEDED -> "#F45C7E"
        BudgetHealth.CAUTION -> "#F59B3F"
        else -> "#2DAA9E"
    }
    val tint=categoryColorFromHex(hex)
    val currency=row.currencyCode
    fun money(value:BigInteger?)=if(value==null || currency==null) "—" else formatMinorUnits(value,currency)
    val progress=if(known && row.limitMinor!!.signum()>0) BigDecimal(row.spentMinor!!).divide(BigDecimal(row.limitMinor),24,RoundingMode.HALF_UP) else BigDecimal.ZERO
    val percent=if(!known) "—" else (if(row.limitMinor!!.signum()>0) BigDecimal(row.spentMinor!!).multiply(BigDecimal(100)).divide(BigDecimal(row.limitMinor),0,RoundingMode.HALF_UP).toBigIntegerExact() else BigInteger.ZERO).toString()+"%"
    Row(Modifier.fillMaxWidth().padding(horizontal=14.dp,vertical=12.dp).testTag("overview.budget.row.${row.id}"),horizontalArrangement=Arrangement.spacedBy(12.dp),verticalAlignment=Alignment.CenterVertically) {
        val option=CategoryIconCatalog.load(LocalContext.current).option(row.icon)
        CategoryIcon(row.icon,TransactionCategoryKind.EXPENSE,if(known) option?.colorHex ?: hex else hex,
            Modifier.size(30.dp).testTag("overview.budget.icon.${row.id}"),shape=RoundedCornerShape(9.6.dp),glyphSize=if(option==null) 11.4.dp else 12.6.dp,backgroundAlpha=0.14f)
        Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp),verticalAlignment=Alignment.Top) {
                Text(row.name,Modifier.weight(1f),fontSize=16.sp,lineHeight=20.sp,fontWeight=FontWeight.SemiBold)
                Text(percent,Modifier.widthIn(max=128.dp).testTag("overview.budget.percent.${row.id}"),color=tint,fontSize=14.sp,lineHeight=18.sp,fontWeight=FontWeight.Bold)
            }
            Text("${money(row.spentMinor)} / ${money(row.limitMinor)}",Modifier.testTag("overview.budget.money.${row.id}"),fontSize=12.sp,lineHeight=16.sp,fontWeight=FontWeight.SemiBold,color=MaterialTheme.colorScheme.onSurfaceVariant)
            if(known) LinearProgressIndicator(progress={progress.max(BigDecimal.ZERO).min(BigDecimal.ONE).toFloat()},modifier=Modifier.fillMaxWidth().testTag("overview.budget.progress.${row.id}"),color=tint,trackColor=tint.copy(alpha=0.16f),gapSize=0.dp,drawStopIndicator={})
            Text(stringResource(R.string.overview_overview_value_days_left,row.pace.daysRemaining.toString()),color=tint,fontSize=11.sp,lineHeight=14.sp,fontWeight=FontWeight.Bold)
        }
    }
}
