package vn.com.quyln.mistia.feature.investment

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.util.Currency
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.designsystem.*
import vn.com.quyln.mistia.core.designsystem.R

private sealed interface TradeFormRequest {
    data class Buy(val value:InvestmentPurchaseRequest):TradeFormRequest
    data class Sell(val value:InvestmentSaleRequest):TradeFormRequest
}
private fun TradeFormRequest.withConsent(consent:InvestmentTradeCreationConsent?):TradeFormRequest=when(this){
    is TradeFormRequest.Buy->copy(value=value.copy(consent=consent))
    is TradeFormRequest.Sell->copy(value=value.copy(consent=consent))
}
private class TradeFormSession {
    var saving by mutableStateOf(false)
    var error by mutableStateOf<Throwable?>(null)
    var review by mutableStateOf<Pair<TradeFormRequest,InvestmentTradeCreationReview>?>(null)
    var failed by mutableStateOf<TradeFormRequest?>(null)
}

@Composable internal fun InvestmentPurchaseSheet(owner:UserId,repository:InvestmentRepository,id:String,initialAssetId:String?,
    rates:List<ExchangeRateSnapshot>,deviceIdProvider:suspend ()->String,onDismiss:()->Unit,now:()->String={Instant.now().toString()}) =
    InvestmentTradeCreationSheet(owner,repository,id,initialAssetId,rates,deviceIdProvider,onDismiss,now,InvestmentTradeKind.BUY,{})

@Composable internal fun InvestmentSaleSheet(owner:UserId,repository:InvestmentRepository,id:String,initialAssetId:String?,
    rates:List<ExchangeRateSnapshot>,deviceIdProvider:suspend ()->String,onDismiss:()->Unit,onSetupLinked:()->Unit,now:()->String={Instant.now().toString()}) =
    InvestmentTradeCreationSheet(owner,repository,id,initialAssetId,rates,deviceIdProvider,onDismiss,now,InvestmentTradeKind.SELL,onSetupLinked)

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun InvestmentTradeCreationSheet(owner:UserId,repository:InvestmentRepository,id:String,initialAssetId:String?,
    rates:List<ExchangeRateSnapshot>,deviceIdProvider:suspend ()->String,onDismiss:()->Unit,now:()->String,kind:InvestmentTradeKind,onSetupLinked:()->Unit) {
    val buying=kind==InvestmentTradeKind.BUY
    val prefix=if(buying)"investment.purchase" else "investment.sale"
    var createdAt by rememberSaveable{mutableStateOf(now())}
    var occurredAt by rememberSaveable{mutableStateOf(createdAt)}
    var assetId by rememberSaveable{mutableStateOf(initialAssetId)}
    var walletId by rememberSaveable{mutableStateOf<String?>(null)}
    var quantity by rememberSaveable{mutableStateOf("")}
    var unit by rememberSaveable{mutableStateOf("")}
    var amount by rememberSaveable{mutableStateOf("")}
    var free by rememberSaveable{mutableStateOf(false)}
    var note by rememberSaveable{mutableStateOf("")}
    var assetMenu by remember{mutableStateOf(false)}
    var walletMenu by remember{mutableStateOf(false)}
    var retry by remember{mutableIntStateOf(0)}
    val session=remember(owner,repository,id,kind){TradeFormSession()}
    val scope=key(repository){rememberCoroutineScope()}
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    val snapshot by key(owner,repository,retry,lifecycle,kind){produceState<InvestmentTradeCreationSnapshot?>(null){
        try{lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED){value=null;(if(buying)repository.observePurchaseSnapshot(owner) else repository.observeSaleSnapshot(owner)).collect{source ->
            value=source.takeIf{it.owner==owner && it.rows.all{row->CloudEntity.fromTable(row.entity)?.let{entity->entity in InvestmentPurchaseSnapshot.entities && row.financeRawIdentity(owner,entity,true)}==true}}
        }}}catch(cancelled:kotlinx.coroutines.CancellationException){throw cancelled}catch(error:Exception){value=null;session.error=error}
    }}
    val parsed=remember(snapshot){snapshot?.let{source->runCatching {
        val channels=source.rows.filter{it.entity==CloudEntity.INVESTMENT_CHANNEL.table && it.financeRawDeleted()==false}.map(InvestmentChannelRecord::fromCloudRecord).filterNot{it.isArchived}.map{it.id}.toSet()
        val assets=source.rows.filter{it.entity==CloudEntity.INVESTMENT_ASSET.table && it.financeRawDeleted()==false}.map(InvestmentAssetRecord::fromCloudRecord).filter{!it.isArchived && it.channelId in channels}
        val wallets=source.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table && it.financeRawDeleted()==false}.map(::investmentLinkedWalletRecord)
        Triple(assets,wallets.filter{!it.isArchived && it.kind!=null && it.kind!=WalletKind.INVESTMENT && (buying || it.kind!=WalletKind.CREDIT_CARD)},wallets.single{it.id==investmentSystemWalletId(owner)})
    }}}
    val data=parsed?.getOrNull()
    val positions=remember(snapshot,data?.first){data?.first?.associate{a->a.id to runCatching{investmentTradePositions(snapshot?.rows.orEmpty(),a)}.getOrNull()}}
    val assets=data?.first.orEmpty().filter{a->buying || a.id==assetId || positions?.get(a.id)?.any{it.quantity.signum()>0}==true}
    val wallets=data?.second.orEmpty()
    val asset=assets.singleOrNull{it.id==assetId};val wallet=wallets.singleOrNull{it.id==walletId}
    LaunchedEffect(assets,wallets){
        if(assetId==null){assetId=assets.firstOrNull()?.id;unit=assets.firstOrNull()?.defaultUnitLabel.orEmpty()}
        else if(unit.isEmpty())unit=asset?.defaultUnitLabel.orEmpty()
        if(walletId==null)walletId=wallets.firstOrNull()?.id
    }
    val ledgerTitle=stringResource(R.string.investment_wallet_history_adjustment)
    val promotionalNote=stringResource(R.string.investment_trade_promotional_free_badge)
    val lossNote=stringResource(R.string.investment_trade_total_loss_badge,formatMinorUnits(0,asset?.currencyCode ?: "JPY"))
    val available=positions?.get(assetId)?.let{values->
        values.firstOrNull{InvestmentUnitLabel.comparisonKey(it.unitLabel)==InvestmentUnitLabel.comparisonKey(unit)}?.quantity ?: BigDecimal.ZERO
    }
    val candidate=snapshot?.rows?.any{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==id}==true
    val desiredQuantity=investmentTradeQuantity(quantity.trim().replace(',','.'))
    val enoughStock=buying || (available!=null && desiredQuantity!=null && desiredQuantity<=available)
    val request=remember(asset,wallet,quantity,unit,amount,free,note,occurredAt,createdAt,rates,data?.third,ledgerTitle,promotionalNote,lossNote,kind){runCatching {
        val a=requireNotNull(asset);val code=requireNotNull(data?.third?.currencyCode)
        val q=requireNotNull(investmentTradeQuantity(quantity.trim().replace(',','.')))
        require(InvestmentUnitLabel.normalizedDisplay(unit)!=null && a.defaultUnitLabel!=null)
        val gross=if(free)0L else purchaseInputMinor(amount,a.currencyCode)?.takeIf{it>0} ?: error("Invalid amount")
        val sourceRate=if(free)null else purchaseRate(a.currencyCode,code,rates)
        val account=if(a.currencyCode==code || free)gross else investmentPurchaseConvertedMinor(gross,a.currencyCode,code,sourceRate?.first ?: error("Missing rate"))
        val w=if(free)null else requireNotNull(wallet)
        val effectiveNote=if(free && investmentCashTrimmedText(note)==null){if(buying)promotionalNote else lossNote} else note
        if(buying) {
            val fundingRate=w?.let{purchaseRate(it.currencyCode,code,rates)}
            val funding=w?.let{if(it.currencyCode==code)account else investmentPurchaseConvertedMinor(account,code,it.currencyCode,fundingRate?.first ?: error("Missing rate"),true)}
            TradeFormRequest.Buy(InvestmentPurchaseRequest(InvestmentPurchaseDraft(id,a.id,q.stripTrailingZeros().toPlainString(),unit,gross,account,code,sourceRate?.first,sourceRate?.second?.provider,sourceRate?.second?.rateDate,
                w?.id,funding,fundingRate?.first,effectiveNote,occurredAt,createdAt),a,w,null,ledgerTitle))
        } else {
            val capitalRate=w?.let{purchaseRate(code,it.currencyCode,rates)}
            if(w!=null && w.currencyCode!=code)investmentPurchaseConvertedMinor(account,code,w.currencyCode,capitalRate?.first ?: error("Missing rate"))
            TradeFormRequest.Sell(InvestmentSaleRequest(InvestmentSaleDraft(id,a.id,q.stripTrailingZeros().toPlainString(),unit,gross,account,code,sourceRate?.first,sourceRate?.second?.provider,sourceRate?.second?.rateDate,
                w?.id,capitalRate?.first,effectiveNote,occurredAt,createdAt),a,w,null,ledgerTitle))
        }
    }.getOrNull()}
    fun execute(r:TradeFormRequest) {
        if(session.saving || request==null || r.withConsent(null)!=request || (!enoughStock && !candidate))return
        session.saving=true;session.error=null;session.review=null;session.failed=null
        scope.launch {
            try {
                val device=deviceIdProvider();coroutineContext.ensureActive()
                val result=when(r){
                    is TradeFormRequest.Buy->repository.savePurchase(owner,r.value,device,now())
                    is TradeFormRequest.Sell->repository.saveSale(owner,r.value,device,now())
                };coroutineContext.ensureActive()
                val error=result.exceptionOrNull()
                when {
                    result.isSuccess->onDismiss()
                    error is InvestmentPurchaseConfirmationRequired->if(error.review.requiresConfirmation)session.review=r.withConsent(null) to error.review else session.error=InvestmentAssetException(InvestmentAssetError.STALE_RECORD)
                    error is InvestmentSaleConfirmationRequired->if(error.review.requiresConfirmation)session.review=r.withConsent(null) to error.review else session.error=InvestmentAssetException(InvestmentAssetError.STALE_RECORD)
                    else->{session.error=error;session.failed=r}
                }
            }catch(cancelled:kotlinx.coroutines.CancellationException){throw cancelled}
            catch(error:Exception){session.error=error;session.failed=r}
            finally{session.saving=false}
        }
    }
    val sheet=rememberModalBottomSheetState(skipPartiallyExpanded=true,confirmValueChange={it!=SheetValue.Hidden || !session.saving})
    ModalBottomSheet(onDismissRequest={if(!session.saving)onDismiss()},sheetState=sheet) {
        Column(Modifier.fillMaxWidth().testTag(prefix+".sheet")) {
            Column(Modifier.fillMaxWidth().padding(horizontal=20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                Text(stringResource(if(buying)R.string.investment_trade_new_buy_title else R.string.investment_trade_new_sell_title),Modifier.testTag(prefix+".title"),style=MaterialTheme.typography.titleLarge)
                Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween){
                    TextButton(onClick=onDismiss,enabled=!session.saving,modifier=Modifier.heightIn(min=48.dp).testTag(prefix+".cancel")){Text(stringResource(R.string.common_cancel))}
                    Button(onClick={request?.let(::execute)},enabled=request!=null && (enoughStock || candidate) && !session.saving,modifier=Modifier.heightIn(min=48.dp).testTag(prefix+".save")){Text(stringResource(R.string.common_save))}
                }
            }
            Column(Modifier.fillMaxWidth().weight(1f,false).verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
                if(!buying && data!=null && data.third.investmentLinkedWalletId==null) {
                    Text(stringResource(R.string.investment_wallet_sell_without_linked_warning),Modifier.testTag(prefix+".linkedWarning"))
                    TextButton(onClick=onSetupLinked,enabled=!session.saving,modifier=Modifier.testTag(prefix+".setupLinked")){Text(stringResource(R.string.investment_wallet_set_up_now))}
                }
                Box {
                    OutlinedButton(onClick={assetMenu=true},enabled=data!=null && !session.saving,modifier=Modifier.fillMaxWidth().testTag(prefix+".asset")){Text(asset?.name ?: stringResource(R.string.investment_trade_choose_asset))}
                    DropdownMenu(expanded=assetMenu,onDismissRequest={assetMenu=false}){assets.forEach{a->DropdownMenuItem(text={Text(a.name)},onClick={assetId=a.id;unit=a.defaultUnitLabel.orEmpty();assetMenu=false;session.review=null;session.failed=null;session.error=null},modifier=Modifier.testTag(prefix+".asset."+a.id))}}
                }
                if(asset?.defaultUnitLabel==null)Text(stringResource(R.string.investment_trade_resolve_unit_before_trading),color=MaterialTheme.colorScheme.error)
                OutlinedTextField(quantity,{quantity=it;session.review=null;session.failed=null;session.error=null},enabled=!session.saving,label={Text(stringResource(R.string.investment_trade_quantity))},keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Decimal),singleLine=true,modifier=Modifier.fillMaxWidth().testTag(prefix+".quantity"))
                if(!buying)Text(stringResource(R.string.investment_trade_available_quantity,available?.let{it.toPlainString()+" "+InvestmentUnitLabel.normalizedDisplay(unit).orEmpty()} ?: "—"),Modifier.testTag(prefix+".available"))
                OutlinedTextField(unit,{unit=it;session.review=null;session.failed=null;session.error=null},enabled=!session.saving,label={Text(stringResource(R.string.investment_trade_unit))},singleLine=true,modifier=Modifier.fillMaxWidth().testTag(prefix+".unit"))
                Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween){Text(if(buying)stringResource(R.string.investment_trade_is_promotional_free) else stringResource(R.string.investment_trade_is_total_loss,formatMinorUnits(0,asset?.currencyCode ?: "JPY")),Modifier.weight(1f));Switch(free,{free=it;session.review=null;session.failed=null;session.error=null},enabled=!session.saving,modifier=Modifier.testTag(prefix+".free"))}
                if(free)Text(if(buying)stringResource(R.string.investment_trade_promotional_free_description) else stringResource(R.string.investment_trade_total_loss_description,formatMinorUnits(0,asset?.currencyCode ?: "JPY")),Modifier.testTag(prefix+".zero.description"))
                else {
                    val measurer=rememberTextMeasurer();val amountStyle=MaterialTheme.typography.bodyLarge
                    BoxWithConstraints(Modifier.fillMaxWidth()) {
                        val inset=with(androidx.compose.ui.platform.LocalDensity.current){32.dp.toPx()}
                        var size=amountStyle.fontSize.value
                        while(size>12f && measurer.measure(amount,amountStyle.copy(fontSize=size.sp)).size.width>constraints.maxWidth-inset)size-=0.5f
                        OutlinedTextField(amount,{amount=currencyAmountInput(it,asset?.currencyCode.orEmpty());session.review=null;session.failed=null;session.error=null},enabled=!session.saving,
                            label={Text(stringResource(if(buying)R.string.investment_trade_buy_total else R.string.investment_trade_sell_total)+" · "+asset?.currencyCode.orEmpty())},textStyle=amountStyle.copy(fontSize=size.sp),
                            keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Decimal),singleLine=true,modifier=Modifier.fillMaxWidth().testTag(prefix+".amount"))
                    }
                    Box {
                        OutlinedButton(onClick={walletMenu=true},enabled=data!=null && !session.saving,modifier=Modifier.fillMaxWidth().testTag(prefix+".wallet")){Text(wallet?.let{it.name+" · "+it.currencyCode} ?: stringResource(if(buying)R.string.investment_trade_funding_wallet else R.string.investment_trade_capital_wallet))}
                        DropdownMenu(expanded=walletMenu,onDismissRequest={walletMenu=false}){wallets.forEach{w->DropdownMenuItem(text={Text(w.name+" · "+w.currencyCode)},onClick={walletId=w.id;walletMenu=false;session.review=null;session.failed=null;session.error=null},modifier=Modifier.testTag(prefix+".wallet."+w.id))}}
                    }
                    when(val r=request) {
                        is TradeFormRequest.Buy->r.value.draft.let{draft->Text(formatMinorUnits(draft.accountingMinor,draft.accountingCurrency),Modifier.testTag(prefix+".accounting"));draft.fundingMinor?.let{Text(formatMinorUnits(it,wallet?.currencyCode.orEmpty()),Modifier.testTag(prefix+".funding"))}}
                        is TradeFormRequest.Sell->r.value.draft.let{draft->Text(formatMinorUnits(draft.accountingMinor,draft.accountingCurrency),Modifier.testTag(prefix+".accounting"))}
                        null->Unit
                    }
                    if(request==null && amount.isNotEmpty() && quantity.isNotEmpty()) {
                        val missingRate=data?.third?.currencyCode?.let{code->(asset?.currencyCode?.let{it!=code && purchaseRate(it,code,rates)==null}==true) || (wallet?.currencyCode?.let{it!=code && purchaseRate(it,code,rates)==null}==true)}==true
                        Text(stringResource(if(missingRate)R.string.investment_error_missing_exchange_rate else R.string.investment_error_invalid_amount),Modifier.testTag(prefix+".input.error"),color=MaterialTheme.colorScheme.error)
                    }
                }
                Text(stringResource(R.string.investment_trade_time),style=MaterialTheme.typography.labelLarge)
                InvestmentCashDateTime(occurredAt,{occurredAt=it;session.review=null;session.failed=null;session.error=null},!session.saving)
                OutlinedTextField(note,{note=it;session.review=null;session.failed=null;session.error=null},enabled=!session.saving,label={Text(stringResource(R.string.investment_trade_note))},modifier=Modifier.fillMaxWidth().testTag(prefix+".note"))
                if(data==null){Text(stringResource(R.string.common_error));TextButton(onClick={session.error=null;retry++},modifier=Modifier.testTag(prefix+".reload")){Text(stringResource(R.string.planning_installment_retry))}}
                session.error?.let{Text(stringResource(purchaseErrorResource(it)),Modifier.testTag(prefix+".error"),color=MaterialTheme.colorScheme.error)}
                session.failed?.let{failed->TextButton(onClick={execute(failed)},enabled=!session.saving && failed.withConsent(null)==request && (enoughStock || candidate),modifier=Modifier.testTag(prefix+".retry")){Text(stringResource(R.string.planning_installment_retry))}}
                if(session.saving)CircularProgressIndicator(Modifier.size(24.dp))
            }
        }
    }
    session.review?.let{(frozen,review)->
        val adapter=InvestmentFundUsageReview(InvestmentFundUsageConsent(owner.value,if(buying)investmentLedgerIdentity(id,"funding") else id,"",""),review.comparison,review.requiresConfirmation)
        InvestmentFundUsageDialog(adapter,wallets,onDismiss={session.review=null},onConfirm={execute(frozen.withConsent(review.consent))},isSaving=session.saving,tagPrefix=prefix+".funds",canConfirm=frozen==request && (enoughStock || candidate),tradeChanges=true,contextMessage=if(buying)null else stringResource(R.string.investment_trade_sale_cash_review_context))
    }
}
private fun purchaseInputMinor(text:String,code:String):Long?=runCatching{BigDecimal(text.trim().replace(",","")).movePointRight(Currency.getInstance(code).defaultFractionDigits).setScale(0,RoundingMode.UNNECESSARY).longValueExact()}.getOrNull()
internal fun purchaseRate(source:String,destination:String,rates:List<ExchangeRateSnapshot>):Pair<String,ExchangeRateSnapshot>? {
    if(source==destination)return null
    val direct=rates.firstOrNull{it.baseCurrencyCode==source && it.quoteCurrencyCode==destination && it.rateDecimalString.toBigDecimalOrNull()?.signum()==1}
    if(direct!=null)return direct.rateDecimalString to direct
    val inverse=rates.firstOrNull{it.baseCurrencyCode==destination && it.quoteCurrencyCode==source && it.rateDecimalString.toBigDecimalOrNull()?.signum()==1} ?: return null
    return runCatching{investmentPurchaseInverseRate(inverse.rateDecimalString) to inverse}.getOrNull()
}
private fun purchaseErrorResource(error:Throwable):Int=when(error) {
    is InvestmentAccountingException->when(error.reason){
        InvestmentAccountingError.INSUFFICIENT_POSITION->R.string.investment_error_insufficient_position
        InvestmentAccountingError.INVALID_QUANTITY->R.string.investment_error_invalid_quantity
        InvestmentAccountingError.ARITHMETIC_OVERFLOW->R.string.investment_error_arithmetic_overflow
        else->R.string.investment_error_invalid_trade_input
    }
    is InvestmentFundTimelineException->if(error.reason==InvestmentFundTimelineError.UNSUPPORTED_CURRENCY_CONVERSION)R.string.investment_error_fund_usage_currency_mismatch else R.string.common_error
    is TransactionValidationException->R.string.investment_error_insufficient_funds
    else->investmentAssetErrorResource(error)
}
