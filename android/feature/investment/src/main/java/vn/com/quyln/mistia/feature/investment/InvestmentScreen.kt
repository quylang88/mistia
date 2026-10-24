package vn.com.quyln.mistia.feature.investment

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.designsystem.*
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@Composable
fun InvestmentScreen(ownerUserId:UserId,repository:InvestmentRepository,onBack:()->Unit,modifier:Modifier=Modifier,
    primaryCurrencyCode:String="JPY",deviceIdProvider:suspend ()->String={throw UnsupportedOperationException("Device identity unavailable")},enabledCurrencyCodes:List<String> = listOf(primaryCurrencyCode),exchangeRates:List<ExchangeRateSnapshot> = emptyList()) {
    key(ownerUserId.value){OwnedInvestmentScreen(ownerUserId,repository,onBack,modifier,primaryCurrencyCode,deviceIdProvider,enabledCurrencyCodes,exchangeRates)}
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun OwnedInvestmentScreen(owner:UserId,repository:InvestmentRepository,onBack:()->Unit,modifier:Modifier,
    primaryCurrency:String,deviceIdProvider:suspend ()->String,enabledCurrencies:List<String>,exchangeRates:List<ExchangeRateSnapshot>) {
    val listState=rememberLazyListState()
    var retry by remember{mutableIntStateOf(0)}
    val load by investmentChannelReadLoad(owner,repository,retry)
    val snapshot=(load as? InvestmentChannelReadLoad.Loaded)?.snapshot
    val parsed=remember(snapshot){snapshot?.let{runCatching{
        it.records(CloudEntity.INVESTMENT_CHANNEL).filter{row ->row.financeRawDeleted()!=true}.map(InvestmentChannelRecord::fromCloudRecord)
            .sortedWith(compareBy(InvestmentChannelRecord::sortOrder).thenBy{channel ->Instant.parse(channel.createdAt)}.thenBy(InvestmentChannelRecord::id))
    }}}
    val channels=parsed?.getOrNull()
    val readable=snapshot!=null && channels!=null
    var cashRetry by remember{mutableIntStateOf(0)}
    val cashLoad by investmentWalletReadLoad(owner,repository,cashRetry)
    val cashSnapshot=(cashLoad as? InvestmentWalletReadLoad.Loaded)?.snapshot
    val cashView=remember(cashSnapshot,primaryCurrency){cashSnapshot?.let{runCatching{investmentCashFinancialView(it,primaryCurrency)}.getOrNull()}}
    val walletParsed=remember(cashSnapshot){cashSnapshot?.let{runCatching{investmentLinkedWalletView(it.walletSnapshot())}}}
    val walletView=walletParsed?.getOrNull()
    val reconciliationView=remember(cashSnapshot){cashSnapshot?.let{runCatching{readInvestmentCashReconciliation(it)}.getOrNull()}}
    var reconciliationTarget by rememberSaveable{mutableStateOf<String?>(null)}
    val historyParsed=remember(cashSnapshot,cashView?.currencyCode){cashSnapshot?.let{runCatching{investmentCashHistory(it,requireNotNull(cashView?.currencyCode))}}}
    val walletNames=remember(cashSnapshot){cashSnapshot?.rows.orEmpty().filter{it.entity==CloudEntity.LEDGER_WALLET.table && it.financeRawDeleted(true)==false}.mapNotNull{row ->row.payload.financeRawString("name")?.let{row.id to it}}.toMap()}
    var historyOpen by rememberSaveable{mutableStateOf(false)}
    var cashEditing by rememberSaveable{mutableStateOf(false)}
    var cashDirection by rememberSaveable{mutableStateOf<String?>(null)}
    var cashEvent by rememberSaveable{mutableStateOf<String?>(null)}
    var pendingCashDirection by rememberSaveable{mutableStateOf<String?>(null)}
    var pendingCashReady by rememberSaveable{mutableStateOf(false)}
    var pickRequest by rememberSaveable{mutableIntStateOf(0)}
    var cashActionError by remember{mutableStateOf<Int?>(null)}
    val linkedBooked=cashView?.allocation?.locations?.singleOrNull{it.walletId==walletView?.linkedWallet?.id}?.bookedMinor
    val linkedUsable=walletView?.linkedWallet?.let{linked ->walletView.eligibleWallets.any{it.id==linked.id}} ?: true
    val cashActionsReady=walletView!=null && linkedUsable && cashView?.allocation!=null && cashView.realizedProfitMinor!=null && cashDirection==null && pendingCashDirection==null
    fun openCash(direction:InvestmentCashTransferDirection) {
        cashActionError=null;cashEditing=false;cashEvent=UUID.randomUUID().toString()
        if(walletView?.linkedWallet==null){pendingCashDirection=direction.name;pendingCashReady=false;pickRequest++}
        else cashDirection=direction.name
    }
    LaunchedEffect(pendingCashReady,walletView?.linkedWallet?.id,linkedBooked) {
        if(pendingCashReady && pendingCashDirection!=null && walletView?.linkedWallet!=null && linkedUsable) {
            if(pendingCashDirection==InvestmentCashTransferDirection.WITHDRAWAL.name && (linkedBooked==null || linkedBooked.signum()<=0)) {
                cashActionError=R.string.investment_cash_transfer_move_to_linked_first;cashEvent=null
            } else cashDirection=pendingCashDirection
            pendingCashDirection=null;pendingCashReady=false
        }
    }
    val scope=key(repository){rememberCoroutineScope()}
    var editorId by rememberSaveable{mutableStateOf<String?>(null)}
    var expectedToken by rememberSaveable{mutableStateOf<String?>(null)}
    var name by rememberSaveable{mutableStateOf("")}
    var saving by remember{mutableStateOf(false)}
    var editorError by remember{mutableStateOf<Int?>(null)}
    var actionError by remember{mutableStateOf<Int?>(null)}
    var archiveToken by rememberSaveable{mutableStateOf<String?>(null)}
    var actionRunning by remember{mutableStateOf(false)}
    var tradeDetailId by rememberSaveable{mutableStateOf<String?>(null)}
    var saleId by rememberSaveable{mutableStateOf<String?>(null)}
    var saleAssetId by rememberSaveable{mutableStateOf<String?>(null)}
    fun openSale(asset:String?){saleAssetId=asset;saleId=UUID.randomUUID().toString()}
    var purchaseId by rememberSaveable{mutableStateOf<String?>(null)}
    var purchaseAssetId by rememberSaveable{mutableStateOf<String?>(null)}
    fun openPurchase(asset:String?){purchaseAssetId=asset;purchaseId=UUID.randomUUID().toString()}
    var assetEditorId by rememberSaveable{mutableStateOf<String?>(null)}
    var assetExpectedToken by rememberSaveable{mutableStateOf<String?>(null)}
    var assetArchiveToken by rememberSaveable{mutableStateOf<String?>(null)}
    var assetActionError by remember{mutableStateOf<Int?>(null)}
    val assetParsed=remember(snapshot){snapshot?.let{runCatching{
        it.records(CloudEntity.INVESTMENT_ASSET).filter{raw ->raw.financeRawDeleted()!=true}.map(InvestmentAssetRecord::fromCloudRecord)
            .sortedWith(compareBy(InvestmentAssetRecord::sortOrder).thenBy{asset ->Instant.parse(asset.createdAt)}.thenBy(InvestmentAssetRecord::id))
    }}}
    val assets=assetParsed?.getOrNull()
    val assetReadable=readable && assets!=null
    val assetPositions=remember(snapshot,assets){assets.orEmpty().associate{asset->asset.id to runCatching{investmentTradePositions(snapshot?.records(CloudEntity.INVESTMENT_TRADE).orEmpty(),asset)}.getOrNull()}}
    val sellable=assetPositions.filterValues{it?.any{position->position.quantity.signum()>0}==true}.keys

    fun editAsset(asset:InvestmentAssetRecord?){
        assetExpectedToken=asset?.toCloudRecord()?.payload?.toString();assetEditorId=asset?.id ?: UUID.randomUUID().toString()
    }
    fun changeAssetArchive(asset:InvestmentAssetRecord,archive:Boolean){
        if(actionRunning || !assetReadable)return
        actionRunning=true;assetActionError=null
        scope.launch{
            try{
                val device=deviceIdProvider();val now=Instant.now().toString()
                val result=if(archive)repository.archiveAsset(owner,asset,device,now) else repository.restoreAsset(owner,asset,device,now)
                coroutineContext.ensureActive()
                result.exceptionOrNull()?.let{assetActionError=investmentAssetErrorResource(it)}
            }catch(cancelled:kotlinx.coroutines.CancellationException){throw cancelled}
            catch(error:Exception){assetActionError=investmentAssetErrorResource(error)}
            finally{actionRunning=false}
        }
    }
    val expected=remember(expectedToken){expectedToken?.let{decodeChannel(owner,it)}}
    val current=channels?.singleOrNull{it.id==editorId}
    val consent=expectedToken==null || (expected!=null && current!=null && expected.matchesVisibleInvestmentChannel(current))
    fun edit(channel:InvestmentChannelRecord?){
        expectedToken=channel?.toCloudRecord()?.payload?.toString();editorId=channel?.id ?: UUID.randomUUID().toString();name=channel?.name.orEmpty();editorError=null
    }
    fun changeArchive(target:InvestmentChannelRecord,archive:Boolean){
        if(actionRunning || !readable)return
        actionRunning=true;actionError=null
        scope.launch{
            try{
                val device=deviceIdProvider();val now=Instant.now().toString()
                val result=if(archive)repository.archiveChannel(owner,target,device,now) else repository.restoreChannel(owner,target,device,now)
                coroutineContext.ensureActive()
                result.exceptionOrNull()?.let{actionError=channelErrorResource(it)}
            }catch(cancelled:kotlinx.coroutines.CancellationException){throw cancelled}catch(error:Exception){actionError=channelErrorResource(error)}
            finally{actionRunning=false}
        }
    }
    fun editCash(item:InvestmentCashHistoryItem) {
        if(!item.isEditable)item.tradeId?.let{tradeDetailId=it;return}
        if(cashDirection!=null || cashSnapshot==null)return
        val event=item.ledgerTransactionId?.let{id ->runCatching{readInvestmentCashTransferLifecycle(cashSnapshot,id).event}.getOrNull()}
        if(event==null)cashActionError=R.string.common_error
        else {cashEditing=true;cashDirection=event.draft.direction.name;cashEvent=event.draft.id}
    }
    val trades=remember(snapshot){snapshot?.records(CloudEntity.INVESTMENT_TRADE).orEmpty().filter{it.financeRawDeleted()==false}
        .sortedWith(compareByDescending<CloudRecord>{runCatching{Instant.parse(it.payload.financeRawString("occurred_at"))}.getOrDefault(Instant.MIN)}
            .thenByDescending{runCatching{Instant.parse(it.payload.financeRawString("created_at"))}.getOrDefault(Instant.MIN)}.thenByDescending{it.id})}
    androidx.activity.compose.BackHandler(enabled=historyOpen && cashDirection==null && tradeDetailId==null){historyOpen=false}
    if(historyOpen)InvestmentCashHistoryScreen(cashLoad,historyParsed,walletNames,assets.orEmpty().associate{it.id to it.name},
        onBack={historyOpen=false},onOpen=::editCash,onRetry={cashRetry++},modifier=modifier)
    else LazyColumn(modifier.fillMaxSize().testTag("investment.list"),state=listState,contentPadding=PaddingValues(16.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
        item{
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){
                IconButton(onClick=onBack){Icon(Icons.AutoMirrored.Filled.ArrowBack,stringResource(R.string.common_close))}
                Text(stringResource(R.string.investment_title),style=MaterialTheme.typography.headlineMedium)
            }
        }
        item(key="investment.cash.summary"){InvestmentCashSummary(cashLoad,cashView,onRetry={cashRetry++})}
        item(key="investment.cash.actions") {
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                Button(onClick={openCash(InvestmentCashTransferDirection.DEPOSIT)},enabled=cashActionsReady && (cashView?.shortfallMinor?.signum() ?: 0)>0,
                    modifier=Modifier.weight(1f).testTag("investment.cash.deposit")){Text(stringResource(R.string.investment_wallet_refill_action))}
                OutlinedButton(onClick={openCash(InvestmentCashTransferDirection.WITHDRAWAL)},enabled=cashActionsReady && (walletView?.linkedWallet==null || (linkedBooked?.signum() ?: 0)>0),
                    modifier=Modifier.weight(1f).testTag("investment.cash.withdraw")){Text(stringResource(R.string.investment_wallet_transfer_out_action))}
            }
        }
        item(key="investment.wallet.link"){InvestmentLinkedWalletSection(owner,repository,deviceIdProvider,cashLoad,cashView,walletParsed,pickRequest,
            onPickerSaved={pickRequest=0;if(pendingCashDirection!=null)pendingCashReady=true},
            onPickerCancelled={pickRequest=0;if(pendingCashDirection!=null){pendingCashDirection=null;pendingCashReady=false;cashEvent=null}},onRetry={cashRetry++})}
        item(key="investment.cash.reconcile.all") {
            OutlinedButton(onClick={reconciliationTarget="all"},enabled=reconciliationView?.locations?.let{locations->locations.isNotEmpty() && locations.all{it.bookedMinor<=java.math.BigInteger.valueOf(Long.MAX_VALUE) && it.actualMinor>=it.bookedMinor}}==true,
                modifier=Modifier.fillMaxWidth().heightIn(min=48.dp).testTag("investment.cash.reconcile.all")){Text(stringResource(R.string.investment_wallet_reconcile_all))}
        }
        item(key="investment.cash.locations"){InvestmentCashLocations(cashLoad,cashSnapshot,cashView,onRetry={cashRetry++},
            reconcilableIds=reconciliationView?.locations.orEmpty().map{it.wallet.id}.toSet(),onReconcile={reconciliationTarget=it})}
        item(key="investment.cash.history"){InvestmentCashHistoryPreview(cashLoad,historyParsed,walletNames,assets.orEmpty().associate{it.id to it.name},
            onAll={historyOpen=true},onOpen=::editCash,onRetry={cashRetry++})}
        item{Button(onClick={edit(null)},enabled=readable && !actionRunning,modifier=Modifier.testTag("investment.channels.add")){Text(stringResource(R.string.investment_hub_add_channel))}}
        item{Button(onClick={editAsset(null)},enabled=assetReadable && !actionRunning && channels.orEmpty().any{!it.isArchived},
            modifier=Modifier.testTag("investment.assets.add")){Text(stringResource(R.string.investment_hub_add_asset))}}
        item{Button(onClick={openPurchase(null)},enabled=assetReadable && assets.orEmpty().any{!it.isArchived && it.defaultUnitLabel!=null},modifier=Modifier.testTag("investment.purchase.add")){Text(stringResource(R.string.investment_hub_buy))}}
        item{OutlinedButton(onClick={openSale(null)},enabled=assetReadable && assets.orEmpty().any{!it.isArchived && it.defaultUnitLabel!=null && it.id in sellable},modifier=Modifier.testTag("investment.sale.add")){Text(stringResource(R.string.investment_hub_sell))}}
        if(load==InvestmentChannelReadLoad.Loading)item{CircularProgressIndicator(Modifier.size(24.dp).testTag("investment.channels.loading"))}
        if(load==InvestmentChannelReadLoad.Failed || parsed?.isFailure==true)item{
            Text(stringResource(R.string.common_error),Modifier.testTag("investment.channels.unavailable"),color=MaterialTheme.colorScheme.error)
            TextButton(onClick={retry++},modifier=Modifier.testTag("investment.channels.retry")){Text(stringResource(R.string.planning_installment_retry))}
        }
        if(channels!=null && channels.none{!it.isArchived})item{
            MistiaGlassCard{padding ->Column(Modifier.padding(padding)){
                Text(stringResource(R.string.investment_hub_empty_title),style=MaterialTheme.typography.titleMedium)
                Text(stringResource(R.string.investment_hub_empty_message),style=MaterialTheme.typography.bodyMedium)
            }}
        }
        items(channels.orEmpty().filterNot{it.isArchived},key={"channel-${it.id}"}){channel ->
            InvestmentChannelRow(channel,!actionRunning,onEdit={edit(channel)},onArchive={archiveToken=channel.toCloudRecord().payload.toString()},onRestore={})
        }
        if(channels.orEmpty().any{it.isArchived})item{Text(stringResource(R.string.management_data_action_archived_items_title),style=MaterialTheme.typography.titleMedium)}
        items(channels.orEmpty().filter{it.isArchived},key={"archived-${it.id}"}){channel ->
            InvestmentChannelRow(channel,!actionRunning,onEdit={edit(channel)},onArchive={},onRestore={changeArchive(channel,false)})
        }
        if(assetParsed?.isFailure==true)item{
            Text(stringResource(R.string.common_error),Modifier.testTag("investment.assets.unavailable"),color=MaterialTheme.colorScheme.error)
            TextButton(onClick={retry++}){Text(stringResource(R.string.planning_installment_retry))}
        }
        if(assets.orEmpty().isNotEmpty())item{Text(stringResource(R.string.investment_hub_assets_tab),style=MaterialTheme.typography.titleLarge)}
        items(assets.orEmpty(),key={asset ->"asset-"+asset.id}){asset ->
            MistiaGlassCard{padding ->Column(Modifier.fillMaxWidth().padding(padding),verticalArrangement=Arrangement.spacedBy(8.dp)){
                Text(asset.name,style=MaterialTheme.typography.titleMedium)
                Text(listOfNotNull(asset.defaultUnitLabel,asset.currencyCode).joinToString(" · "),style=MaterialTheme.typography.bodyMedium)
                val stock=assetPositions[asset.id]?.joinToString(" · "){it.quantity.toPlainString()+" "+it.unitLabel.orEmpty()}
                Text(stock ?: "—",Modifier.testTag("investment.asset.stock."+asset.id))
                Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){
                    if(!asset.isArchived)TextButton(onClick={openPurchase(asset.id)},enabled=asset.defaultUnitLabel!=null && !actionRunning,modifier=Modifier.testTag("investment.asset.buy."+asset.id)){Text(stringResource(R.string.investment_hub_buy))}
                    if(!asset.isArchived)TextButton(onClick={openSale(asset.id)},enabled=asset.id in sellable && asset.defaultUnitLabel!=null && !actionRunning,modifier=Modifier.testTag("investment.asset.sell."+asset.id)){Text(stringResource(R.string.investment_hub_sell))}
                    TextButton(onClick={editAsset(asset)},enabled=!actionRunning,modifier=Modifier.testTag("investment.asset.edit."+asset.id)){
                        Text(stringResource(R.string.management_management_edit))
                    }
                    if(asset.isArchived)TextButton(onClick={changeAssetArchive(asset,false)},enabled=!actionRunning,
                        modifier=Modifier.testTag("investment.asset.restore."+asset.id)){Text(stringResource(R.string.management_managementarchiveditems_restore))}
                    else TextButton(onClick={assetArchiveToken=asset.toCloudRecord().payload.toString()},enabled=!actionRunning,
                        modifier=Modifier.testTag("investment.asset.archive."+asset.id)){Text(stringResource(R.string.common_archive))}
                }
            }}
        }
        if(trades.isNotEmpty())item{Text(stringResource(R.string.investment_hub_activity),style=MaterialTheme.typography.titleLarge)}
        items(trades,key={"trade-${it.id}"}){trade ->
            val currency=trade.payload.financeRawString("currency_code")?.financeReportingCode()
            val amount=trade.payload.financeRawLong("gross_amount_minor")
            MistiaGlassCard{padding ->MistiaRecordRow(stringResource(if(trade.string("kind_raw_value")=="buy")R.string.investment_hub_buy else R.string.investment_hub_sell),
                subtitle=trade.string("occurred_at"),trailing=if(currency==null || amount==null) "—" else formatMinorUnits(amount,currency),modifier=Modifier.padding(padding).clickable{tradeDetailId=trade.id}.testTag("investment.trade."+trade.id))}
        }
        item{Spacer(Modifier.height(32.dp))}
    }
    tradeDetailId?.let{id->InvestmentTradeDetailSheet(owner,repository,id,deviceIdProvider,onDismiss={tradeDetailId=null},rates=exchangeRates,onSetupLinked={scope.launch{listState.scrollToItem(3);pickRequest++}})}
    saleId?.let{id->key(owner.value,id){InvestmentSaleSheet(owner,repository,id,saleAssetId,exchangeRates,deviceIdProvider,{saleId=null;saleAssetId=null},onSetupLinked={scope.launch{
        // This fixed section precedes every variable channel/asset/activity row.
        listState.scrollToItem(3);pickRequest++
    }})}}
    purchaseId?.let{id->key(owner.value,id){InvestmentPurchaseSheet(owner,repository,id,purchaseAssetId,exchangeRates,deviceIdProvider,{purchaseId=null;purchaseAssetId=null})}}
    assetActionError?.let{resource ->AlertDialog(onDismissRequest={assetActionError=null},title={Text(stringResource(R.string.common_error))},
        text={Text(stringResource(resource),Modifier.testTag("investment.assets.error"))},
        confirmButton={TextButton(onClick={assetActionError=null}){Text(stringResource(R.string.common_ok))}})}
    val assetArchive=remember(assetArchiveToken){assetArchiveToken?.let{decodeInvestmentAsset(owner,it)}}
    if(assetArchiveToken!=null)AlertDialog(onDismissRequest={assetArchiveToken=null},
        title={Text(stringResource(if(assetArchive==null)R.string.common_error else R.string.common_archive))},
        text={Text(assetArchive?.name ?: stringResource(R.string.common_error))},
        confirmButton={TextButton(onClick={assetArchiveToken=null;if(assetArchive!=null)changeAssetArchive(assetArchive,true)},
            enabled=assetArchive!=null && !actionRunning,modifier=Modifier.testTag("investment.asset.confirmArchive")){Text(stringResource(R.string.common_archive))}},
        dismissButton={TextButton(onClick={assetArchiveToken=null}){Text(stringResource(R.string.common_cancel))}})
    assetEditorId?.let{id ->key(id,assetExpectedToken){
        InvestmentAssetEditorSheet(owner,repository,id,assetExpectedToken,primaryCurrency,enabledCurrencies,deviceIdProvider,onDismiss={assetEditorId=null})
    }}
    actionError?.let{resource ->AlertDialog(onDismissRequest={actionError=null},title={Text(stringResource(R.string.common_error))},
        text={Text(stringResource(resource),Modifier.testTag("investment.channels.error"))},
        confirmButton={TextButton(onClick={actionError=null},modifier=Modifier.testTag("investment.channel.error.dismiss")){Text(stringResource(R.string.common_ok))}})}
    val archive=remember(archiveToken){archiveToken?.let{decodeChannel(owner,it)}}
    if(archive!=null)AlertDialog(onDismissRequest={archiveToken=null},title={Text(stringResource(R.string.common_archive))},text={Text(archive.name)},
        confirmButton={TextButton(onClick={archiveToken=null;changeArchive(archive,true)},enabled=!actionRunning,modifier=Modifier.testTag("investment.channel.confirmArchive")){Text(stringResource(R.string.common_archive))}},
        dismissButton={TextButton(onClick={archiveToken=null}){Text(stringResource(R.string.common_cancel))}})
    if(cashDirection!=null && cashEvent!=null)key(cashEvent) {
        InvestmentCashTransferSheet(owner,repository,deviceIdProvider,requireNotNull(cashEvent),InvestmentCashTransferDirection.valueOf(requireNotNull(cashDirection)),
            cashLoad,walletView,onRetry={cashRetry++},onDismiss={cashDirection=null;cashEvent=null;cashEditing=false},editing=cashEditing)
    }
    reconciliationTarget?.let{target->key(target){InvestmentCashReconciliationSheet(owner,repository,deviceIdProvider,target.takeUnless{it=="all"},cashLoad,onRetry={cashRetry++},onDismiss={reconciliationTarget=null})}}
    cashActionError?.let{message ->AlertDialog(onDismissRequest={cashActionError=null},title={Text(stringResource(R.string.common_error))},
        text={Text(stringResource(message))},confirmButton={TextButton(onClick={cashActionError=null}){Text(stringResource(R.string.common_ok))}})}
    val id=editorId
    if(id!=null)ModalBottomSheet(onDismissRequest={if(!saving)editorId=null}){
        Column(Modifier.fillMaxWidth().padding(horizontal=20.dp).padding(bottom=24.dp).testTag("investment.channel.sheet"),verticalArrangement=Arrangement.spacedBy(14.dp)){
            Text(stringResource(R.string.investment_channel_new_title),modifier=Modifier.fillMaxWidth(),style=MaterialTheme.typography.titleLarge)
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween){
                TextButton(onClick={editorId=null},enabled=!saving){Text(stringResource(R.string.common_cancel))}
                Button(onClick={
                    if(saving || !readable || !consent || normalizedInvestmentChannelName(name).isEmpty())return@Button
                    saving=true;editorError=null
                    val draft=InvestmentChannelDraft(id,name,expected)
                    scope.launch{
                        try{
                            val result=repository.saveChannel(owner,draft,primaryCurrency,deviceIdProvider(),Instant.now().toString())
                            coroutineContext.ensureActive()
                            if(result.isSuccess)editorId=null else editorError=channelErrorResource(requireNotNull(result.exceptionOrNull()))
                        }catch(cancelled:kotlinx.coroutines.CancellationException){throw cancelled}catch(error:Exception){editorError=channelErrorResource(error)}
                        finally{saving=false}
                    }
                },enabled=!saving && readable && consent && normalizedInvestmentChannelName(name).isNotEmpty(),modifier=Modifier.testTag("investment.channel.save")){Text(stringResource(R.string.common_save))}
            }
            OutlinedTextField(value=name,onValueChange={name=it;editorError=null},enabled=!saving,label={Text(stringResource(R.string.investment_channel_name))},
                placeholder={Text(stringResource(R.string.investment_channel_name_placeholder))},modifier=Modifier.fillMaxWidth().testTag("investment.channel.name"),singleLine=true)
            if(!readable || !consent)Text(stringResource(R.string.common_error),Modifier.testTag("investment.channel.unavailable"),color=MaterialTheme.colorScheme.error)
            if(load==InvestmentChannelReadLoad.Failed)TextButton(onClick={retry++},modifier=Modifier.testTag("investment.channel.retry")){Text(stringResource(R.string.planning_installment_retry))}
            editorError?.let{Text(stringResource(it),Modifier.testTag("investment.channel.error"),color=MaterialTheme.colorScheme.error)}
            if(saving)CircularProgressIndicator(Modifier.size(24.dp))
        }
    }
}

@Composable
private fun InvestmentChannelRow(channel:InvestmentChannelRecord,enabled:Boolean,onEdit:()->Unit,onArchive:()->Unit,onRestore:()->Unit){
    MistiaGlassCard{padding ->Column(Modifier.fillMaxWidth().padding(padding),verticalArrangement=Arrangement.spacedBy(8.dp)){
        Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)){
            CategoryIcon(channel.iconSymbolName,TransactionCategoryKind.INCOME,channel.iconColorHex,Modifier.size(30.dp))
            Text(channel.name,style=MaterialTheme.typography.titleMedium)
        }
        Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){
            TextButton(onClick=onEdit,enabled=enabled,modifier=Modifier.testTag("investment.channel.edit.${channel.id}")){Text(stringResource(R.string.management_management_edit))}
            if(channel.isArchived)TextButton(onClick=onRestore,enabled=enabled,modifier=Modifier.testTag("investment.channel.restore.${channel.id}")){Text(stringResource(R.string.management_managementarchiveditems_restore))}
            else TextButton(onClick=onArchive,enabled=enabled,modifier=Modifier.testTag("investment.channel.archive.${channel.id}")){Text(stringResource(R.string.common_archive))}
        }
    }}
}
private fun decodeChannel(owner:UserId,token:String):InvestmentChannelRecord?=runCatching{
    val p=Json.parseToJsonElement(token).jsonObject
    val id=requireNotNull(p.financeRawString("id"));val version=requireNotNull(p.financeRawLong("sync_version"))
    InvestmentChannelRecord.fromCloudRecord(CloudRecord(CloudEntity.INVESTMENT_CHANNEL.table,id,owner.value,p,p.financeRawString("updated_at"),null,version))
}.getOrNull()
private fun channelErrorResource(error:Throwable):Int=when((error as? InvestmentChannelException)?.reason){
    InvestmentChannelError.OPEN_POSITION ->R.string.investment_error_close_positions_before_archive
    InvestmentChannelError.STALE_RECORD ->R.string.investment_cash_transfer_error_conflict
    else ->R.string.common_error
}
