package vn.com.quyln.mistia.feature.overview

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.background
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.com.quyln.mistia.core.designsystem.*
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@Composable internal fun OverviewHeroMetrics(months:List<OverviewMonthlyCashflow>,currency:String,assetBalance:Long,weeks:List<OverviewWeekSpending>,categoryPages:List<OverviewCategorySpendingMonth>,overlayPresented:Boolean,onOpenExpenseDay:(java.time.LocalDate)->Unit) {
    val code=currency.trim().uppercase(java.util.Locale.ROOT).takeIf {it in CurrencyPreferences.supportedCurrencyCodes} ?: "JPY"
    var dismissToken by remember {mutableIntStateOf(0)}
    var categoryMode by remember {mutableStateOf(false)}
    var preferredWeek by remember {mutableStateOf(weeks.lastOrNull()?.start)}
    var preferredMonth by remember {mutableStateOf(categoryPages.lastOrNull()?.month ?: months.last().month)}
    val current=months.last()
    val availableWeeks=weeks.map {it.start}
    val availableMonths=categoryPages.map {it.month}
    // Reconcile both identities even while the other chart is composed.
    LaunchedEffect(availableWeeks) {if(preferredWeek !in availableWeeks) preferredWeek=availableWeeks.lastOrNull()}
    LaunchedEffect(availableMonths) {if(preferredMonth !in availableMonths) preferredMonth=availableMonths.lastOrNull() ?: current.month}
    val selectedMonth=if(categoryMode) (categoryPages.firstOrNull {it.month==preferredMonth} ?: categoryPages.lastOrNull())?.month ?: current.month else current.month
    val month=months.firstOrNull {it.month==selectedMonth} ?: OverviewMonthlyCashflow(selectedMonth,0,0)
    val historical=categoryMode && month.month!=current.month
    val controls:@Composable ()->Unit={OverviewChartModePicker(categoryMode) {categoryMode=it;dismissToken++}}
    MistiaGlassCard {padding ->
        Column(Modifier.padding(padding).fillMaxWidth(),verticalArrangement=Arrangement.spacedBy(18.dp)) {
            Column(Modifier.pointerInput(Unit) {detectTapGestures {dismissToken++}},verticalArrangement=Arrangement.spacedBy(7.dp)) {
                Text(stringResource(R.string.overview_overview_available_assets),fontSize=15.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                BasicText(formatMinorUnits(assetBalance,code),Modifier.fillMaxWidth().testTag("overview.assets"),
                    style=MaterialTheme.typography.headlineLarge.copy(color=MaterialTheme.colorScheme.onSurface,fontWeight=FontWeight.Bold),
                    maxLines=1,softWrap=false,autoSize=TextAutoSize.StepBased(minFontSize=14.sp,maxFontSize=34.sp,stepSize=1.sp))
            }
            FlowRow(Modifier.fillMaxWidth().pointerInput(Unit) {detectTapGestures {dismissToken++}},horizontalArrangement=Arrangement.spacedBy(14.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
                for((kind,amount) in listOf("income" to month.incomeMinor,"expense" to month.expenseMinor)) {
                    Column(Modifier.widthIn(min=140.dp),verticalArrangement=Arrangement.spacedBy(6.dp)) {
                        val title=if(historical) stringResource(if(kind=="income") R.string.overview_overview_income_month_value else R.string.overview_overview_expense_month_value,month.month.monthValue.toString())
                            else stringResource(if(kind=="income") R.string.overview_overview_income_this_month else R.string.overview_overview_expense_this_month)
                        Text(title,
                            fontSize=13.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(formatMinorUnits(amount,code),Modifier.testTag("overview.monthly.$kind"),fontSize=18.sp,fontWeight=FontWeight.Bold,
                            color=if(kind=="income") Color(0xFF2DAA9E) else Color(0xFFF45C7E),maxLines=1,softWrap=false)
                    }
                }
            }
            if(categoryMode) OverviewCategoryChart(categoryPages,preferredMonth,onMonthChanged={preferredMonth=it},headerControls=controls)
            else OverviewWeeklyChart(weeks,code,overlayPresented,dismissToken,onOpenExpenseDay,preferredWeek,onWeekChanged={preferredWeek=it},headerControls=controls)
        }
    }
}

@Composable private fun OverviewChartModePicker(categoryMode:Boolean,onChange:(Boolean)->Unit) {
    val shape=RoundedCornerShape(9.dp)
    Row(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.onSurface.copy(alpha=0.06f),shape).padding(3.dp).testTag("overview.hero.chart.mode"),horizontalArrangement=Arrangement.spacedBy(3.dp)) {
        for(category in listOf(false,true)) Box(Modifier.weight(1f).heightIn(min=40.dp)
            .background(if(categoryMode==category) MaterialTheme.colorScheme.surface else Color.Transparent,shape)
            .testTag("overview.chart.mode.${if(category) "category" else "day"}").selectable(selected=categoryMode==category,role=Role.Tab,onClick={onChange(category)}),contentAlignment=androidx.compose.ui.Alignment.Center) {
            Text(stringResource(if(category) R.string.overview_overview_category else R.string.overview_overview_day),fontSize=13.sp,fontWeight=FontWeight.SemiBold)
        }
    }
}
