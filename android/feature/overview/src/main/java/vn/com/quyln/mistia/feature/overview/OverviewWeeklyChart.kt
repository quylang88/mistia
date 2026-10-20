package vn.com.quyln.mistia.feature.overview

import androidx.compose.foundation.border
import androidx.compose.ui.draw.shadow
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.BiasAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.OverviewWeekSpending

@Composable internal fun OverviewWeeklyChart(pages:List<OverviewWeekSpending>,currency:String,overlayPresented:Boolean=false,dismissToken:Int=0,onOpenExpenseDay:((LocalDate)->Unit)?=null,
    preferredWeek:LocalDate?=null,onWeekChanged:(LocalDate)->Unit={},headerControls:@Composable ()->Unit={}) {
    if(pages.isEmpty()) return
    val initial=pages.indexOfFirst {it.start==preferredWeek}.takeIf {it>=0} ?: pages.lastIndex
    val pager=rememberPagerState(initialPage=initial) {pages.size}
    var selectedWeek by remember {mutableStateOf(pages[initial].start)}
    var selectedDate by remember {mutableStateOf<LocalDate?>(null)}
    val week=pages[pager.currentPage.coerceIn(pages.indices)]
    val point=week.points.singleOrNull {!week.hasUnavailableConversion && it.date==selectedDate && (it.amountMinor?.signum() ?: 0)>0}
    val dates=pages.map {it.start}
    LaunchedEffect(dates) {
        val target=pages.indexOfFirst {it.start==selectedWeek}.takeIf {it>=0} ?: pages.lastIndex
        selectedWeek=pages[target].start
        onWeekChanged(selectedWeek)
        pager.scrollToPage(target)
    }
    LaunchedEffect(pager.settledPage) {
        selectedWeek=pages[pager.settledPage.coerceIn(pages.indices)].start
        onWeekChanged(selectedWeek)
    }
    LaunchedEffect(week.start,overlayPresented,dismissToken) {selectedDate=null}
    LaunchedEffect(week.points) {if(point==null) selectedDate=null}
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer=LifecycleEventObserver {_,event ->
            if(event==Lifecycle.Event.ON_PAUSE || event==Lifecycle.Event.ON_STOP || event==Lifecycle.Event.ON_DESTROY) selectedDate=null
        }
        lifecycle.addObserver(observer)
        onDispose {lifecycle.removeObserver(observer)}
    }
    val language=LocalConfiguration.current.locales[0].language
    val viewConfiguration=androidx.compose.ui.platform.LocalViewConfiguration.current
    val chartConfiguration=remember(viewConfiguration) {object:androidx.compose.ui.platform.ViewConfiguration by viewConfiguration {override val longPressTimeoutMillis=350L}}
    val haptic=androidx.compose.ui.platform.LocalHapticFeedback.current
    val dayDetailsLabel=stringResource(R.string.overview_overview_day_details)
    val range="${week.start.format(chartDateFormat)} - ${week.end.format(chartDateFormat)}"
    Column(verticalArrangement=Arrangement.spacedBy(12.dp)) {
        FlowRow(Modifier.fillMaxWidth().pointerInput(Unit) {detectTapGestures {selectedDate=null}},horizontalArrangement=Arrangement.SpaceBetween,verticalArrangement=Arrangement.spacedBy(4.dp)) {
            Text(stringResource(R.string.overview_overview_daily_spending),fontSize=16.sp,fontWeight=FontWeight.Bold)
            Text(if(week.isCurrent) stringResource(R.string.shared_corelogic_mistialocalization_this_week_value,range) else range,
                Modifier.testTag("overview.chart.range"),fontSize=11.sp,fontWeight=FontWeight.SemiBold,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        headerControls()
        CompositionLocalProvider(androidx.compose.ui.platform.LocalViewConfiguration provides chartConfiguration) {
        HorizontalPager(pager,Modifier.fillMaxWidth().height(154.dp).testTag("overview.chart.pager"),key={pages[it].start.toString()}) {index ->
            val page=pages[index]
            val active=index==pager.currentPage
            if(page.hasUnavailableConversion) {
                Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.onSurface.copy(alpha=0.03f),RoundedCornerShape(18.dp)).padding(18.dp),contentAlignment=Alignment.Center) {
                    BasicText(stringResource(R.string.overview_overview_conversion_unavailable),
                        if(active) Modifier.fillMaxWidth().testTag("overview.chart.unavailable") else Modifier.fillMaxWidth(),
                        style=androidx.compose.ui.text.TextStyle(fontSize=14.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,textAlign=androidx.compose.ui.text.style.TextAlign.Center),
                        autoSize=TextAutoSize.StepBased(minFontSize=10.sp,maxFontSize=14.sp,stepSize=0.5.sp))
                }
                return@HorizontalPager
            }
            val maximum=page.points.mapNotNull {it.amountMinor}.maxOrNull()?.max(BigInteger.ZERO) ?: BigInteger.ZERO
            val scale=BigDecimal(maximum).multiply(BigDecimal("1.2")).max(BigDecimal.ONE)
            val top=scale.setScale(0,RoundingMode.HALF_UP).toBigIntegerExact()
            val middle=scale.divide(BigDecimal("2")).setScale(0,RoundingMode.HALF_UP).toBigIntegerExact()
            val grid=MaterialTheme.colorScheme.onSurface.copy(alpha=0.10f)
            val axisStyle=MaterialTheme.typography.labelSmall.copy(fontSize=9.sp,fontWeight=FontWeight.SemiBold,color=MaterialTheme.colorScheme.onSurfaceVariant)
            val axisAuto=TextAutoSize.StepBased(minFontSize=6.sp,maxFontSize=9.sp,stepSize=0.5.sp)
            val topText=chartAxisLabel(top);val middleText=chartAxisLabel(middle)
            val density=LocalDensity.current;val measurer=rememberTextMeasurer()
            val requiredAxis=with(density) {maxOf(measurer.measure(topText,axisStyle).size.width,measurer.measure(middleText,axisStyle).size.width).toDp()}+2.dp
            BoxWithConstraints(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.onSurface.copy(alpha=0.03f),RoundedCornerShape(18.dp)).padding(horizontal=12.dp,vertical=10.dp)
                .pointerInput(Unit) {detectTapGestures {selectedDate=null}}) {
                val axisWidth=requiredAxis.coerceAtLeast(24.dp).coerceAtMost(maxWidth*0.4f)
                val shownPoint=point?.takeIf {active && !overlayPresented}
                val calloutStyle=MaterialTheme.typography.labelLarge.copy(color=MaterialTheme.colorScheme.onSurface,fontWeight=FontWeight.Bold)
                val calloutSpace=shownPoint?.let {
                    with(density) {measurer.measure(formatMinorUnits(checkNotNull(it.amountMinor),currency),calloutStyle).size.height.toDp()}+22.dp
                } ?: 0.dp
                val plotHeight=(maxHeight-calloutSpace-20.dp).coerceAtLeast(0.dp)
                Row(Modifier.fillMaxSize().padding(top=calloutSpace),horizontalArrangement=Arrangement.spacedBy(4.dp)) {
                    Box(Modifier.width(axisWidth).fillMaxHeight().padding(bottom=20.dp)) {
                        BasicText(topText,Modifier.align(Alignment.TopStart).fillMaxWidth(),style=axisStyle,maxLines=1,softWrap=false,autoSize=axisAuto)
                        if(middle!=top && middle!=BigInteger.ZERO) BasicText(middleText,Modifier.align(Alignment.CenterStart).fillMaxWidth(),style=axisStyle,maxLines=1,softWrap=false,autoSize=axisAuto)
                        BasicText("0",Modifier.align(Alignment.BottomStart),style=axisStyle,maxLines=1)
                    }
                    Box(Modifier.weight(1f).fillMaxHeight()) {
                        Canvas(Modifier.fillMaxWidth().height(plotHeight)) {
                            for(fraction in listOf(0f,0.5f,1f)) drawLine(grid,Offset(0f,size.height*fraction),Offset(size.width,size.height*fraction),
                                strokeWidth=0.7.dp.toPx(),pathEffect=PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(),4.dp.toPx())))
                        }
                        Row(Modifier.fillMaxSize(),horizontalArrangement=Arrangement.spacedBy(3.dp)) {
                            page.points.forEach {day ->
                                val amount=checkNotNull(day.amountMinor)
                                val label=chartWeekday(day.date,language)
                                val description="$label, ${day.date.format(chartDateFormat)}, ${formatMinorUnits(amount,currency)}"
                                val ratio=if(amount.signum()<=0) 0f else BigDecimal(amount).divide(scale,24,RoundingMode.HALF_UP).toFloat().coerceIn(0f,1f)
                                val tint=chartTint(day.intensity)
                                val opacity=if(!active || point==null) 0.92f else if(point.date==day.date) 1f else 0.42f
                                Column(Modifier.weight(1f).fillMaxHeight().testTag("overview.chart.day.${day.date}").semantics {contentDescription=description}
                                    .combinedClickable(onClick={if(!overlayPresented) selectedDate=if(amount.signum()<=0 || selectedDate==day.date) null else day.date},
                                        onLongClickLabel=dayDetailsLabel,hapticFeedbackEnabled=false,
                                        onLongClick=if(amount.signum()>0 && !overlayPresented && onOpenExpenseDay!=null) {{
                                            selectedDate=null;haptic.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress);onOpenExpenseDay(day.date)
                                        }} else null),
                                    horizontalAlignment=Alignment.CenterHorizontally) {
                                    Box(Modifier.fillMaxWidth().height(plotHeight),contentAlignment=Alignment.BottomCenter) {
                                        if(ratio>0) Box(Modifier.fillMaxWidth(0.78f).fillMaxHeight(ratio).alpha(opacity)
                                            .background(Brush.verticalGradient(listOf(tint,tint.copy(alpha=0.68f))),RoundedCornerShape(topStart=8.dp,topEnd=8.dp)))
                                    }
                                    BasicText(label,Modifier.fillMaxWidth(),
                                        style=androidx.compose.ui.text.TextStyle(fontSize=10.sp,fontWeight=FontWeight.SemiBold,color=MaterialTheme.colorScheme.onSurfaceVariant,textAlign=androidx.compose.ui.text.style.TextAlign.Center),
                                        maxLines=1,softWrap=false,autoSize=TextAutoSize.StepBased(minFontSize=6.sp,maxFontSize=10.sp,stepSize=0.5.sp))
                                }
                            }
                        }
                    }
                }
                // Reserve a measured row above the axes; the callout remains transparent to pointer hit testing.
                if(shownPoint!=null) {
                    val pointIndex=page.points.indexOfFirst {it.date==shownPoint.date}
                    val anchor=axisWidth+4.dp+(maxWidth-axisWidth-4.dp)*((pointIndex+0.5f)/page.points.size)
                    val bias=if(maxWidth>0.dp) ((anchor/maxWidth)*2-1).coerceIn(-1f,1f) else 0f
                    val shape=RoundedCornerShape(50)
                    Box(Modifier.align(BiasAlignment(bias,-1f))
                        .shadow(3.dp,shape).background(MaterialTheme.colorScheme.surface.copy(alpha=0.96f),shape).border(0.5.dp,MaterialTheme.colorScheme.outlineVariant,shape)) {
                        BasicText(formatMinorUnits(checkNotNull(shownPoint.amountMinor),currency),Modifier.padding(horizontal=12.dp,vertical=7.dp).testTag("overview.chart.selection"),
                            style=calloutStyle,maxLines=1,softWrap=false,
                            autoSize=TextAutoSize.StepBased(minFontSize=12.sp,maxFontSize=14.sp,stepSize=0.5.sp))
                    }
                }
            }
        }
        }
    }
}
private val chartDateFormat=DateTimeFormatter.ofPattern("dd/MM",Locale.ROOT)
private fun chartWeekday(date:LocalDate,language:String):String {
    val labels=when(language) {"vi" -> listOf("T2","T3","T4","T5","T6","T7","CN");"ja" -> listOf("月","火","水","木","金","土","日");else -> listOf("Mon","Tue","Wed","Thu","Fri","Sat","Sun")}
    return labels[date.dayOfWeek.value-1]
}
private fun chartAxisLabel(value:BigInteger):String=when {
    value.abs()>=BigInteger.valueOf(1000000) -> "${value/BigInteger.valueOf(1000000)}M"
    value.abs()>=BigInteger.valueOf(1000) -> "${value/BigInteger.valueOf(1000)}K"
    else -> value.toString()
}
private fun chartTint(intensity:Double):Color {
    val value=intensity.coerceIn(0.0,1.0)
    return Color((0.18+0.78*value).toFloat(),(0.67-0.31*value).toFloat(),(0.62-0.13*value).toFloat())
}
