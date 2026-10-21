package vn.com.quyln.mistia.feature.overview

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.math.BigInteger
import vn.com.quyln.mistia.core.designsystem.FinanceIcon
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.OverviewInvestmentSummary

@Composable
internal fun OverviewInvestmentCard(summary:OverviewInvestmentSummary,enabled:Boolean,failed:Boolean,onRetry:()->Unit,onOpen:()->Unit) {
    val dark=MaterialTheme.colorScheme.surface.luminance()<0.5f
    val locale=LocalConfiguration.current.locales[0]
    val currency=summary.currencyCode
    val positive=if(currency==null) null else summary.realizedProfitLossMinor?.signum()?.let {it>=0}
    val gain=Color(0.18f,0.67f,0.62f);val loss=Color(0.96f,0.36f,0.49f)
    fun money(value:BigInteger?)=if(value==null || currency==null) "—" else formatMinorUnits(value,currency)
    val profit=money(summary.realizedProfitLossMinor).let {if(positive==true && summary.currencyCode!=null) "+$it" else it}
    Column(Modifier.fillMaxWidth().testTag("overview.investment.section"),verticalArrangement=Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.investment_title).uppercase(locale),fontSize=13.sp,lineHeight=16.sp,letterSpacing=0.6.sp,
            fontWeight=FontWeight.Bold,color=if(dark) Color.White.copy(alpha=0.66f) else Color(0.36f,0.37f,0.43f))
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(if(dark) Color(0xFF1C1C1E) else Color.White)
            .clickable(enabled=enabled,role=Role.Button,onClick=onOpen).testTag("overview.investment.card").padding(vertical=2.dp)) {
            InvestmentRow("capital",stringResource(R.string.investment_hub_invested_capital),money(summary.capitalMinor),"mistia.wallet.investment",MaterialTheme.colorScheme.onSurface)
            HorizontalDivider(Modifier.padding(start=56.dp))
            InvestmentRow("profit",stringResource(R.string.investment_hub_realized_profit_loss),profit,
                if(positive==false) "mistia.flow.expense" else "mistia.category.income.investment_finance.investment_gain",
                when(positive){true ->gain;false ->loss;null ->MaterialTheme.colorScheme.onSurfaceVariant})
        }
        if(summary.currencyCode==null || summary.capitalMinor==null || summary.realizedProfitLossMinor==null) {
            Text(stringResource(R.string.overview_overview_reporting_amount_unavailable),Modifier.testTag("overview.investment.unavailable"),
                fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if(failed) TextButton(onClick=onRetry,modifier=Modifier.testTag("overview.investment.retry")) {Text(stringResource(R.string.planning_installment_retry))}
    }
}

@Composable
private fun InvestmentRow(kind:String,title:String,value:String,icon:String,valueColor:Color) {
    val titleStyle=TextStyle(fontSize=15.sp,fontWeight=FontWeight.SemiBold,color=MaterialTheme.colorScheme.onSurface)
    val valueStyle=TextStyle(fontSize=15.sp,fontWeight=FontWeight.Bold,color=valueColor,textAlign=TextAlign.End)
    val measurer=rememberTextMeasurer();val density=LocalDensity.current
    BoxWithConstraints(Modifier.fillMaxWidth().padding(horizontal=14.dp,vertical=12.dp)) {
        val gap=with(density){8.dp.toPx()}
        val textWidth=(constraints.maxWidth-with(density){(30+12+12+12).dp.toPx()}).coerceAtLeast(0f)
        val required=measurer.measure(title,titleStyle).size.width+measurer.measure(value,valueStyle).size.width+gap
        val minimumValueWidth=measurer.measure(value,valueStyle.copy(fontSize=12.sp)).size.width
        val fullRow=minimumValueWidth>textWidth
        val stacked=required>textWidth
        val amountWidth=if(fullRow) constraints.maxWidth.toFloat() else textWidth
        val amount:@Composable ()->Unit={
            var size=15f
            while(size>12f && measurer.measure(value,valueStyle.copy(fontSize=size.sp)).size.width>amountWidth) size-=0.5f
            val wrap=measurer.measure(value,valueStyle.copy(fontSize=size.sp)).size.width>amountWidth
            BasicText(value,Modifier.then(if(stacked) Modifier.fillMaxWidth() else Modifier).testTag("overview.investment.$kind"),
                style=valueStyle.copy(fontSize=size.sp),maxLines=if(wrap) Int.MAX_VALUE else 1,softWrap=wrap)
        }
        val heading:@Composable ()->Unit={
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(12.dp),verticalAlignment=Alignment.CenterVertically) {
                FinanceIcon(icon,Modifier.size(30.dp).testTag("overview.investment.icon.$kind"))
                Box(Modifier.weight(1f)) {
                    if(fullRow) Text(title,style=titleStyle)
                    else if(stacked) Column(Modifier.fillMaxWidth(),verticalArrangement=Arrangement.spacedBy(4.dp)) {Text(title,style=titleStyle);amount()}
                    else Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp),verticalAlignment=Alignment.CenterVertically) {
                        Text(title,Modifier.weight(1f),style=titleStyle);amount()
                    }
                }
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight,contentDescription=null,modifier=Modifier.size(12.dp),tint=MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha=0.45f))
            }
        }
        if(fullRow) Column(Modifier.fillMaxWidth(),verticalArrangement=Arrangement.spacedBy(4.dp)) {heading();amount()}
        else heading()
    }
}
