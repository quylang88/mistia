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
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.math.BigInteger
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun InvestmentCashReconciliationSheet(owner:UserId,repository:InvestmentRepository,deviceIdProvider:suspend ()->String,
    selectedWalletId:String?,load:InvestmentWalletReadLoad,onRetry:()->Unit,onDismiss:()->Unit) {
    val title=stringResource(if(selectedWalletId==null)R.string.investment_wallet_reconcile_all else R.string.investment_wallet_reconcile)
    val translatedLedgerTitle=stringResource(R.string.investment_cash_reconciliation_title)
    val ledgerTitle by rememberSaveable{mutableStateOf(translatedLedgerTitle)}
    val createdAt by rememberSaveable{mutableStateOf(Instant.now().toString())}
    var expectedToken by rememberSaveable{mutableStateOf<String?>(null)}
    var eventsToken by rememberSaveable{mutableStateOf("{}")}
    var amountText by rememberSaveable{mutableStateOf("")}
    var confirmed by rememberSaveable{mutableStateOf(false)}
    var attemptDevice by rememberSaveable{mutableStateOf<String?>(null)}
    var saving by remember(repository){mutableStateOf(false)}
    var error by remember{mutableStateOf<Int?>(null)}
    val scope=key(repository){rememberCoroutineScope()}
    val snapshot=(load as? InvestmentWalletReadLoad.Loaded)?.snapshot
    val parsed=remember(snapshot){snapshot?.let{runCatching{readInvestmentCashReconciliation(it)}}}
    val current=parsed?.getOrNull()
    val expected=remember(expectedToken){expectedToken?.let{decodeReconciliationView(owner,it)}}
    val locations=expected?.locations.orEmpty().filter{selectedWalletId==null || it.wallet.id==selectedWalletId}
    val code=expected?.system?.currencyCode ?: current?.system?.currencyCode
    val amount=runCatching{BigInteger(amountText.replace(",","").trim()).longValueExact()}.getOrNull()?.takeIf{it>0}
    fun capture(value:InvestmentCashReconciliationView,initial:Boolean) {
        expectedToken=encodeReconciliationView(value);confirmed=false;error=null
        val old=runCatching{Json.parseToJsonElement(eventsToken).jsonObject}.getOrDefault(JsonObject(emptyMap()))
        eventsToken=buildJsonObject{value.locations.forEach{put(it.wallet.id,old.financeRawString(it.wallet.id) ?: UUID.randomUUID().toString())}}.toString()
        if(initial && selectedWalletId!=null)amountText=value.locations.singleOrNull{it.wallet.id==selectedWalletId}?.bookedMinor?.min(BigInteger.valueOf(Long.MAX_VALUE))?.let{currencyAmountInput(it.toString(),value.system.currencyCode)}.orEmpty()
    }
    LaunchedEffect(current,expectedToken){if(expectedToken==null && current!=null)capture(current,true)}
    val transfers=remember(expected,eventsToken,amount,selectedWalletId){runCatching {
        val events=Json.parseToJsonElement(eventsToken).jsonObject
        require(locations.isNotEmpty())
        locations.map{location->InvestmentCashReconciliationTransfer(requireNotNull(events.financeRawString(location.wallet.id)),location.wallet.id,
            if(selectedWalletId!=null)requireNotNull(amount) else location.bookedMinor.longValueExact())}
    }.getOrNull()}
    val staged=if(expected!=null && transfers!=null)InvestmentCashReconciliationRequest(expected,transfers,createdAt,createdAt,ledgerTitle,confirmed) else null
    val sourceConsent=expected!=null && current!=null && expected.system.matchesVisibleInvestmentWallet(current.system) && expected.linked.matchesVisibleInvestmentWallet(current.linked) &&
        locations.isNotEmpty() && locations.all{old->current.locations.singleOrNull{it.wallet.id==old.wallet.id}?.let{now->old.wallet.matchesVisibleInvestmentWallet(now.wallet) && old.bookedMinor==now.bookedMinor && old.actualMinor==now.actualMinor}==true} &&
        (selectedWalletId!=null || expected.locations.map{it.wallet.id}.toSet()==current.locations.map{it.wallet.id}.toSet())
    val replay=remember(snapshot,staged,attemptDevice){if(snapshot!=null && staged!=null && attemptDevice!=null)
        runCatching{planInvestmentCashReconciliation(snapshot,staged.copy(confirmedRealTransfer=true),requireNotNull(attemptDevice),createdAt).mutations.isEmpty()}.getOrDefault(false) else false}
    LaunchedEffect(current,sourceConsent,replay,saving){
        if(expected!=null && current!=null && !sourceConsent && !replay && !saving)confirmed=false
    }
    val affordable=transfers?.all{transfer->locations.single{it.wallet.id==transfer.sourceWalletId}.actualMinor>=BigInteger.valueOf(transfer.amountMinor)}==true
    val canSave=!saving && confirmed && staged!=null && ((sourceConsent && affordable) || replay)
    fun save() {
        if(!canSave || staged==null)return
        saving=true;error=null
        scope.launch {
            try {
                val device=deviceIdProvider();coroutineContext.ensureActive();attemptDevice=device
                val result=repository.reconcileCash(owner,staged,device,Instant.now().toString())
                coroutineContext.ensureActive()
                if(result.isSuccess)onDismiss() else error=reconciliationErrorResource(requireNotNull(result.exceptionOrNull()))
            }catch(cancelled:kotlinx.coroutines.CancellationException){throw cancelled}
            catch(failure:Exception){error=reconciliationErrorResource(failure)}
            finally{saving=false}
        }
    }
    val sheetState=rememberModalBottomSheetState(skipPartiallyExpanded=true,confirmValueChange={it!=SheetValue.Hidden || !saving})
    ModalBottomSheet(onDismissRequest={if(!saving)onDismiss()},sheetState=sheetState) {
        Column(Modifier.fillMaxWidth().testTag("investment.cash.reconciliation.sheet")) {
            Column(Modifier.fillMaxWidth().padding(horizontal=20.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
                Text(title,style=MaterialTheme.typography.titleLarge)
                Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {
                    TextButton(onClick=onDismiss,enabled=!saving,modifier=Modifier.heightIn(min=48.dp).testTag("investment.cash.reconciliation.cancel")){Text(stringResource(R.string.common_cancel))}
                    Button(onClick=::save,enabled=canSave,modifier=Modifier.heightIn(min=48.dp).testTag("investment.cash.reconciliation.save")){Text(stringResource(R.string.common_save))}
                }
            }
            Column(Modifier.fillMaxWidth().weight(1f,fill=false).verticalScroll(rememberScrollState()).padding(horizontal=20.dp).padding(bottom=24.dp)
                .testTag("investment.cash.reconciliation.body"),verticalArrangement=Arrangement.spacedBy(14.dp)) {
                Text(stringResource(R.string.investment_wallet_real_transfers),style=MaterialTheme.typography.titleMedium)
                locations.forEach{location->
                    Surface(Modifier.fillMaxWidth().testTag("investment.cash.reconciliation.instruction."+location.wallet.id),shape=MaterialTheme.shapes.large,color=MaterialTheme.colorScheme.surface) {
                    Column(Modifier.fillMaxWidth().padding(14.dp),verticalArrangement=Arrangement.spacedBy(5.dp)) {
                        Text(stringResource(R.string.investment_wallet_real_transfer_instruction,location.wallet.name,expected?.linked?.name.orEmpty()),style=MaterialTheme.typography.bodyMedium)
                        val value=if(selectedWalletId!=null)amount?.let(BigInteger::valueOf) ?: BigInteger.ZERO else location.bookedMinor
                        CashMoneyText(formatMinorUnits(value,requireNotNull(code)),"investment.cash.reconciliation.money."+location.wallet.id,MaterialTheme.typography.titleMedium.copy(color=MaterialTheme.colorScheme.primary))
                    }
                    }
                }
                if(selectedWalletId!=null) {
                    val measurer=rememberTextMeasurer();val style=MaterialTheme.typography.bodyLarge
                    BoxWithConstraints(Modifier.fillMaxWidth()) {
                        val inset=with(androidx.compose.ui.platform.LocalDensity.current){32.dp.toPx()};var size=style.fontSize.value
                        while(size>12f && measurer.measure(amountText,style.copy(fontSize=size.sp)).size.width>constraints.maxWidth-inset)size-=0.5f
                        OutlinedTextField(amountText,{amountText=currencyAmountInput(it,code.orEmpty());error=null;confirmed=false},enabled=!saving,
                            label={Text(stringResource(R.string.investment_wallet_amount_to_reconcile))},singleLine=true,textStyle=style.copy(fontSize=size.sp),
                            keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Number),modifier=Modifier.fillMaxWidth().testTag("investment.cash.reconciliation.amount"))
                    }
                    val booked=locations.singleOrNull()?.bookedMinor
                    Text(stringResource(R.string.investment_wallet_available_cash_for_transfer,booked?.let{formatMinorUnits(it,requireNotNull(code))} ?: "—"),style=MaterialTheme.typography.bodySmall)
                }
                Row(Modifier.fillMaxWidth()) {
                    Checkbox(checked=confirmed,onCheckedChange={confirmed=it},enabled=!saving && (sourceConsent || replay),modifier=Modifier.sizeIn(minWidth=48.dp,minHeight=48.dp).testTag("investment.cash.reconciliation.confirm"))
                    Text(stringResource(R.string.investment_wallet_confirmed_real_transfer),Modifier.weight(1f).padding(top=12.dp))
                }
                Text(stringResource(R.string.investment_wallet_confirmed_real_transfer_message),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                if(load==InvestmentWalletReadLoad.Loading)CircularProgressIndicator(Modifier.size(24.dp))
                if(current==null || (!sourceConsent && !replay) || transfers==null || !affordable) {
                    Text(stringResource(if(transfers==null && expected!=null) {if(selectedWalletId==null)R.string.shared_amount_calculator_result_too_large else R.string.investment_error_invalid_trade_input}
                        else if(!affordable && sourceConsent)R.string.investment_error_insufficient_funds else R.string.investment_cash_transfer_error_conflict),
                        color=MaterialTheme.colorScheme.error,modifier=Modifier.testTag("investment.cash.reconciliation.unavailable"))
                    TextButton(onClick={onRetry();current?.let{capture(it,false)}},enabled=!saving,modifier=Modifier.testTag("investment.cash.reconciliation.refresh")){Text(stringResource(R.string.planning_installment_retry))}
                }
                error?.let{Text(stringResource(it),color=MaterialTheme.colorScheme.error,modifier=Modifier.testTag("investment.cash.reconciliation.error"))}
            }
        }
    }
}

private fun encodeReconciliationView(view:InvestmentCashReconciliationView)=buildJsonObject {
    put("system",view.system.toPayload());put("linked",view.linked.toPayload());put("locations",buildJsonArray{view.locations.forEach{location->add(buildJsonObject {
        put("wallet",location.wallet.toPayload());put("booked",location.bookedMinor.toString());put("actual",location.actualMinor.toString())
    })}})
}.toString()
private fun decodeReconciliationView(owner:UserId,token:String)=runCatching {
    val p=Json.parseToJsonElement(token).jsonObject
    InvestmentCashReconciliationView(requireNotNull(decodeLinkedWallet(owner,p.getValue("system").toString())),requireNotNull(decodeLinkedWallet(owner,p.getValue("linked").toString())),
        p.getValue("locations").jsonArray.map{element->val location=element.jsonObject
            InvestmentCashReconciliationLocation(requireNotNull(decodeLinkedWallet(owner,location.getValue("wallet").toString())),BigInteger(location.financeRawString("booked")),BigInteger(location.financeRawString("actual")))})
}.getOrNull()
private fun reconciliationErrorResource(error:Throwable)=when((error as? InvestmentCashReconciliationException)?.reason) {
    InvestmentCashReconciliationError.EXCEEDS_BALANCE->R.string.investment_error_insufficient_funds
    InvestmentCashReconciliationError.STALE_RECORD,InvestmentCashReconciliationError.EVENT_CONFLICT->R.string.investment_cash_transfer_error_conflict
    InvestmentCashReconciliationError.INVALID_WALLET->R.string.investment_error_invalid_wallet
    else->R.string.common_error
}
