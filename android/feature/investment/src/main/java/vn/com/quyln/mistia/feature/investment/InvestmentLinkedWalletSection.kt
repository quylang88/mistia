package vn.com.quyln.mistia.feature.investment

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.designsystem.CategoryIcon
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun InvestmentLinkedWalletSection(owner:UserId,repository:InvestmentRepository,deviceIdProvider:suspend ()->String,load:InvestmentWalletReadLoad,financial:InvestmentCashFinancialView?,onRetry:()->Unit) {
    val snapshot=(load as? InvestmentWalletReadLoad.Loaded)?.snapshot
    val parsed=remember(snapshot){snapshot?.let{runCatching{investmentLinkedWalletView(it.walletSnapshot())}}}
    val view=parsed?.getOrNull()
    var picker by rememberSaveable{mutableStateOf(false)}
    var choices by rememberSaveable{mutableStateOf(false)}
    var systemToken by rememberSaveable{mutableStateOf<String?>(null)}
    var targetToken by rememberSaveable{mutableStateOf<String?>(null)}
    var booked by rememberSaveable{mutableStateOf<Long?>(null)}
    var eventId by rememberSaveable{mutableStateOf<String?>(null)}
    var busy by remember{mutableStateOf(false)}
    var error by remember{mutableStateOf<Int?>(null)}
    val expectedSystem=remember(systemToken){systemToken?.let{decodeLinkedWallet(owner,it)}}
    val expectedTarget=remember(targetToken){targetToken?.let{decodeLinkedWallet(owner,it)}}
    val baseConsent=view!=null && expectedSystem!=null && expectedSystem.matchesVisibleInvestmentWallet(view.system)
    val targetConsent=expectedTarget!=null && view?.eligibleWallets?.singleOrNull{it.id==expectedTarget.id}?.let(expectedTarget::matchesVisibleInvestmentWallet)==true
    val canDefault=baseConsent && targetConsent && !busy
    val canMove=canDefault && booked!=null && view?.bookedMinor==booked
    val scope=rememberCoroutineScope()
    val ledgerTitle=stringResource(R.string.investment_wallet_change_and_transfer_all)
    fun apply(move:Boolean,target:LedgerWalletRecord?=expectedTarget) {
        if(busy || !baseConsent || target==null || eventId==null || (move && (booked==null || view?.bookedMinor!=booked)))return
        if(view?.eligibleWallets?.singleOrNull{it.id==target.id}?.let(target::matchesVisibleInvestmentWallet)!=true)return
        val request=InvestmentWalletLinkRequest(requireNotNull(expectedSystem),target,requireNotNull(eventId),move,booked ?: 0L,ledgerTitle)
        busy=true;error=null
        scope.launch {
            try {
                val result=repository.changeLinkedWallet(owner,request,deviceIdProvider(),Instant.now().toString())
                coroutineContext.ensureActive()
                if(result.isSuccess){picker=false;choices=false;targetToken=null;systemToken=null;eventId=null}
                else error=linkedWalletErrorResource(requireNotNull(result.exceptionOrNull()))
            }catch(cancelled:kotlinx.coroutines.CancellationException){throw cancelled}
            catch(failure:Exception){error=linkedWalletErrorResource(failure)}
            finally{busy=false}
        }
    }
    @Composable fun ReadStatus() {
        if(load==InvestmentWalletReadLoad.Loading)CircularProgressIndicator(Modifier.size(24.dp).testTag("investment.wallet.link.loading"))
        if(view==null && load!=InvestmentWalletReadLoad.Loading)Text(stringResource(R.string.common_error),Modifier.testTag("investment.wallet.link.unavailable"),color=MaterialTheme.colorScheme.error)
        if(load==InvestmentWalletReadLoad.Failed || parsed?.isFailure==true)
            TextButton(onClick=onRetry,enabled=!busy,modifier=Modifier.testTag("investment.wallet.link.retry")){Text(stringResource(R.string.planning_installment_retry))}
    }
    Surface(shape=RoundedCornerShape(22.dp),color=MaterialTheme.colorScheme.surfaceContainerLow,modifier=Modifier.fillMaxWidth().testTag("investment.wallet.link.card")) {
        Column(Modifier.fillMaxWidth().padding(18.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.investment_wallet_linked_wallet),Modifier.weight(1f),fontSize=17.sp,fontWeight=FontWeight.SemiBold)
                TextButton(onClick={
                    systemToken=view?.system?.toPayload()?.toString();booked=view?.bookedMinor;eventId=UUID.randomUUID().toString()
                    targetToken=null;error=null;picker=true
                },enabled=view!=null && !busy,modifier=Modifier.testTag("investment.wallet.link.choose")){
                    Text(stringResource(if(view?.system?.investmentLinkedWalletId==null)R.string.investment_wallet_choose else R.string.investment_wallet_change))
                }
            }
            val linked=financial?.linkedWallet ?: view?.linkedWallet
            if(linked!=null)Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                CategoryIcon(linked.iconSymbolName,TransactionCategoryKind.INCOME,linked.iconColorHex,Modifier.size(38.dp))
                Text(linked.name,Modifier.weight(1f).testTag("investment.wallet.linked.name"),style=MaterialTheme.typography.titleSmall)
            } else if(view!=null) {
                Text(stringResource(R.string.investment_wallet_not_set),style=MaterialTheme.typography.titleSmall)
                Text(stringResource(R.string.investment_wallet_not_set_message),style=MaterialTheme.typography.bodySmall)
            }
            if(linked!=null) {
                val actual=financial?.linkedActualMinor?.let{formatMinorUnits(it,linked.currencyCode)}
                Text(actual?.let{stringResource(R.string.investment_wallet_actual_balance,it)} ?: "—",Modifier.testTag("investment.wallet.link.actual"),style=MaterialTheme.typography.bodySmall)
                val portion=financial?.linkedBalances?.investmentMinor?.let{formatMinorUnits(it,linked.currencyCode)}
                Text(portion?.let{stringResource(R.string.investment_wallet_investment_portion,it)} ?: "—",Modifier.testTag("investment.wallet.link.portion"),style=MaterialTheme.typography.bodySmall,color=androidx.compose.ui.graphics.Color(0.65f,0.45f,0.98f))
            }
            ReadStatus()
        }
    }
    val sheet=rememberModalBottomSheetState(skipPartiallyExpanded=true,confirmValueChange={it!=SheetValue.Hidden || !busy})
    if(picker)ModalBottomSheet(onDismissRequest={if(!busy){picker=false;targetToken=null}},sheetState=sheet) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal=20.dp).padding(bottom=24.dp)
            .testTag("investment.wallet.link.picker"),verticalArrangement=Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.investment_wallet_choose_linked_wallet),Modifier.fillMaxWidth(),style=MaterialTheme.typography.titleLarge)
            TextButton(onClick={picker=false;targetToken=null},enabled=!busy,modifier=Modifier.testTag("investment.wallet.link.picker.cancel")){Text(stringResource(R.string.common_cancel))}
            ReadStatus()
            if(view!=null && !baseConsent)Text(stringResource(R.string.investment_cash_transfer_error_conflict),Modifier.testTag("investment.wallet.link.conflict"),color=MaterialTheme.colorScheme.error)
            view?.eligibleWallets.orEmpty().forEach { target ->
                OutlinedButton(onClick={
                    targetToken=target.toPayload().toString();error=null
                    if(expectedSystem?.investmentLinkedWalletId==null || expectedSystem.investmentLinkedWalletId==target.id)apply(false,target)
                    else{picker=false;choices=true}
                },enabled=baseConsent && !busy,modifier=Modifier.fillMaxWidth().testTag("investment.wallet.link.option."+target.id)) {
                    Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                        CategoryIcon(target.iconSymbolName,TransactionCategoryKind.INCOME,target.iconColorHex,Modifier.size(30.dp))
                        Column(Modifier.weight(1f)) {Text(target.name);Text(target.currencyCode,style=MaterialTheme.typography.bodySmall)}
                    }
                }
            }
            error?.let{Text(stringResource(it),Modifier.testTag("investment.wallet.link.error"),color=MaterialTheme.colorScheme.error)}
            if(error!=null && targetToken!=null)TextButton(onClick={apply(false)},enabled=canDefault,modifier=Modifier.testTag("investment.wallet.link.retrySave")){Text(stringResource(R.string.planning_installment_retry))}
            if(busy)CircularProgressIndicator(Modifier.size(24.dp).testTag("investment.wallet.link.saving"))
        }
    }
    if(choices)AlertDialog(onDismissRequest={if(!busy){choices=false;targetToken=null}},
        title={Text(stringResource(R.string.investment_wallet_change_choice_title))},
        text={Column(Modifier.verticalScroll(rememberScrollState()).testTag("investment.wallet.link.confirmation"),verticalArrangement=Arrangement.spacedBy(12.dp)) {
            Text(expectedTarget?.name.orEmpty(),Modifier.testTag("investment.wallet.link.target"),fontWeight=FontWeight.SemiBold)
            Text(stringResource(R.string.investment_wallet_change_choice_message))
            Text(booked?.let{formatMinorUnits(it,expectedSystem?.currencyCode ?: "VND")} ?: "—",Modifier.testTag("investment.wallet.link.amount"))
            ReadStatus()
            if(view!=null && (!baseConsent || !targetConsent || (booked!=null && view.bookedMinor!=booked)))
                Text(stringResource(R.string.investment_cash_transfer_error_conflict),Modifier.testTag("investment.wallet.link.conflict"),color=MaterialTheme.colorScheme.error)
            error?.let{Text(stringResource(it),Modifier.testTag("investment.wallet.link.error"),color=MaterialTheme.colorScheme.error)}
            if(busy)CircularProgressIndicator(Modifier.size(24.dp).testTag("investment.wallet.link.saving"))
        }},
        confirmButton={Column(Modifier.fillMaxWidth()) {
            TextButton(onClick={apply(false)},enabled=canDefault,modifier=Modifier.fillMaxWidth().testTag("investment.wallet.link.onlyDefault")){Text(stringResource(R.string.investment_wallet_only_change_default))}
            TextButton(onClick={apply(true)},enabled=canMove,modifier=Modifier.fillMaxWidth().testTag("investment.wallet.link.moveAll")){Text(stringResource(R.string.investment_wallet_change_and_transfer_all))}
            TextButton(onClick={choices=false;targetToken=null},enabled=!busy,modifier=Modifier.fillMaxWidth().testTag("investment.wallet.link.cancel")){Text(stringResource(R.string.common_cancel))}
        }})
}

private fun decodeLinkedWallet(owner:UserId,token:String):LedgerWalletRecord?=runCatching {
    val p=Json.parseToJsonElement(token).jsonObject
    val raw=CloudRecord(CloudEntity.LEDGER_WALLET.table,requireNotNull(p.financeRawString("id")),owner.value,p,
        p.financeRawString("updated_at"),p.financeRawString("deleted_at"),requireNotNull(p.financeRawLong("sync_version")))
    require(raw.financeRawIdentity(owner,CloudEntity.LEDGER_WALLET,true))
    investmentLinkedWalletRecord(raw)
}.getOrNull()
private fun linkedWalletErrorResource(error:Throwable):Int=when((error as? InvestmentWalletLinkException)?.reason) {
    InvestmentWalletLinkError.STALE_RECORD,InvestmentWalletLinkError.EVENT_CONFLICT->R.string.investment_cash_transfer_error_conflict
    else->R.string.common_error
}
