package vn.com.quyln.mistia.feature.investment

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

@Composable internal fun InvestmentCashHistoryPreview(load:InvestmentWalletReadLoad,parsed:Result<List<InvestmentCashHistoryItem>>?,
    wallets:Map<String,String>,assets:Map<String,String>,onAll:()->Unit,onOpen:(InvestmentCashHistoryItem)->Unit,onRetry:()->Unit,owner:UserId,repository:InvestmentRepository,assetImagePaths:Map<String,String?>) {
    Column(Modifier.fillMaxWidth().testTag("investment.cash.history.preview"),verticalArrangement=Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
            Text(stringResource(R.string.investment_wallet_history_title),Modifier.weight(1f),style=MaterialTheme.typography.titleMedium)
            TextButton(onClick=onAll,modifier=Modifier.testTag("investment.cash.history.seeAll")){Text(stringResource(R.string.investment_wallet_history_see_all))}
        }
        HistoryReadStatus(load,parsed,onRetry)
        if(parsed?.getOrNull()?.isEmpty()==true)Text(stringResource(R.string.investment_wallet_history_empty))
        parsed?.getOrNull()?.take(3)?.forEach{CashHistoryRow(it,wallets,assets,onOpen,owner,repository,assetImagePaths)}
    }
}
@Composable internal fun InvestmentCashHistoryScreen(load:InvestmentWalletReadLoad,parsed:Result<List<InvestmentCashHistoryItem>>?,
    wallets:Map<String,String>,assets:Map<String,String>,onBack:()->Unit,onOpen:(InvestmentCashHistoryItem)->Unit,onRetry:()->Unit,owner:UserId,repository:InvestmentRepository,assetImagePaths:Map<String,String?>,modifier:Modifier=Modifier) {
    var filterName by rememberSaveable{mutableStateOf(InvestmentCashHistoryFilter.ALL.name)}
    val filter=InvestmentCashHistoryFilter.valueOf(filterName)
    var visibleLimit by rememberSaveable{mutableIntStateOf(50)}
    val values=remember(parsed,filter){filterInvestmentCashHistory(parsed?.getOrNull().orEmpty(),filter)}
    val listState=rememberLazyListState()
    LaunchedEffect(filter){visibleLimit=50;listState.scrollToItem(0)}
    LaunchedEffect(listState,values.size,visibleLimit) {
        snapshotFlow{listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index}.collect{last ->
            if(last!=null && last>=visibleLimit-1 && visibleLimit<values.size)visibleLimit=(visibleLimit+50).coerceAtMost(values.size)
        }
    }
    Column(modifier.fillMaxSize().testTag("investment.cash.history.screen")) {
        Row(Modifier.fillMaxWidth().padding(horizontal=8.dp),verticalAlignment=Alignment.CenterVertically) {
            IconButton(onClick=onBack,modifier=Modifier.testTag("investment.cash.history.back")){Icon(Icons.AutoMirrored.Filled.ArrowBack,stringResource(R.string.common_close))}
            Text(stringResource(R.string.investment_wallet_history_title),Modifier.weight(1f),style=MaterialTheme.typography.titleLarge)
        }
        Row(Modifier.fillMaxWidth().padding(12.dp).height(IntrinsicSize.Min),horizontalArrangement=Arrangement.spacedBy(4.dp)) {
            InvestmentCashHistoryFilter.entries.forEach{option ->
                val resource=when(option){InvestmentCashHistoryFilter.ALL->R.string.investment_wallet_history_filter_all;InvestmentCashHistoryFilter.INCOMING->R.string.investment_wallet_history_filter_incoming
                    InvestmentCashHistoryFilter.OUTGOING->R.string.investment_wallet_history_filter_outgoing;InvestmentCashHistoryFilter.MOVEMENT->R.string.investment_wallet_history_filter_movement}
                OutlinedButton(onClick={filterName=option.name},modifier=Modifier.weight(1f).fillMaxHeight().testTag("investment.cash.history.filter."+option.name).semantics{selected=option==filter;role=Role.RadioButton},
                    contentPadding=PaddingValues(horizontal=4.dp,vertical=10.dp),colors=ButtonDefaults.outlinedButtonColors(
                        containerColor=if(option==filter)MaterialTheme.colorScheme.secondaryContainer else Color.Transparent)) {Text(stringResource(resource),fontSize=13.sp)}
            }
        }
        LazyColumn(Modifier.fillMaxWidth().weight(1f).testTag("investment.cash.history.list"),state=listState,contentPadding=PaddingValues(16.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
            item{HistoryReadStatus(load,parsed,onRetry)}
            if(parsed?.isSuccess==true && values.isEmpty())item{Text(stringResource(R.string.investment_wallet_history_empty))}
            items(values.take(visibleLimit),key={it.id}){CashHistoryRow(it,wallets,assets,onOpen,owner,repository,assetImagePaths)}
        }
    }
}
@Composable private fun HistoryReadStatus(load:InvestmentWalletReadLoad,parsed:Result<List<InvestmentCashHistoryItem>>?,onRetry:()->Unit) {
    if(load==InvestmentWalletReadLoad.Loading)CircularProgressIndicator(Modifier.size(24.dp).testTag("investment.cash.history.loading"))
    else if(load==InvestmentWalletReadLoad.Failed || parsed?.isFailure==true || parsed==null)Column {
        Text(stringResource(R.string.common_error),Modifier.testTag("investment.cash.history.error"),color=MaterialTheme.colorScheme.error)
        TextButton(onClick=onRetry,modifier=Modifier.testTag("investment.cash.history.retry")){Text(stringResource(R.string.planning_installment_retry))}
    }
}
@Composable private fun CashHistoryRow(item:InvestmentCashHistoryItem,wallets:Map<String,String>,assets:Map<String,String>,onOpen:(InvestmentCashHistoryItem)->Unit,owner:UserId,repository:InvestmentRepository,assetImagePaths:Map<String,String?>) {
    val title=when(item.kind) {
        InvestmentCashHistoryKind.REALIZED_PROFIT -> assets[item.assetId] ?: stringResource(R.string.investment_wallet_history_realized_profit)
        InvestmentCashHistoryKind.LIQUIDATION -> assets[item.assetId] ?: stringResource(R.string.investment_trade_asset)
        InvestmentCashHistoryKind.DEPOSIT -> stringResource(R.string.investment_wallet_history_deposit)
        InvestmentCashHistoryKind.WITHDRAWAL -> stringResource(R.string.investment_wallet_history_withdrawal)
        InvestmentCashHistoryKind.SPENDING -> investmentCashTrimmedText(item.title) ?: stringResource(R.string.investment_wallet_history_spending)
        InvestmentCashHistoryKind.MOVEMENT -> stringResource(R.string.investment_wallet_history_movement)
        InvestmentCashHistoryKind.ADJUSTMENT -> stringResource(R.string.investment_wallet_history_adjustment)
    }
    val image=when(item.kind) {
        InvestmentCashHistoryKind.REALIZED_PROFIT,InvestmentCashHistoryKind.LIQUIDATION->R.drawable.finance_art_ic_fluent_coin_multiple_24_color
        InvestmentCashHistoryKind.DEPOSIT->R.drawable.finance_art_ic_fluent_savings_24_color
        InvestmentCashHistoryKind.WITHDRAWAL->R.drawable.finance_art_ic_fluent_send_24_color
        InvestmentCashHistoryKind.SPENDING->R.drawable.finance_art_ic_fluent_receipt_24_color
        InvestmentCashHistoryKind.MOVEMENT->R.drawable.finance_art_ic_fluent_arrow_sync_24_color
        InvestmentCashHistoryKind.ADJUSTMENT->R.drawable.finance_art_ic_fluent_arrow_clockwise_dashes_24_color
    }
    val dark=MaterialTheme.colorScheme.background.luminance()<0.5f
    val accent=if(item.kind==InvestmentCashHistoryKind.LIQUIDATION)Color(if(dark)0xFFFF453A else 0xFFFF3B30) else when(item.filter) {
        InvestmentCashHistoryFilter.INCOMING->Color(if(dark)0xFF30D158 else 0xFF34C759)
        InvestmentCashHistoryFilter.OUTGOING->Color(if(dark)0xFFFF9F0A else 0xFFFF9500)
        else->Color(0.65f,0.45f,0.98f)
    }
    val amount=(when(item.filter){InvestmentCashHistoryFilter.INCOMING->"+";InvestmentCashHistoryFilter.OUTGOING->"−";else->""})+formatMinorUnits(item.accountingAmountMinor.abs(),item.accountingCurrencyCode)
    val source=wallets[item.sourceWalletId];val destination=wallets[item.destinationWalletId]
    val flow=if(source!=null && destination!=null)stringResource(R.string.investment_wallet_history_wallet_flow,source,destination) else source ?: destination
    val locale=LocalConfiguration.current.locales[0]
    val date=remember(item.occurredAt,locale){Instant.parse(item.occurredAt).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL).withLocale(locale))}
    val content:@Composable ()->Unit={
        Column(Modifier.fillMaxWidth().padding(14.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(12.dp),verticalAlignment=Alignment.CenterVertically) {
                if(item.assetId!=null)InvestmentProductThumbnail(owner,repository,requireNotNull(item.assetId),assetImagePaths[item.assetId],Modifier.testTag("investment.cash.history.icon."+item.id),42.dp)
                else Image(painterResource(image),contentDescription=null,modifier=Modifier.size(42.dp).background(accent.copy(alpha=0.1f),RoundedCornerShape(10.dp)).testTag("investment.cash.history.icon."+item.id).padding(7.dp))
                Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(3.dp)) {
                    Text(title,style=MaterialTheme.typography.titleSmall)
                    flow?.let{Text(it,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
                    if(item.kind==InvestmentCashHistoryKind.LIQUIDATION)Text(stringResource(R.string.investment_wallet_history_liquidation_label),style=MaterialTheme.typography.bodySmall)
                    else if(item.grossAmountMinor!=null && item.grossCurrencyCode!=null)Text(stringResource(R.string.investment_wallet_history_sale_amount,formatMinorUnits(requireNotNull(item.grossAmountMinor),requireNotNull(item.grossCurrencyCode))),style=MaterialTheme.typography.bodySmall)
                    Text(date,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            CashMoneyText(amount,"investment.cash.history.amount."+item.id,MaterialTheme.typography.bodyMedium.copy(color=accent,fontWeight=FontWeight.Bold,textAlign=TextAlign.End))
        }
    }
    val modifier=Modifier.fillMaxWidth().testTag("investment.cash.history.item."+item.id)
    if(item.isEditable || item.tradeId!=null)Surface(onClick={onOpen(item)},modifier=modifier,shape=MaterialTheme.shapes.large,color=MaterialTheme.colorScheme.surface,content=content)
    else Surface(modifier=modifier,shape=MaterialTheme.shapes.large,color=MaterialTheme.colorScheme.surface,content=content)
}
