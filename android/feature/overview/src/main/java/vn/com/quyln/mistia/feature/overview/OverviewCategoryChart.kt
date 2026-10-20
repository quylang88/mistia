package vn.com.quyln.mistia.feature.overview

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import kotlin.math.atan2
import vn.com.quyln.mistia.core.designsystem.categoryColorFromHex
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@Composable internal fun OverviewCategoryChart(pages:List<OverviewCategorySpendingMonth>,preferredMonth:YearMonth,onMonthChanged:(YearMonth)->Unit,headerControls:@Composable ()->Unit) {
    if(pages.isEmpty()) return
    // Pager count, keys and content must change as one subtree when history changes.
    // Keeping the old lazy intervals with a new count can index the previous month's list.
    key(pages.map {it.month}) {CategoryChartPages(pages,preferredMonth,onMonthChanged,headerControls)}
}

@Composable private fun CategoryChartPages(pages:List<OverviewCategorySpendingMonth>,preferredMonth:YearMonth,onMonthChanged:(YearMonth)->Unit,headerControls:@Composable ()->Unit) {
    val initial=pages.indexOfFirst {it.month==preferredMonth}.takeIf {it>=0} ?: pages.lastIndex
    val pager=rememberPagerState(initialPage=initial) {pages.size}
    var selectedMonth by remember {mutableStateOf(preferredMonth)}
    val months=pages.map {it.month}
    LaunchedEffect(months) {
        val target=pages.indexOfFirst {it.month==selectedMonth}.takeIf {it>=0} ?: pages.lastIndex
        selectedMonth=pages[target].month;onMonthChanged(selectedMonth);pager.scrollToPage(target)
    }
    LaunchedEffect(pager.settledPage) {selectedMonth=pages[pager.settledPage.coerceIn(pages.indices)].month;onMonthChanged(selectedMonth)}
    val active=pages[pager.currentPage.coerceIn(pages.indices)]
    var drilldownId by remember(active) {mutableStateOf<String?>(null)}
    val roots=overviewCategoryChartSlices(active.slices,"root-${active.month}")
    val drilldown=roots.firstOrNull {it.id==drilldownId && it.canSelect}
    val visible=if(drilldown==null) roots else overviewCategoryChartSlices(drilldown.children,"drill-${drilldown.id}",allowSelection=false)
    val locale=LocalConfiguration.current.locales[0]
    val monthPattern=remember(locale) {android.text.format.DateFormat.getBestDateTimePattern(locale,"yMMMM")}
    val haptic=LocalHapticFeedback.current
    Column(verticalArrangement=Arrangement.spacedBy(12.dp)) {
        FlowRow(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,verticalArrangement=Arrangement.spacedBy(4.dp)) {
            Text(stringResource(R.string.overview_overview_spending_by_category),fontSize=16.sp,fontWeight=FontWeight.Bold)
            Text(active.month.atDay(1).format(DateTimeFormatter.ofPattern(monthPattern,locale)),Modifier.testTag("overview.category.month"),fontSize=11.sp,fontWeight=FontWeight.SemiBold,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        headerControls()
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val density=LocalDensity.current
            val measurer=rememberTextMeasurer()
            val names=visible.map {categoryChartName(it)}
            val moneyWidth=with(density) {visible.maxOfOrNull {measurer.measure(formatMinorUnits(it.amountMinor,active.currencyCode),categoryLegendMoneyStyle,maxLines=1).size.width}?.toDp() ?: 0.dp}
            val percentageWidth=with(density) {measurer.measure("100%",categoryLegendPercentageStyle,maxLines=1).size.width.toDp()}
            val requiredLegendWidth=moneyWidth+37.dp+(if(visible.size>1) maxOf(34.dp,percentageWidth)+8.dp else 0.dp)
            val stacked=maxWidth<300.dp || density.fontScale>=1.2f || maxWidth<150.dp+14.dp+requiredLegendWidth
            val legendHeight=visible.indices.fold(0.dp) {height,index ->
                val nameHeight=with(density) {measurer.measure(names[index],categoryLegendNameStyle,maxLines=1).size.height.toDp()}
                val moneyHeight=with(density) {measurer.measure(formatMinorUnits(visible[index].amountMinor,active.currencyCode),categoryLegendMoneyStyle,maxLines=1).size.height.toDp()}
                val percentageHeight=with(density) {measurer.measure("100%",categoryLegendPercentageStyle,maxLines=1).size.height.toDp()}
                height+maxOf(28.dp,nameHeight+1.dp+moneyHeight,percentageHeight)+14.dp
            }+7.dp*(visible.size-1).coerceAtLeast(0)
            val backHeight=if(drilldown==null) 0.dp else {
                val nameHeight=with(density) {measurer.measure(categoryChartName(drilldown),categoryBackStyle,maxLines=1).size.height.toDp()}
                maxOf(16.dp,nameHeight)+12.dp+10.dp
            }
            val chartHeight=20.dp+backHeight+(if(active.totalMinor==null || visible.isEmpty()) 150.dp else if(stacked) 150.dp+14.dp+legendHeight else maxOf(150.dp,legendHeight))
            HorizontalPager(pager,Modifier.fillMaxWidth().height(chartHeight).testTag("overview.category.pager"),key={pages[it].month.toString()}) {index ->
                val page=pages[index]
                val isActive=index==pager.currentPage
                val pageDrilldown=drilldown.takeIf {isActive}
                val slices=if(isActive) visible else overviewCategoryChartSlices(page.slices,"root-${page.month}")
                Column(Modifier.fillMaxSize().padding(vertical=10.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
                    if(pageDrilldown!=null) {
                        Row(Modifier.testTag("overview.category.back").background(MaterialTheme.colorScheme.onSurface.copy(alpha=0.05f),RoundedCornerShape(50))
                            .clickable {drilldownId=null}.padding(horizontal=10.dp,vertical=6.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(7.dp)) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack,contentDescription=null,Modifier.size(16.dp))
                            Text(categoryChartName(pageDrilldown),style=categoryBackStyle,maxLines=1,overflow=TextOverflow.Ellipsis)
                        }
                    }
                    if(page.totalMinor==null) Box(Modifier.fillMaxWidth().height(150.dp),contentAlignment=Alignment.Center) {
                        Text(stringResource(R.string.overview_overview_conversion_unavailable),Modifier.testTag("overview.category.unavailable"),color=MaterialTheme.colorScheme.onSurfaceVariant)
                    } else if(slices.isEmpty()) Column(Modifier.fillMaxWidth().height(150.dp),verticalArrangement=Arrangement.Center,horizontalAlignment=Alignment.CenterHorizontally) {
                        Text(stringResource(R.string.core_ui_mistiacategoryspendingchart_no_spending_yet),fontSize=15.sp,fontWeight=FontWeight.Bold)
                        Text(stringResource(R.string.core_ui_mistiacategoryspendingchart_change_the_time_range_to_see_more),fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                    } else {
                        val onSelect:(OverviewCategoryChartSlice)->Unit={slice ->if(isActive && slice.canSelect) {
                            haptic.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.TextHandleMove);drilldownId=slice.id
                        }}
                        if(stacked) Column(Modifier.fillMaxWidth(),verticalArrangement=Arrangement.spacedBy(14.dp),horizontalAlignment=Alignment.CenterHorizontally) {
                            CategoryPie(slices,onSelect);CategoryLegend(slices,page.currencyCode,onSelect,Modifier.fillMaxWidth())
                        } else Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(14.dp),verticalAlignment=Alignment.Top) {
                            CategoryPie(slices,onSelect);CategoryLegend(slices,page.currencyCode,onSelect,Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}

@Composable private fun categoryChartName(slice:OverviewCategoryChartSlice):String = if(slice.isOverflow) stringResource(R.string.core_ui_mistiacategoryspendingchart_other)
    else slice.name?.takeIf(String::isNotBlank) ?: stringResource(R.string.shared_corelogic_overview_uncategorized)

@Composable private fun CategoryPie(slices:List<OverviewCategoryChartSlice>,onSelect:(OverviewCategoryChartSlice)->Unit) {
    val total=slices.fold(BigInteger.ZERO) {sum,slice ->sum+slice.amountMinor}
    // Only finalized dimensionless visual ratios pass through Float; amounts stay BigInteger.
    val ratios=slices.map {BigDecimal(it.amountMinor).divide(BigDecimal(total),24,RoundingMode.HALF_UP).toFloat()}
    val colors=slices.map {categoryColorFromHex(it.colorHex)}
    val prominent=slices.indices.maxByOrNull {slices[it].amountMinor}
    val background=MaterialTheme.colorScheme.onSurface.copy(alpha=0.045f)
    val description=stringResource(R.string.overview_overview_spending_by_category)
    Canvas(Modifier.size(150.dp).testTag("overview.category.pie").semantics {contentDescription=description}.pointerInput(slices) {
        detectTapGestures {position ->
            val x=position.x-size.width/2f;val y=position.y-size.height/2f
            if(x*x+y*y<=size.width*size.width/4f) {
                val angle=((Math.toDegrees(atan2(y.toDouble(),x.toDouble()))+450)%360).toFloat()
                var start=0f
                for(index in slices.indices) {
                    val end=if(index==slices.lastIndex) 360f else start+ratios[index]*360
                    if(angle>=start && angle<end) {onSelect(slices[index]);break};start=end
                }
            }
        }
    }) {
        drawCircle(background)
        var start=-90f
        for(index in slices.indices) {
            val sweep=if(index==slices.lastIndex) 270f-start else ratios[index]*360
            val radius=size.minDimension/2f*(if(index==prominent) 1f else 0.92f)
            val gap=if(slices.size==1) 0f else minOf(1.8f,sweep/2)
            drawArc(colors[index].copy(alpha=if(index==prominent) 1f else 0.9f),start+gap/2,(sweep-gap).coerceAtLeast(0f),true,
                topLeft=Offset(center.x-radius,center.y-radius),size=Size(radius*2,radius*2))
            start+=sweep
        }
    }
}

@Composable private fun CategoryLegend(slices:List<OverviewCategoryChartSlice>,currency:String,onSelect:(OverviewCategoryChartSlice)->Unit,modifier:Modifier) {
    val total=slices.fold(BigInteger.ZERO) {sum,slice ->sum+slice.amountMinor}
    Column(modifier,verticalArrangement=Arrangement.spacedBy(7.dp)) {
        slices.forEach {slice ->
            val color=categoryColorFromHex(slice.colorHex)
            val shape=RoundedCornerShape(12.dp)
            val action=if(slice.canSelect) Modifier.clickable {onSelect(slice)} else Modifier
            Row(Modifier.fillMaxWidth().testTag("overview.category.row.${slice.id}").background(MaterialTheme.colorScheme.surface.copy(alpha=0.58f),shape).then(action)
                .padding(horizontal=10.dp,vertical=7.dp).heightIn(min=28.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                Canvas(Modifier.size(9.dp)) {drawCircle(color)}
                Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(1.dp)) {
                    Text(categoryChartName(slice),style=categoryLegendNameStyle,maxLines=1,overflow=TextOverflow.Ellipsis)
                    BasicText(formatMinorUnits(slice.amountMinor,currency),Modifier.fillMaxWidth().testTag("overview.category.amount.${slice.id}"),
                        style=categoryLegendMoneyStyle.copy(color=MaterialTheme.colorScheme.onSurfaceVariant),maxLines=1,softWrap=false,
                        autoSize=TextAutoSize.StepBased(minFontSize=6.sp,maxFontSize=10.5.sp,stepSize=0.5.sp))
                }
                if(slices.size>1) Text("${overviewCategoryPercentage(slice.amountMinor,total)}%",Modifier.widthIn(min=34.dp),style=categoryLegendPercentageStyle,color=color,maxLines=1)
            }
        }
    }
}

private val categoryLegendNameStyle=TextStyle(fontSize=12.sp,fontWeight=FontWeight.SemiBold)
private val categoryLegendMoneyStyle=TextStyle(fontSize=10.5.sp,fontWeight=FontWeight.SemiBold)
private val categoryLegendPercentageStyle=TextStyle(fontSize=11.sp,fontWeight=FontWeight.Bold)
private val categoryBackStyle=TextStyle(fontSize=12.sp,fontWeight=FontWeight.Bold)
