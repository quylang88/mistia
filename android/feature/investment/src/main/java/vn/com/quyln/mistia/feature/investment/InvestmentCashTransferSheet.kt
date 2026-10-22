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
import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode
import java.time.Instant
import java.util.Currency
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun InvestmentCashTransferSheet(owner:UserId,repository:InvestmentRepository,deviceIdProvider:suspend ()->String,
    eventId:String,direction:InvestmentCashTransferDirection,load:InvestmentWalletReadLoad,walletView:InvestmentLinkedWalletView?,onRetry:()->Unit,onDismiss:()->Unit) {
    val deposit=direction==InvestmentCashTransferDirection.DEPOSIT
    val currentTitle=stringResource(if(deposit)R.string.investment_cash_transfer_deposit_title else R.string.investment_cash_transfer_withdrawal_title)
    val ledgerTitle by rememberSaveable{mutableStateOf(currentTitle)}
    val createdAt by rememberSaveable{mutableStateOf(Instant.now().toString())}
    var occurredAt by rememberSaveable{mutableStateOf(createdAt)}
    var walletId by rememberSaveable{mutableStateOf<String?>(null)}
    var amountText by rememberSaveable{mutableStateOf("")}
    var note by rememberSaveable{mutableStateOf("")}
    var initialized by rememberSaveable{mutableStateOf(false)}
    var systemToken by rememberSaveable{mutableStateOf<String?>(null)}
    var linkedToken by rememberSaveable{mutableStateOf<String?>(null)}
    var selectedToken by rememberSaveable{mutableStateOf<String?>(null)}
    var previewToken by rememberSaveable{mutableStateOf<String?>(null)}
    var saving by remember{mutableStateOf(false)}
    var error by remember{mutableStateOf<Int?>(null)}
    var walletMenu by remember{mutableStateOf(false)}
    val expectedSystem=remember(systemToken){systemToken?.let{decodeLinkedWallet(owner,it)}}
    val expectedLinked=remember(linkedToken){linkedToken?.let{decodeLinkedWallet(owner,it)}}
    val expectedSelected=remember(selectedToken){selectedToken?.let{decodeLinkedWallet(owner,it)}}
    val frozen=remember(previewToken){previewToken?.let(::decodeCashTransferPreview)}
    val code=expectedSystem?.currencyCode ?: walletView?.system?.currencyCode
    val amount=cashTransferMinorInput(amountText,code)
    val snapshot=(load as? InvestmentWalletReadLoad.Loaded)?.snapshot
    val parsed=remember(snapshot,direction,walletId,amount){snapshot?.let{runCatching{readInvestmentCashTransfer(it,direction,walletId,amount ?: 0)}}}
    val quote=parsed?.getOrNull()
    fun capture(view:InvestmentCashTransferReadView) {
        systemToken=view.system.toPayload().toString();linkedToken=view.linked.toPayload().toString();selectedToken=view.selected.toPayload().toString()
        previewToken=encodeCashTransferPreview(view.preview);walletId=view.selected.id;error=null
    }
    LaunchedEffect(quote,initialized) {
        if(!initialized && quote!=null){capture(quote);amountText=cashTransferInput(quote.preview.maximumMinor,quote.system.currencyCode);initialized=true}
    }
    val sourceConsent=expectedSystem!=null && expectedLinked!=null && expectedSelected!=null && walletView!=null &&
        expectedSystem.matchesVisibleInvestmentWallet(walletView.system) && walletView.linkedWallet?.let(expectedLinked::matchesVisibleInvestmentWallet)==true &&
        walletView.eligibleWallets.singleOrNull{it.id==walletId}?.let(expectedSelected::matchesVisibleInvestmentWallet)==true
    val eventCandidate=snapshot?.rows?.any{(it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==eventId) ||
        (it.entity==CloudEntity.INVESTMENT_POSTING.table && it.id==investmentLedgerIdentity(eventId,"cash-transfer-posting"))}==true
    val capacityConsent=quote!=null && frozen?.copy(requestedMinor=quote.preview.requestedMinor)==quote.preview
    val datesReadable=runCatching{Instant.parse(createdAt);Instant.parse(occurredAt)}.isSuccess
    val canSave=initialized && sourceConsent && datesReadable && amount!=null && amount>0 && frozen!=null && amount<=frozen.maximumMinor &&
        (capacityConsent || eventCandidate) && !saving
    val conflict=initialized && load is InvestmentWalletReadLoad.Loaded && (!sourceConsent || (!capacityConsent && !eventCandidate))
    val scope=key(repository){rememberCoroutineScope()}
    fun save() {
        if(!canSave)return
        val request=InvestmentCashTransferRequest(requireNotNull(expectedSystem),requireNotNull(expectedLinked),requireNotNull(expectedSelected),
            InvestmentCashTransferDraft(eventId,direction,requireNotNull(walletId),requireNotNull(amount),note,occurredAt,createdAt),
            requireNotNull(frozen).copy(requestedMinor=amount),ledgerTitle)
        saving=true;error=null
        scope.launch {
            try {
                val result=repository.saveCashTransfer(owner,request,deviceIdProvider(),Instant.now().toString())
                coroutineContext.ensureActive()
                if(result.isSuccess)onDismiss() else error=cashTransferErrorResource(requireNotNull(result.exceptionOrNull()))
            }catch(cancelled:kotlinx.coroutines.CancellationException){throw cancelled}
            catch(failure:Exception){error=cashTransferErrorResource(failure)}
            finally{saving=false}
        }
    }
    val sheet=rememberModalBottomSheetState(skipPartiallyExpanded=true,confirmValueChange={it!=SheetValue.Hidden || !saving})
    ModalBottomSheet(onDismissRequest={if(!saving)onDismiss()},sheetState=sheet) {
        Column(Modifier.fillMaxWidth().testTag("investment.cash.transfer.sheet")) {
            Column(Modifier.fillMaxWidth().padding(horizontal=20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
                Text(currentTitle,Modifier.fillMaxWidth(),style=MaterialTheme.typography.titleLarge)
                Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {
                    TextButton(onClick=onDismiss,enabled=!saving,modifier=Modifier.testTag("investment.cash.transfer.cancel")){Text(stringResource(R.string.common_cancel))}
                    Button(onClick=::save,enabled=canSave,modifier=Modifier.testTag("investment.cash.transfer.save")){Text(stringResource(R.string.common_save))}
                }
            }
            Column(Modifier.fillMaxWidth().weight(1f,fill=false).verticalScroll(rememberScrollState()).padding(horizontal=20.dp).padding(bottom=24.dp)
                .testTag("investment.cash.transfer.body"),verticalArrangement=Arrangement.spacedBy(14.dp)) {
                Text(stringResource(if(deposit)R.string.investment_cash_transfer_from_wallet else R.string.investment_cash_transfer_to_wallet),style=MaterialTheme.typography.labelLarge)
                Box {
                    OutlinedButton(onClick={walletMenu=true},enabled=sourceConsent && !saving && !conflict,
                        modifier=Modifier.fillMaxWidth().testTag("investment.cash.transfer.wallet")) {
                        Text(expectedSelected?.name ?: quote?.selected?.name ?: "—")
                    }
                    DropdownMenu(expanded=walletMenu,onDismissRequest={walletMenu=false}) {
                        walletView?.eligibleWallets.orEmpty().filter{it.currencyCode==code}.forEach{wallet ->DropdownMenuItem(text={Text(wallet.name)},
                            enabled=!saving && sourceConsent && !conflict,onClick={
                                walletMenu=false
                                snapshot?.let{runCatching{readInvestmentCashTransfer(it,direction,wallet.id,amount ?: 0)}.getOrNull()?.let(::capture)}
                            },modifier=Modifier.testTag("investment.cash.transfer.wallet.option."+wallet.id))}
                    }
                }
                Text(stringResource(if(deposit)R.string.investment_cash_transfer_to_wallet else R.string.investment_cash_transfer_from_wallet)+": "+stringResource(R.string.investment_cash_transfer_investment_wallet),style=MaterialTheme.typography.bodyMedium)
                val measurer=rememberTextMeasurer();val inputStyle=MaterialTheme.typography.bodyLarge
                BoxWithConstraints(Modifier.fillMaxWidth()) {
                    val inset=with(androidx.compose.ui.platform.LocalDensity.current){32.dp.toPx()}
                    var size=inputStyle.fontSize.value
                    while(size>12f && measurer.measure(amountText,inputStyle.copy(fontSize=size.sp)).size.width>constraints.maxWidth-inset)size-=0.5f
                    OutlinedTextField(value=amountText,onValueChange={amountText=currencyAmountInput(it,code.orEmpty());error=null},enabled=!saving && initialized,
                        label={Text(stringResource(R.string.investment_cash_transfer_amount))},singleLine=true,textStyle=inputStyle.copy(fontSize=size.sp),
                        keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Decimal),modifier=Modifier.fillMaxWidth().testTag("investment.cash.transfer.amount"))
                }
                TextButton(onClick={frozen?.let{amountText=cashTransferInput(it.maximumMinor,code);error=null}},
                    enabled=!saving && sourceConsent && !conflict && (frozen?.maximumMinor ?: 0)>0,modifier=Modifier.testTag("investment.cash.transfer.maximum")) {
                    Text(stringResource(if(deposit)R.string.investment_cash_transfer_refill_full else R.string.investment_cash_transfer_transfer_all))
                }
                Text(stringResource(R.string.investment_cash_transfer_maximum,""),style=MaterialTheme.typography.bodySmall)
                CashMoneyText(if(frozen!=null && code!=null)formatMinorUnits(frozen.maximumMinor,code) else "—","investment.cash.transfer.limit.amount",MaterialTheme.typography.bodySmall.copy(color=MaterialTheme.colorScheme.onSurfaceVariant))
                if(expectedSelected?.id!=null && expectedSelected.id==expectedLinked?.id)Text(stringResource(if(deposit)R.string.investment_cash_transfer_same_wallet_deposit else R.string.investment_cash_transfer_same_wallet_withdrawal),
                    Modifier.testTag("investment.cash.transfer.sameWallet"),style=MaterialTheme.typography.bodySmall)
                Text(stringResource(R.string.investment_cash_transfer_time),style=MaterialTheme.typography.labelLarge)
                InvestmentCashDateTime(occurredAt,{occurredAt=it;error=null},enabled=!saving)
                OutlinedTextField(value=note,onValueChange={note=it;error=null},enabled=!saving,label={Text(stringResource(R.string.investment_cash_transfer_note))},
                    modifier=Modifier.fillMaxWidth().testTag("investment.cash.transfer.note"))
                if(load==InvestmentWalletReadLoad.Loading)CircularProgressIndicator(Modifier.size(24.dp).testTag("investment.cash.transfer.loading"))
                if(load==InvestmentWalletReadLoad.Failed || parsed?.isFailure==true)Text(stringResource(R.string.common_error),Modifier.testTag("investment.cash.transfer.readError"),color=MaterialTheme.colorScheme.error)
                if(conflict)Text(stringResource(R.string.investment_cash_transfer_error_conflict),Modifier.testTag("investment.cash.transfer.conflict"),color=MaterialTheme.colorScheme.error)
                if(conflict || load==InvestmentWalletReadLoad.Failed || parsed?.isFailure==true)TextButton(onClick={
                    if(!eventCandidate && quote!=null && quote.system.currencyCode==code)capture(quote)
                    onRetry()
                },enabled=!saving,modifier=Modifier.testTag("investment.cash.transfer.retryRead")){Text(stringResource(R.string.planning_installment_retry))}
                error?.let{Text(stringResource(it),Modifier.testTag("investment.cash.transfer.error"),color=MaterialTheme.colorScheme.error)
                    TextButton(onClick=::save,enabled=canSave,modifier=Modifier.testTag("investment.cash.transfer.retrySave")){Text(stringResource(R.string.planning_installment_retry))}}
                if(saving)CircularProgressIndicator(Modifier.size(24.dp).testTag("investment.cash.transfer.saving"))
            }
        }
    }
}

private fun cashTransferMinorInput(text:String,code:String?):Long? {
    val digits=code?.let{runCatching{Currency.getInstance(it).defaultFractionDigits}.getOrNull()}?.takeIf{it>=0} ?: return null
    return runCatching{BigDecimal(if(code in setOf("JPY","VND"))text.trim().replace(",","") else text.trim())
        .movePointRight(digits).setScale(0,RoundingMode.UNNECESSARY).longValueExact()}.getOrNull()
}
private fun cashTransferInput(minor:Long,code:String?):String {
    val digits=code?.let{runCatching{Currency.getInstance(it).defaultFractionDigits}.getOrNull()}?.takeIf{it>=0} ?: return ""
    return currencyAmountInput(BigDecimal.valueOf(minor,digits).stripTrailingZeros().toPlainString(),code)
}
private fun encodeCashTransferPreview(value:InvestmentCashTransferPreview)=buildJsonObject {
    put("direction",value.direction.name);put("requested",value.requestedMinor);put("maximum",value.maximumMinor)
    put("profit",value.realizedProfitMinor.toString());put("available",value.availableInvestmentMinor.toString());put("booked",value.linkedBookedMinor.toString());put("ordinary",value.sourceOrdinaryMinor.toString())
}.toString()
private fun decodeCashTransferPreview(token:String):InvestmentCashTransferPreview?=runCatching {
    val p=Json.parseToJsonElement(token).jsonObject
    fun n(key:String)=BigInteger(requireNotNull(p.financeRawString(key)))
    InvestmentCashTransferPreview(InvestmentCashTransferDirection.valueOf(requireNotNull(p.financeRawString("direction"))),requireNotNull(p.financeRawLong("requested")),
        requireNotNull(p.financeRawLong("maximum")),n("profit"),n("available"),n("booked"),n("ordinary"))
}.getOrNull()
private fun cashTransferErrorResource(error:Throwable)=when((error as? InvestmentCashTransferException)?.reason) {
    InvestmentCashTransferError.STALE_RECORD,InvestmentCashTransferError.EVENT_CONFLICT->R.string.investment_cash_transfer_error_conflict
    InvestmentCashTransferError.EXCEEDS_LIMIT->R.string.investment_cash_transfer_error_exceeds_limit
    else->R.string.common_error
}
