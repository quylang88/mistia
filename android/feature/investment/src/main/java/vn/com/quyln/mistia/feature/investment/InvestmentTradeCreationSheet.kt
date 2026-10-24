package vn.com.quyln.mistia.feature.investment

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
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
import kotlinx.coroutines.isActive
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
    data class Edit(val value:InvestmentTradeEditRequest):TradeFormRequest
}
private fun TradeFormRequest.withConsent(consent:InvestmentTradeCreationConsent?):TradeFormRequest=when(this){
    is TradeFormRequest.Buy->copy(value=value.copy(consent=consent))
    is TradeFormRequest.Sell->copy(value=value.copy(consent=consent))
    is TradeFormRequest.Edit->copy(value=value.copy(consent=consent))
}
private fun sameTradeFormWallet(a:LedgerWalletRecord?,b:LedgerWalletRecord?):Boolean=
    if(a==null)b==null else b!=null && a.matchesVisibleInvestmentWallet(b)
private fun TradeFormRequest.matchesIntent(other:TradeFormRequest?):Boolean=when(this){
    is TradeFormRequest.Buy->other is TradeFormRequest.Buy &&
        value.expectedAsset.matchesVisibleInvestmentAsset(other.value.expectedAsset) && sameTradeFormWallet(value.expectedWallet,other.value.expectedWallet) &&
        value.copy(expectedAsset=other.value.expectedAsset,expectedWallet=other.value.expectedWallet,consent=null)==other.value.copy(consent=null)
    is TradeFormRequest.Edit->other is TradeFormRequest.Edit && value.expectedTrade.matchesVisibleInvestmentTrade(other.value.expectedTrade) &&
        value.expectedAsset.matchesVisibleInvestmentAsset(other.value.expectedAsset) && sameTradeFormWallet(value.expectedWallet,other.value.expectedWallet) &&
        value.copy(expectedTrade=other.value.expectedTrade,expectedAsset=other.value.expectedAsset,expectedWallet=other.value.expectedWallet,consent=null)==other.value.copy(consent=null)
    is TradeFormRequest.Sell->other is TradeFormRequest.Sell &&
        value.expectedAsset.matchesVisibleInvestmentAsset(other.value.expectedAsset) && sameTradeFormWallet(value.expectedWallet,other.value.expectedWallet) &&
        value.copy(expectedAsset=other.value.expectedAsset,expectedWallet=other.value.expectedWallet,consent=null)==other.value.copy(consent=null)
}
private class TradeFormReview(val request:TradeFormRequest,val review:InvestmentTradeCreationReview)
private class TradeFormFailure(val request:TradeFormRequest)
private class TradeFormSession {
    var open=true
    var sourceAvailable=false
    var sourceEpoch by mutableStateOf(Any())
    var saving by mutableStateOf(false)
    var error by mutableStateOf<Throwable?>(null)
    var review by mutableStateOf<TradeFormReview?>(null)
    var failed by mutableStateOf<TradeFormFailure?>(null)
    fun revokeReadAuthority(){sourceEpoch=Any();review=null;failed=failed?.let{TradeFormFailure(it.request)}}
    fun invalidateSource(){sourceAvailable=false;revokeReadAuthority()}
}

@Composable internal fun InvestmentPurchaseSheet(owner:UserId,repository:InvestmentRepository,id:String,initialAssetId:String?,
    rates:List<ExchangeRateSnapshot>,deviceIdProvider:suspend ()->String,onDismiss:()->Unit,now:()->String={Instant.now().toString()}) =
    InvestmentTradeCreationSheet(owner,repository,id,initialAssetId,rates,deviceIdProvider,onDismiss,now,InvestmentTradeKind.BUY,{})

@Composable internal fun InvestmentSaleSheet(owner:UserId,repository:InvestmentRepository,id:String,initialAssetId:String?,
    rates:List<ExchangeRateSnapshot>,deviceIdProvider:suspend ()->String,onDismiss:()->Unit,onSetupLinked:()->Unit,now:()->String={Instant.now().toString()}) =
    InvestmentTradeCreationSheet(owner,repository,id,initialAssetId,rates,deviceIdProvider,onDismiss,now,InvestmentTradeKind.SELL,onSetupLinked)

@Composable internal fun InvestmentTradeEditingSheet(owner:UserId,repository:InvestmentRepository,expected:CloudRecord,
    rates:List<ExchangeRateSnapshot>,deviceIdProvider:suspend ()->String,onDismiss:()->Unit,onSetupLinked:()->Unit,now:()->String={Instant.now().toString()}) {
    val kind=if(expected.payload.financeRawString("kind_raw_value")=="buy")InvestmentTradeKind.BUY else InvestmentTradeKind.SELL
    InvestmentTradeCreationSheet(owner,repository,expected.id,expected.payload.financeRawString("asset_id"),rates,deviceIdProvider,onDismiss,now,kind,onSetupLinked,expected)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun InvestmentTradeCreationSheet(owner:UserId,repository:InvestmentRepository,id:String,initialAssetId:String?,
    rates:List<ExchangeRateSnapshot>,deviceIdProvider:suspend ()->String,onDismiss:()->Unit,now:()->String,kind:InvestmentTradeKind,onSetupLinked:()->Unit,expected:CloudRecord?=null) {
    val buying=kind==InvestmentTradeKind.BUY
    val prefix=if(expected!=null)"investment.edit" else if(buying)"investment.purchase" else "investment.sale"
    var createdAt by rememberSaveable{mutableStateOf(expected?.payload?.financeRawString("created_at") ?: now())}
    var occurredAt by rememberSaveable{mutableStateOf(expected?.payload?.financeRawString("occurred_at") ?: createdAt)}
    var assetId by rememberSaveable{mutableStateOf(initialAssetId)}
    var walletId by rememberSaveable{mutableStateOf(expected?.payload?.financeRawString(if(buying)"funding_wallet_id" else "capital_return_wallet_id"))}
    var quantity by rememberSaveable{mutableStateOf(expected?.payload?.financeRawString("quantity_decimal_string").orEmpty())}
    var unit by rememberSaveable{mutableStateOf(expected?.payload?.financeRawString("unit_label").orEmpty())}
    var amount by rememberSaveable{mutableStateOf(expected?.payload?.let{p->p.financeRawLong("gross_amount_minor")?.toBigDecimal()?.movePointLeft(Currency.getInstance(p.financeRawString("currency_code")).defaultFractionDigits)?.toPlainString()}.orEmpty())}
    var free by rememberSaveable{mutableStateOf(expected?.payload?.financeRawLong("gross_amount_minor")==0L)}
    var note by rememberSaveable{mutableStateOf(expected?.payload?.financeRawString("note").orEmpty())}
    var assetMenu by remember{mutableStateOf(false)}
    var walletMenu by remember{mutableStateOf(false)}
    var retry by remember{mutableIntStateOf(0)}
    val session=remember(owner,repository,id,kind){TradeFormSession()}
    val scope=key(repository){rememberCoroutineScope()}
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    val snapshot by key(owner,repository,id,retry,lifecycle,kind){produceState<InvestmentTradeCreationSnapshot?>(null){
        try{lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED){
            value=null;session.invalidateSource()
            try{(if(buying)repository.observePurchaseSnapshot(owner) else repository.observeSaleSnapshot(owner)).collect{source ->
                value=source.takeIf{it.owner==owner && it.rows.all{row->CloudEntity.fromTable(row.entity)?.let{entity->entity in InvestmentPurchaseSnapshot.entities && row.financeRawIdentity(owner,entity,true)}==true}}
                if(value==null)session.invalidateSource() else session.sourceAvailable=true
            }}finally{if(!kotlinx.coroutines.currentCoroutineContext().isActive){value=null;session.invalidateSource()}}
        }}catch(cancelled:kotlinx.coroutines.CancellationException){throw cancelled}catch(error:Exception){value=null;session.invalidateSource();session.error=error}
    }}
    val parsed=remember(snapshot){snapshot?.let{source->runCatching {
        val channels=source.rows.filter{it.entity==CloudEntity.INVESTMENT_CHANNEL.table && it.financeRawDeleted()==false}.map(InvestmentChannelRecord::fromCloudRecord).filterNot{it.isArchived}.map{it.id}.toSet()
        val assets=source.rows.filter{it.entity==CloudEntity.INVESTMENT_ASSET.table && it.financeRawDeleted()==false}.map(InvestmentAssetRecord::fromCloudRecord).filter{!it.isArchived && it.channelId in channels}
        val wallets=source.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table && it.financeRawDeleted()==false}.map(::investmentLinkedWalletRecord)
        Triple(assets,wallets.filter{!it.isArchived && it.kind!=null && it.kind!=WalletKind.INVESTMENT && (buying || it.kind!=WalletKind.CREDIT_CARD)},wallets.single{it.id==investmentSystemWalletId(owner)})
    }}}
    val data=parsed?.getOrNull()
    val latestSnapshot by rememberUpdatedState(snapshot)
    val latestData by rememberUpdatedState(data)
    val latestRates by rememberUpdatedState(rates)
    val latestResources by rememberUpdatedState(LocalContext.current.resources)
    val latestReadable by rememberUpdatedState(data!=null && snapshot!=null)
    LaunchedEffect(data==null){if(data==null)session.revokeReadAuthority()}
    val positions=remember(snapshot,data?.first){data?.first?.associate{a->a.id to runCatching{investmentTradePositions(snapshot?.rows.orEmpty().filterNot{expected!=null && it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==id},a)}.getOrNull()}}
    val assets=data?.first.orEmpty().filter{a->buying || a.id==assetId || positions?.get(a.id)?.any{it.quantity.signum()>0}==true}
    val wallets=data?.second.orEmpty()
    val asset=assets.singleOrNull{it.id==assetId};val wallet=wallets.singleOrNull{it.id==walletId}
    LaunchedEffect(assets,wallets){
        if(assetId==null){assetId=assets.firstOrNull()?.id;unit=assets.firstOrNull()?.defaultUnitLabel.orEmpty()}
        else if(unit.isEmpty())unit=asset?.defaultUnitLabel.orEmpty()
        if(walletId==null)walletId=wallets.firstOrNull()?.id
    }
    val available=positions?.get(assetId)?.let{values->
        values.firstOrNull{InvestmentUnitLabel.comparisonKey(it.unitLabel)==InvestmentUnitLabel.comparisonKey(unit)}?.quantity ?: BigDecimal.ZERO
    }
    val candidate=expected==null && snapshot?.rows?.any{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==id}==true
    val desiredQuantity=investmentTradeQuantity(quantity.trim().replace(',','.'))
    val enoughStock=buying || (available!=null && desiredQuantity!=null && desiredQuantity<=available)
    fun currentRequest():TradeFormRequest?=runCatching {
        val view=requireNotNull(latestData)
        val a=requireNotNull(view.first.singleOrNull{it.id==assetId});val code=view.third.currencyCode
        val selectedWallet=view.second.singleOrNull{it.id==walletId}
        val currentRates=latestRates;val resources=latestResources
        val ledgerTitle=resources.getString(R.string.investment_cash_automatic_reconciliation_title)
        val q=requireNotNull(investmentTradeQuantity(quantity.trim().replace(',','.')))
        require(InvestmentUnitLabel.normalizedDisplay(unit)!=null && a.defaultUnitLabel!=null)
        val gross=if(free)0L else purchaseInputMinor(amount,a.currencyCode)?.takeIf{it>0} ?: error("Invalid amount")
        val preservesRate=expected!=null && expected.payload.financeRawLong("gross_amount_minor")?.let{it>0}==true && expected.payload.financeRawString("currency_code")==a.currencyCode && expected.payload.financeRawString("accounting_currency_code")==code
        val storedRate=expected?.payload?.financeRawString("exchange_rate_decimal_string")
        val sourceRate=if(free || preservesRate)null else purchaseRate(a.currencyCode,code,currentRates)
        val sourceRateValue=if(free)null else if(preservesRate)storedRate else sourceRate?.first
        val provider=if(free)null else if(preservesRate)expected?.payload?.financeRawString("exchange_rate_provider") else sourceRate?.second?.provider
        val rateDate=if(free)null else if(preservesRate)expected?.payload?.financeRawString("exchange_rate_date") else sourceRate?.second?.rateDate
        val account=if(a.currencyCode==code || free)gross else investmentPurchaseConvertedMinor(gross,a.currencyCode,code,sourceRateValue ?: error("Missing rate"))
        val w=if(free)null else requireNotNull(selectedWallet)
        val effectiveNote=if(free && investmentCashTrimmedText(note)==null){
            if(buying)resources.getString(R.string.investment_trade_promotional_free_badge)
            else resources.getString(R.string.investment_trade_total_loss_badge,formatMinorUnits(0,a.currencyCode))
        } else note
        if(buying) {
            val fundingRate=w?.let{purchaseRate(it.currencyCode,code,currentRates)}
            val funding=w?.let{if(it.currencyCode==code)account else investmentPurchaseConvertedMinor(account,code,it.currencyCode,fundingRate?.first ?: error("Missing rate"),true)}
            if(expected!=null)TradeFormRequest.Edit(InvestmentTradeEditRequest(expected,InvestmentTradeEditDraft(id,a.id,kind,q.stripTrailingZeros().toPlainString(),unit,gross,account,code,sourceRateValue,provider,rateDate,w?.id,funding,fundingRate?.first,effectiveNote,occurredAt,createdAt),a,w,null,ledgerTitle))
            else TradeFormRequest.Buy(InvestmentPurchaseRequest(InvestmentPurchaseDraft(id,a.id,q.stripTrailingZeros().toPlainString(),unit,gross,account,code,sourceRateValue,provider,rateDate,
                w?.id,funding,fundingRate?.first,effectiveNote,occurredAt,createdAt),a,w,null,ledgerTitle))
        } else {
            val capitalRate=w?.let{purchaseRate(code,it.currencyCode,currentRates)}
            if(w!=null && w.currencyCode!=code)investmentPurchaseConvertedMinor(account,code,w.currencyCode,capitalRate?.first ?: error("Missing rate"))
            if(expected!=null)TradeFormRequest.Edit(InvestmentTradeEditRequest(expected,InvestmentTradeEditDraft(id,a.id,kind,q.stripTrailingZeros().toPlainString(),unit,gross,account,code,sourceRateValue,provider,rateDate,w?.id,null,capitalRate?.first,effectiveNote,occurredAt,createdAt),a,w,null,ledgerTitle))
            else TradeFormRequest.Sell(InvestmentSaleRequest(InvestmentSaleDraft(id,a.id,q.stripTrailingZeros().toPlainString(),unit,gross,account,code,sourceRateValue,provider,rateDate,
                w?.id,capitalRate?.first,effectiveNote,occurredAt,createdAt),a,w,null,ledgerTitle))
        }
    }.getOrNull()
    val request=currentRequest()
    val saveEpoch=session.sourceEpoch
    fun currentCanSubmit(r:TradeFormRequest):Boolean=runCatching {
        val rows=requireNotNull(latestSnapshot).rows
        if(buying || (expected==null && rows.any{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==id}))true
        else {
            val selectedAssetId=when(r){is TradeFormRequest.Sell->r.value.draft.assetId;is TradeFormRequest.Edit->r.value.draft.assetId;else->error("Invalid sale")}
            val selectedUnit=when(r){is TradeFormRequest.Sell->r.value.draft.unit;is TradeFormRequest.Edit->r.value.draft.unit;else->error("Invalid sale")}
            val selectedQuantity=when(r){is TradeFormRequest.Sell->r.value.draft.quantity;is TradeFormRequest.Edit->r.value.draft.quantity;else->error("Invalid sale")}
            val currentAsset=requireNotNull(latestData?.first?.singleOrNull{it.id==selectedAssetId})
            val stock=investmentTradePositions(rows.filterNot{expected!=null && it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==id},currentAsset).firstOrNull{
                InvestmentUnitLabel.comparisonKey(it.unitLabel)==InvestmentUnitLabel.comparisonKey(selectedUnit)
            }?.quantity ?: BigDecimal.ZERO
            requireNotNull(investmentTradeQuantity(selectedQuantity))<=stock
        }
    }.getOrDefault(false)
    fun execute(r:TradeFormRequest) {
        if(!session.open || !session.sourceAvailable || !latestReadable || session.saving || !r.matchesIntent(currentRequest()) || !currentCanSubmit(r))return
        val sourceEpoch=session.sourceEpoch
        session.saving=true;session.error=null;session.review=null;session.failed=null
        scope.launch {
            try {
                val device=deviceIdProvider();coroutineContext.ensureActive()
                val result=when(r){
                    is TradeFormRequest.Buy->repository.savePurchase(owner,r.value,device,now())
                    is TradeFormRequest.Sell->repository.saveSale(owner,r.value,device,now())
                    is TradeFormRequest.Edit->repository.editTrade(owner,r.value,device,now())
                };coroutineContext.ensureActive()
                val error=result.exceptionOrNull()
                val requestedReview=when(error){
                    is InvestmentPurchaseConfirmationRequired->error.review
                    is InvestmentSaleConfirmationRequired->error.review
                    is InvestmentTradeEditConfirmationRequired->error.review
                    else->null
                }
                when {
                    result.isSuccess->{session.open=false;onDismiss()}
                    requestedReview!=null->if(session.open)when {
                        !session.sourceAvailable || !latestReadable->session.error=InvestmentAssetException(InvestmentAssetError.UNREADABLE_SOURCE)
                        session.sourceEpoch!==sourceEpoch->session.error=InvestmentAssetException(InvestmentAssetError.STALE_RECORD)
                        requestedReview.requiresConfirmation->session.review=TradeFormReview(r.withConsent(null),requestedReview)
                        else->session.error=InvestmentAssetException(InvestmentAssetError.STALE_RECORD)
                    }
                    else->{session.error=error;session.failed=TradeFormFailure(r)}
                }
            }catch(cancelled:kotlinx.coroutines.CancellationException){throw cancelled}
            catch(error:Exception){session.error=error;session.failed=TradeFormFailure(r)}
            finally{session.saving=false}
        }
    }
    fun dismiss(){if(!session.saving && session.open){session.open=false;session.review=null;session.failed=null;onDismiss()}}
    val sheet=rememberModalBottomSheetState(skipPartiallyExpanded=true,confirmValueChange={it!=SheetValue.Hidden || !session.saving})
    ModalBottomSheet(onDismissRequest=::dismiss,sheetState=sheet) {
        Column(Modifier.fillMaxWidth().testTag(prefix+".sheet")) {
            Column(Modifier.fillMaxWidth().padding(horizontal=20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                Text(stringResource(if(expected!=null)R.string.investment_trade_detail_title else if(buying)R.string.investment_trade_new_buy_title else R.string.investment_trade_new_sell_title),Modifier.testTag(prefix+".title"),style=MaterialTheme.typography.titleLarge)
                if(expected!=null)Text(stringResource(if(buying)R.string.investment_hub_buy else R.string.investment_hub_sell),Modifier.testTag(prefix+".kind"),style=MaterialTheme.typography.labelLarge)
                Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween){
                    TextButton(onClick=::dismiss,enabled=!session.saving,modifier=Modifier.heightIn(min=48.dp).testTag(prefix+".cancel")){Text(stringResource(R.string.common_cancel))}
                    key(saveEpoch){Button(onClick={if(session.sourceEpoch===saveEpoch)currentRequest()?.let(::execute)},enabled=request!=null && (enoughStock || candidate) && !session.saving,modifier=Modifier.heightIn(min=48.dp).testTag(prefix+".save")){Text(stringResource(R.string.common_save))}}
                }
            }
            Column(Modifier.fillMaxWidth().weight(1f,false).verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
                if(!buying && data!=null && data.third.investmentLinkedWalletId==null) {
                    Text(stringResource(R.string.investment_wallet_sell_without_linked_warning),Modifier.testTag(prefix+".linkedWarning"))
                    TextButton(onClick=onSetupLinked,enabled=!session.saving,modifier=Modifier.testTag(prefix+".setupLinked")){Text(stringResource(R.string.investment_wallet_set_up_now))}
                }
                Box {
                    OutlinedButton(onClick={assetMenu=true},enabled=data!=null && !session.saving,modifier=Modifier.fillMaxWidth().testTag(prefix+".asset")){asset?.let{InvestmentProductThumbnail(owner,repository,it.id,it.imagePath,Modifier.padding(end=10.dp),34.dp)};Text(asset?.name ?: stringResource(R.string.investment_trade_choose_asset))}
                    DropdownMenu(expanded=assetMenu,onDismissRequest={assetMenu=false}){assets.forEach{a->DropdownMenuItem(leadingIcon={InvestmentProductThumbnail(owner,repository,a.id,a.imagePath, size=44.dp)},text={Text(a.name)},onClick={assetId=a.id;unit=a.defaultUnitLabel.orEmpty();assetMenu=false;session.review=null;session.failed=null;session.error=null},modifier=Modifier.testTag(prefix+".asset."+a.id))}}
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
                        is TradeFormRequest.Edit->r.value.draft.let{draft->Text(formatMinorUnits(draft.accountingMinor,draft.accountingCurrency),Modifier.testTag(prefix+".accounting"));if(buying)draft.walletMinor?.let{Text(formatMinorUnits(it,wallet?.currencyCode.orEmpty()),Modifier.testTag(prefix+".funding"))}}
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
                session.error?.let{Text(stringResource(investmentTradeErrorResource(it)),Modifier.testTag(prefix+".error"),color=MaterialTheme.colorScheme.error)}
                session.failed?.let{failed->key(failed){TextButton(onClick={if(session.failed===failed)execute(failed.request)},enabled=!session.saving && failed.request.matchesIntent(request) && (enoughStock || candidate),modifier=Modifier.testTag(prefix+".retry")){Text(stringResource(R.string.planning_installment_retry))}}}
                if(session.saving)CircularProgressIndicator(Modifier.size(24.dp))
            }
        }
    }
    session.review?.let{prompt->
        val frozen=prompt.request;val review=prompt.review
        val adapter=InvestmentFundUsageReview(InvestmentFundUsageConsent(owner.value,if(buying)investmentLedgerIdentity(id,"funding") else id,"",""),review.comparison,review.requiresConfirmation)
        InvestmentFundUsageDialog(adapter,wallets,onDismiss={if(session.review===prompt)session.review=null},onConfirm={if(session.review===prompt)execute(frozen.withConsent(review.consent))},isSaving=session.saving,tagPrefix=prefix+".funds",canConfirm=frozen.matchesIntent(request) && (enoughStock || candidate),tradeAction=InvestmentTradeFundAction.SAVE,contextMessage=if(buying)null else stringResource(R.string.investment_trade_sale_cash_review_context))
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
internal fun investmentTradeErrorResource(error:Throwable):Int=when(error) {
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
