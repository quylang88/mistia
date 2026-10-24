package vn.com.quyln.mistia.feature.investment

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import vn.com.quyln.mistia.core.designsystem.*
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

private sealed interface TradeDetailRead {
    data object Loading:TradeDetailRead
    data object Failed:TradeDetailRead
    data class Loaded(val snapshot:InvestmentTradeDeletionSnapshot):TradeDetailRead
}
@Composable private fun tradeDetailRead(owner:UserId,repository:InvestmentRepository,retry:Int):State<TradeDetailRead> {
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    return key(owner.value,repository,retry,lifecycle){produceState<TradeDetailRead>(TradeDetailRead.Loading){
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED){
            value=TradeDetailRead.Loading
            try{repository.observeTradeDeletionSnapshot(owner).collect{snapshot->
                val valid=snapshot.owner==owner && snapshot.rows.all{row->CloudEntity.fromTable(row.entity)?.let{it in InvestmentTradeDeletionSnapshot.entities && row.financeRawIdentity(owner,it,true)}==true} && snapshot.rows.map{it.entity to it.id}.distinct().size==snapshot.rows.size
                value=if(valid)TradeDetailRead.Loaded(snapshot) else TradeDetailRead.Failed
            }}catch(cancelled:CancellationException){throw cancelled}
            catch(_:Exception){value=TradeDetailRead.Failed}
            finally{if(!currentCoroutineContext().isActive)value=TradeDetailRead.Loading}
        }
    }}
}
private data class TradeDetail(val raw:CloudRecord,val asset:InvestmentAssetRecord,val channelName:String,val kind:InvestmentTradeKind,val quantity:BigDecimal,val unit:String,
    val explicitUnit:Boolean,val gross:Long,val currency:String,val accountingGross:Long,val accountingCurrency:String,val basis:Long,val profit:Long,
    val position:BigDecimal,val positionCost:Long,val occurred:Instant,val note:String?)
private fun tradeDetail(snapshot:InvestmentTradeDeletionSnapshot,raw:CloudRecord):TradeDetail {
    val p=raw.payload
    fun text(key:String)=requireNotNull(p.financeRawString(key))
    fun amount(key:String)=requireNotNull(p.financeRawLong(key))
    val ref=p.financeRawReference("asset_id");require(ref.readable)
    val asset=InvestmentAssetRecord.fromCloudRecord(snapshot.rows.single{it.entity==CloudEntity.INVESTMENT_ASSET.table && it.id==ref.id})
    val label=p["unit_label"];require(label==null || label==JsonNull || p.financeRawString("unit_label")!=null)
    val unit=p.financeRawString("unit_label")?.let(InvestmentUnitLabel::normalizedDisplay)
    val quantity=requireNotNull(investmentTradeQuantity(text("quantity_decimal_string")))
    val positionText=text("position_quantity_after_decimal_string");require(positionText.length<=256)
    val position=positionText.toBigDecimal().also{require(it.signum()>=0 && it.scale() in -165..128)}
    val kind=when(text("kind_raw_value")){"buy"->InvestmentTradeKind.BUY;"sell"->InvestmentTradeKind.SELL;else->error("Unreadable trade kind")}
    val gross=amount("gross_amount_minor");val accounting=amount("accounting_gross_amount_minor");val basis=amount("released_cost_basis_minor");val cost=amount("position_cost_basis_after_minor")
    require(gross>=0 && accounting>=0 && basis>=0 && cost>=0)
    val currency=requireNotNull(text("currency_code").financeReportingCode());val accountingCurrency=requireNotNull(text("accounting_currency_code").financeReportingCode())
    val note=p["note"];require(note==null || note==JsonNull || p.financeRawString("note")!=null)
    val channelName=snapshot.rows.singleOrNull{it.entity==CloudEntity.INVESTMENT_CHANNEL.table && it.id==asset.channelId}?.payload?.financeRawString("name") ?: "—"
    return TradeDetail(raw,asset,channelName,kind,quantity,unit ?: asset.defaultUnitLabel ?: "—",unit!=null,gross,currency,accounting,accountingCurrency,basis,amount("realized_profit_loss_minor"),position,cost,Instant.parse(text("occurred_at")),p.financeRawString("note"))
}
private fun sameDetailTrade(a:CloudRecord,b:CloudRecord,ignoreDeleted:Boolean=false):Boolean =
    a.matchesVisibleInvestmentTrade(b) && (ignoreDeleted || a.financeRawDeleted(true)==b.financeRawDeleted(true))

private class TradeDeletePrompt(val trade:CloudRecord)
private class TradeDeleteFundPrompt(val request:InvestmentTradeDeletionRequest,val review:InvestmentTradeDeletionReview)
private class TradeDeleteFailure(val request:InvestmentTradeDeletionRequest)
private class TradeDetailSession {
    var saving by mutableStateOf(false)
    var confirmation by mutableStateOf<TradeDeletePrompt?>(null)
    var review by mutableStateOf<TradeDeleteFundPrompt?>(null)
    var failed by mutableStateOf<TradeDeleteFailure?>(null)
    var error by mutableStateOf<Throwable?>(null)
}
@Composable internal fun InvestmentTradeDetailSheet(owner:UserId,repository:InvestmentRepository,id:String,deviceIdProvider:suspend ()->String,
    onDismiss:()->Unit,now:()->String={Instant.now().toString()},rates:List<ExchangeRateSnapshot> = emptyList(),onSetupLinked:()->Unit={}) {
    key(owner.value,repository,id){OwnedTradeDetailSheet(owner,repository,id,deviceIdProvider,onDismiss,now,rates,onSetupLinked)}
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun OwnedTradeDetailSheet(owner:UserId,repository:InvestmentRepository,id:String,deviceIdProvider:suspend ()->String,onDismiss:()->Unit,now:()->String,rates:List<ExchangeRateSnapshot>,onSetupLinked:()->Unit) {
    val prefix="investment.trade.detail"
    var editToken by androidx.compose.runtime.saveable.rememberSaveable{mutableStateOf<String?>(null)}
    val editing=remember(editToken){editToken?.let{runCatching{Json.decodeFromString(CloudRecord.serializer(),it)}.getOrNull()}}
    if(editing!=null) {
        key(editToken){InvestmentTradeEditingSheet(owner,repository,editing,rates,deviceIdProvider,{editToken=null},onSetupLinked,now)}
        return
    }
    var retry by remember{mutableIntStateOf(0)}
    val load by tradeDetailRead(owner,repository,retry)
    val snapshot=(load as? TradeDetailRead.Loaded)?.snapshot
    val raw=snapshot?.rows?.singleOrNull{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==id}
    val session=remember{TradeDetailSession()};val scope=rememberCoroutineScope()
    val latestSnapshot by rememberUpdatedState(snapshot)
    LaunchedEffect(load){if(load !is TradeDetailRead.Loaded){session.confirmation=null;session.review=null}}
    val active=raw?.takeIf{it.financeRawDeleted(true)==false}
    val failed=session.failed
    val display=active ?: failed?.request?.expectedTrade?.takeIf{raw?.financeRawDeleted(true)==true && sameDetailTrade(it,raw,true)}
    val parsed=remember(snapshot,display){if(snapshot==null || display==null)null else runCatching{tradeDetail(snapshot,display)}}
    val detail=parsed?.getOrNull()
    val wallets=remember(snapshot){snapshot?.rows.orEmpty().filter{it.entity==CloudEntity.LEDGER_WALLET.table}.mapNotNull{runCatching{LedgerWalletRecord.fromCloudRecord(it)}.getOrNull()}}
    val title=stringResource(R.string.investment_trade_detail_title)
    val adjustmentTitle=stringResource(R.string.investment_cash_automatic_reconciliation_title)
    fun allowed(r:InvestmentTradeDeletionRequest):Boolean {
        if(snapshot==null || detail==null || raw==null)return false
        if(raw.financeRawDeleted(true)==false)return sameDetailTrade(r.expectedTrade,raw)
        return session.failed?.request?.copy(consent=null)==r.copy(consent=null) && raw.financeRawDeleted(true)==true && sameDetailTrade(r.expectedTrade,raw,true)
    }
    fun execute(r:InvestmentTradeDeletionRequest) {
        if(session.saving || !allowed(r))return
        session.saving=true;session.error=null;session.confirmation=null;session.review=null;session.failed=null
        scope.launch {
            try {
                val device=deviceIdProvider();coroutineContext.ensureActive()
                val result=repository.deleteTrade(owner,r,device,now());coroutineContext.ensureActive()
                val error=result.exceptionOrNull()
                when {
                    result.isSuccess->onDismiss()
                    error is InvestmentTradeDeletionConfirmationRequired->if(latestSnapshot==null)session.error=InvestmentAssetException(InvestmentAssetError.UNREADABLE_SOURCE) else if(error.review.requiresConfirmation)session.review=TradeDeleteFundPrompt(r.copy(consent=null),error.review) else session.error=InvestmentAssetException(InvestmentAssetError.STALE_RECORD)
                    else->{session.error=error;session.failed=TradeDeleteFailure(r)}
                }
            }catch(cancelled:CancellationException){throw cancelled}
            catch(error:Exception){session.error=error;session.failed=TradeDeleteFailure(r)}
            finally{session.saving=false}
        }
    }
    val sheet=rememberModalBottomSheetState(skipPartiallyExpanded=true,confirmValueChange={it!=SheetValue.Hidden || !session.saving})
    ModalBottomSheet(onDismissRequest={if(!session.saving)onDismiss()},sheetState=sheet) {
        Column(Modifier.fillMaxWidth().testTag(prefix+".sheet")) {
            Row(Modifier.fillMaxWidth().padding(horizontal=16.dp),horizontalArrangement=Arrangement.SpaceBetween) {
                Text(title,Modifier.weight(1f).padding(vertical=12.dp).testTag(prefix+".title"),style=MaterialTheme.typography.titleLarge)
                IconButton(onClick=onDismiss,enabled=!session.saving,modifier=Modifier.size(48.dp).testTag(prefix+".close")){Icon(Icons.Default.Close,stringResource(R.string.common_close))}
            }
            Column(Modifier.fillMaxWidth().weight(1f,false).verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
                if(detail!=null) {
                    TradeDetailValue(stringResource(R.string.investment_trade_asset),detail.asset.name,prefix+".asset")
                    TradeDetailValue(stringResource(R.string.investment_channel_name),detail.channelName,prefix+".channel")
                    Text(stringResource(if(detail.kind==InvestmentTradeKind.BUY)R.string.investment_hub_buy else R.string.investment_hub_sell),Modifier.testTag(prefix+".kind"),style=MaterialTheme.typography.titleMedium)
                    TradeDetailValue(stringResource(R.string.investment_trade_quantity),detail.quantity.stripTrailingZeros().toPlainString()+" "+detail.unit,prefix+".quantity")
                    TradeDetailValue(stringResource(R.string.investment_trade_gross_amount),formatMinorUnits(detail.gross,detail.currency),prefix+".gross",fitMoney=true)
                    TradeDetailValue(stringResource(R.string.investment_trade_accounting_amount),formatMinorUnits(detail.accountingGross,detail.accountingCurrency),prefix+".accounting",fitMoney=true)
                    TradeDetailValue(stringResource(if(detail.kind==InvestmentTradeKind.BUY)R.string.investment_hub_cost_basis else R.string.investment_trade_released_cost_basis),formatMinorUnits(if(detail.kind==InvestmentTradeKind.BUY)detail.accountingGross else detail.basis,detail.accountingCurrency),prefix+".basis",fitMoney=true)
                    TradeDetailValue(stringResource(R.string.investment_hub_realized_profit_loss),formatMinorUnits(detail.profit,detail.accountingCurrency),prefix+".profit",fitMoney=true)
                    Column(Modifier.fillMaxWidth(),verticalArrangement=Arrangement.spacedBy(4.dp)) {
                        TradeDetailValue(stringResource(R.string.investment_trade_position_after),detail.position.stripTrailingZeros().toPlainString()+" "+detail.unit,prefix+".position")
                        TradeDetailValue(stringResource(R.string.investment_lot_history_remaining_cost),formatMinorUnits(detail.positionCost,detail.accountingCurrency),prefix+".position.cost",fitMoney=true)
                    }
                    val locale=androidx.compose.ui.platform.LocalConfiguration.current.locales[0]
                    TradeDetailValue(stringResource(R.string.investment_trade_time),DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM,FormatStyle.SHORT).withLocale(locale).format(detail.occurred.atZone(ZoneId.systemDefault())),prefix+".time")
                    val p=detail.raw.payload
                    for((refKey,label) in listOf("funding_wallet_id" to R.string.investment_trade_funding_wallet,"capital_return_wallet_id" to R.string.investment_trade_capital_wallet)) {
                        p.financeRawReference(refKey).id?.let{walletId->TradeDetailValue(stringResource(label),wallets.firstOrNull{it.id==walletId}?.let{it.name+" · "+it.currencyCode} ?: "—",prefix+"."+refKey)}
                    }
                    val rates=listOfNotNull(
                        p.financeRawString("exchange_rate_decimal_string")?.let{detail.currency+" → "+detail.accountingCurrency+": "+it},
                        p.financeRawString("funding_to_accounting_rate_decimal_string")?.let{p.financeRawString("funding_wallet_currency_code").orEmpty()+" → "+detail.accountingCurrency+": "+it},
                        p.financeRawString("accounting_to_capital_return_rate_decimal_string")?.let{detail.accountingCurrency+" → "+p.financeRawString("capital_return_wallet_currency_code").orEmpty()+": "+it})
                    if(rates.isNotEmpty())TradeDetailValue(stringResource(R.string.investment_trade_exchange_rate),(rates+listOfNotNull(p.financeRawString("exchange_rate_provider"),p.financeRawString("exchange_rate_date"))).joinToString("\n"),prefix+".rates")
                    detail.note?.takeIf{it.isNotBlank()}?.let{TradeDetailValue(stringResource(R.string.investment_trade_note),it,prefix+".note")}
                    if(!detail.explicitUnit)Text(stringResource(R.string.investment_trade_resolve_unit_before_trading),color=MaterialTheme.colorScheme.error)
                    TextButton(onClick={active?.let{editToken=Json.encodeToString(CloudRecord.serializer(),it)}},enabled=active!=null && detail.explicitUnit && !session.saving,
                        modifier=Modifier.fillMaxWidth().heightIn(min=48.dp).testTag(prefix+".edit")){Text(stringResource(R.string.management_management_edit))}
                    Text(stringResource(R.string.investment_trade_delete_description),Modifier.testTag(prefix+".delete.description"),style=MaterialTheme.typography.bodyMedium)
                    TextButton(onClick={active?.let{session.confirmation=TradeDeletePrompt(it);session.error=null;session.failed=null}},enabled=active!=null && detail.explicitUnit && !session.saving,modifier=Modifier.fillMaxWidth().heightIn(min=48.dp).testTag(prefix+".delete"),colors=ButtonDefaults.textButtonColors(contentColor=MaterialTheme.colorScheme.error)){Text(stringResource(R.string.investment_trade_delete_action),Modifier.testTag(prefix+".delete.text"))}
                } else if(load==TradeDetailRead.Loading)CircularProgressIndicator(Modifier.size(24.dp).testTag(prefix+".loading"))
                else {
                    Text(stringResource(if(load==TradeDetailRead.Failed || parsed?.isFailure==true)R.string.common_error else R.string.planning_installment_editor_not_found),Modifier.testTag(prefix+".unavailable"))
                    TextButton(onClick={session.error=null;session.failed=null;session.review=null;session.confirmation=null;retry++},modifier=Modifier.testTag(prefix+".reload")){Text(stringResource(R.string.planning_installment_retry))}
                }
                session.error?.let{Text(stringResource(investmentTradeErrorResource(it)),Modifier.testTag(prefix+".error"),color=MaterialTheme.colorScheme.error)}
                session.failed?.let{failure->TextButton(onClick={if(session.failed===failure)execute(failure.request)},enabled=!session.saving && allowed(failure.request),modifier=Modifier.heightIn(min=48.dp).testTag(prefix+".retry")){Text(stringResource(R.string.planning_installment_retry))}}
                if(session.saving)CircularProgressIndicator(Modifier.size(24.dp).testTag(prefix+".saving"))
            }
        }
    }
    session.confirmation?.let{prompt->
        val target=prompt.trade
        AlertDialog(modifier=Modifier.testTag(prefix+".delete.review"),onDismissRequest={if(session.confirmation===prompt)session.confirmation=null},title={Text(stringResource(R.string.investment_trade_delete_action),Modifier.testTag(prefix+".delete.title"))},
            text={Text(stringResource(R.string.investment_trade_delete_confirmation),Modifier.testTag(prefix+".delete.message"))},
            confirmButton={TextButton(onClick={if(session.confirmation===prompt)execute(InvestmentTradeDeletionRequest(target,null,adjustmentTitle))},enabled=!session.saving && active?.let{sameDetailTrade(target,it)}==true,modifier=Modifier.heightIn(min=48.dp).testTag(prefix+".delete.confirm")){Text(stringResource(R.string.common_delete),Modifier.testTag(prefix+".delete.confirm.text"),color=MaterialTheme.colorScheme.error)}},
            dismissButton={TextButton(onClick={if(session.confirmation===prompt)session.confirmation=null},modifier=Modifier.heightIn(min=48.dp).testTag(prefix+".delete.cancel")){Text(stringResource(R.string.common_cancel),Modifier.testTag(prefix+".delete.cancel.text"))}})
    }
    session.review?.let{prompt->
        val r=prompt.request;val review=prompt.review
        val adapter=InvestmentFundUsageReview(InvestmentFundUsageConsent(owner.value,id,"",""),review.comparison,review.requiresConfirmation)
        InvestmentFundUsageDialog(adapter,wallets,onDismiss={if(session.review===prompt)session.review=null},onConfirm={if(session.review===prompt)execute(r.copy(consent=review.consent))},isSaving=session.saving,tagPrefix=prefix+".funds",canConfirm=allowed(r),tradeAction=InvestmentTradeFundAction.DELETE)
    }
}
@Composable private fun TradeDetailValue(label:String,value:String,tag:String,fitMoney:Boolean=false) {
    Column(Modifier.fillMaxWidth(),verticalArrangement=Arrangement.spacedBy(4.dp)) {
        Text(label,Modifier.testTag(tag+".label"),style=MaterialTheme.typography.labelLarge,color=MaterialTheme.colorScheme.onSurfaceVariant)
        if(fitMoney)CashMoneyText(value,tag,MaterialTheme.typography.bodyLarge.copy(color=MaterialTheme.colorScheme.onSurface))
        else Text(value,Modifier.testTag(tag),style=MaterialTheme.typography.bodyLarge)
    }
}
