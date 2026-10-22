package vn.com.quyln.mistia.feature.investment

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.HelpOutline
import androidx.compose.ui.Alignment
import vn.com.quyln.mistia.core.designsystem.CategoryIcon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.math.BigInteger
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

@Composable internal fun InvestmentCashSummary(load:InvestmentWalletReadLoad,view:InvestmentCashFinancialView?,onRetry:()->Unit) {
    Surface(shape=RoundedCornerShape(22.dp),color=Color(0.43f,0.23f,0.76f).copy(alpha=0.12f),modifier=Modifier.fillMaxWidth().testTag("investment.cash.summary")) {
        Column(Modifier.fillMaxWidth().padding(18.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.investment_wallet_earned_profit),style=MaterialTheme.typography.titleSmall)
            val profit=view?.realizedProfitMinor
            val dark=MaterialTheme.colorScheme.surface.luminance()<0.5f
            val profitColor=when{profit==null || profit.signum()==0->MaterialTheme.colorScheme.onSurface;profit.signum()>0->Color(if(dark)0xFF30D158 else 0xFF34C759);else->Color(if(dark)0xFFFF453A else 0xFFFF3B30)}
            CashMoneyText(cashMoney(profit,view?.currencyCode,signed=true),"investment.cash.profit",TextStyle(fontSize=30.sp,fontWeight=FontWeight.Bold,color=profitColor))
            HorizontalDivider()
            CashMetric(R.string.investment_wallet_available_investment,view?.availableMinor,view?.currencyCode,"investment.cash.available")
            val shortfall=view?.shortfallMinor
            if(shortfall==null || shortfall.signum()>0)
                CashMetric(R.string.investment_wallet_shortfall,shortfall,view?.currencyCode,"investment.cash.shortfall")
            CashReadStatus(load,view==null,onRetry)
        }
    }
}

@Composable private fun CashMetric(title:Int,amount:BigInteger?,code:String?,tag:String) {
    Column(verticalArrangement=Arrangement.spacedBy(4.dp)) {
        Text(stringResource(title),style=MaterialTheme.typography.bodySmall)
        CashMoneyText(cashMoney(amount,code),tag,MaterialTheme.typography.titleMedium.copy(fontWeight=FontWeight.Bold,color=if(title==R.string.investment_wallet_shortfall)Color(0xFFFF9500) else Color(0.65f,0.45f,0.98f)))
    }
}

@Composable internal fun InvestmentCashLocations(load:InvestmentWalletReadLoad,snapshot:InvestmentCashReadSnapshot?,view:InvestmentCashFinancialView?,onRetry:()->Unit) {
    Column(Modifier.fillMaxWidth().testTag("investment.cash.locations"),verticalArrangement=Arrangement.spacedBy(10.dp)) {
        Text(stringResource(R.string.investment_wallet_locations),style=MaterialTheme.typography.titleMedium)
        val allocation=view?.allocation
        if(allocation==null) {
            if(load!=InvestmentWalletReadLoad.Loading)Text(stringResource(R.string.common_error),Modifier.testTag("investment.cash.locations.unavailable"),color=MaterialTheme.colorScheme.error)
            CashReadStatus(load,view==null,onRetry)
        } else {
            val locations=allocation.locations.filter{it.walletId!=view.linkedWallet?.id && (it.totalMinor.signum()>0 || it.originalTotalMinor.signum()>0)}
            if(locations.isEmpty())Text(stringResource(R.string.investment_wallet_no_locations),Modifier.testTag("investment.cash.locations.empty"),style=MaterialTheme.typography.bodyMedium)
            locations.forEach{location ->
                val wallet=snapshot?.rows?.singleOrNull{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==location.walletId && it.financeRawDeleted()==false}
                val name=wallet?.payload?.financeRawString("name")?.takeIf{it.isNotBlank()} ?: stringResource(R.string.investment_wallet_unidentified)
                Surface(shape=RoundedCornerShape(18.dp),color=MaterialTheme.colorScheme.surfaceContainerLow,modifier=Modifier.fillMaxWidth().testTag("investment.cash.location."+location.walletId)) {
                    Column(Modifier.padding(15.dp),verticalArrangement=Arrangement.spacedBy(9.dp)) {
                        Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(10.dp)) {
                            val symbol=wallet?.payload?.financeRawString("icon_symbol_name")?.takeIf{it.isNotBlank()}
                            if(symbol!=null)CategoryIcon(symbol,TransactionCategoryKind.INCOME,wallet?.payload?.financeRawString("icon_color_hex") ?: "#8A8A8E",Modifier.size(28.dp))
                            else Icon(Icons.Outlined.HelpOutline,null,Modifier.size(28.dp),tint=MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(name,Modifier.weight(1f).testTag("investment.cash.location.name."+location.walletId),style=MaterialTheme.typography.titleSmall)
                        }
                        Text(formatMinorUnits(location.totalMinor,allocation.accountingCurrencyCode),Modifier.testTag("investment.cash.location.amount."+location.walletId),style=MaterialTheme.typography.titleSmall,fontWeight=FontWeight.Bold)
                        Text(stringResource(R.string.investment_wallet_available_cash_in_wallet),style=MaterialTheme.typography.bodySmall)
                        if(location.currencyCode!=allocation.accountingCurrencyCode)Text(stringResource(R.string.investment_wallet_original_amount_reference,formatMinorUnits(location.originalTotalMinor,location.currencyCode)),
                            Modifier.testTag("investment.cash.location.original."+location.walletId),style=MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }
}

@Composable private fun CashReadStatus(load:InvestmentWalletReadLoad,unreadable:Boolean,onRetry:()->Unit) {
    if(load==InvestmentWalletReadLoad.Loading)CircularProgressIndicator(Modifier.size(24.dp).testTag("investment.cash.loading"))
    if(load==InvestmentWalletReadLoad.Failed || (load is InvestmentWalletReadLoad.Loaded && unreadable)) {
        Text(stringResource(R.string.common_error),Modifier.testTag("investment.cash.unavailable"),color=MaterialTheme.colorScheme.error)
        TextButton(onClick=onRetry,modifier=Modifier.testTag("investment.cash.retry")){Text(stringResource(R.string.planning_installment_retry))}
    }
}
private fun cashMoney(value:BigInteger?,code:String?,signed:Boolean=false):String =
    if(value==null || code==null)"—" else (if(signed && value.signum()>0)"+" else "")+formatMinorUnits(value,code)

/** Keep a formatted amount together while retaining every digit and the actual system font scale. */
@Composable internal fun CashMoneyText(value:String,tag:String,style:TextStyle) {
    val measurer=rememberTextMeasurer()
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        var size=style.fontSize.value
        while(size>12f && measurer.measure(value,style.copy(fontSize=size.sp)).size.width>constraints.maxWidth)size-=0.5f
        BasicText(value,Modifier.fillMaxWidth().testTag(tag),style=style.copy(fontSize=size.sp))
    }
}
