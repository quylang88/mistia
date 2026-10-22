package vn.com.quyln.mistia.feature.investment

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
    primaryCurrencyCode:String="JPY",deviceIdProvider:suspend ()->String={throw UnsupportedOperationException("Device identity unavailable")},enabledCurrencyCodes:List<String> = listOf(primaryCurrencyCode)) {
    key(ownerUserId.value,repository){OwnedInvestmentScreen(ownerUserId,repository,onBack,modifier,primaryCurrencyCode,deviceIdProvider,enabledCurrencyCodes)}
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun OwnedInvestmentScreen(owner:UserId,repository:InvestmentRepository,onBack:()->Unit,modifier:Modifier,
    primaryCurrency:String,deviceIdProvider:suspend ()->String,enabledCurrencies:List<String>) {
    var retry by remember{mutableIntStateOf(0)}
    val load by investmentChannelReadLoad(owner,repository,retry)
    val snapshot=(load as? InvestmentChannelReadLoad.Loaded)?.snapshot
    val parsed=remember(snapshot){snapshot?.let{runCatching{
        it.records(CloudEntity.INVESTMENT_CHANNEL).filter{row ->row.financeRawDeleted()!=true}.map(InvestmentChannelRecord::fromCloudRecord)
            .sortedWith(compareBy(InvestmentChannelRecord::sortOrder).thenBy{channel ->Instant.parse(channel.createdAt)}.thenBy(InvestmentChannelRecord::id))
    }}}
    val channels=parsed?.getOrNull()
    val readable=snapshot!=null && channels!=null
    val scope=rememberCoroutineScope()
    var editorId by rememberSaveable{mutableStateOf<String?>(null)}
    var expectedToken by rememberSaveable{mutableStateOf<String?>(null)}
    var name by rememberSaveable{mutableStateOf("")}
    var saving by remember{mutableStateOf(false)}
    var editorError by remember{mutableStateOf<Int?>(null)}
    var actionError by remember{mutableStateOf<Int?>(null)}
    var archiveToken by rememberSaveable{mutableStateOf<String?>(null)}
    var actionRunning by remember{mutableStateOf(false)}
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
    LazyColumn(modifier.fillMaxSize(),contentPadding=PaddingValues(16.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
        item{
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){
                IconButton(onClick=onBack){Icon(Icons.AutoMirrored.Filled.ArrowBack,stringResource(R.string.common_close))}
                Text(stringResource(R.string.investment_title),style=MaterialTheme.typography.headlineMedium)
            }
        }
        item(key="investment.wallet.link"){InvestmentLinkedWalletSection(owner,repository,deviceIdProvider)}
        item{Button(onClick={edit(null)},enabled=readable && !actionRunning,modifier=Modifier.testTag("investment.channels.add")){Text(stringResource(R.string.investment_hub_add_channel))}}
        item{Button(onClick={editAsset(null)},enabled=assetReadable && !actionRunning && channels.orEmpty().any{!it.isArchived},
            modifier=Modifier.testTag("investment.assets.add")){Text(stringResource(R.string.investment_hub_add_asset))}}
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
                Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){
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
        val trades=snapshot?.records(CloudEntity.INVESTMENT_TRADE).orEmpty().filter{it.financeRawDeleted()==false}
        if(trades.isNotEmpty())item{Text(stringResource(R.string.investment_hub_activity),style=MaterialTheme.typography.titleLarge)}
        items(trades.take(20),key={"trade-${it.id}"}){trade ->
            val currency=trade.payload.financeRawString("currency_code")?.financeReportingCode()
            val amount=trade.payload.financeRawLong("gross_amount_minor")
            MistiaGlassCard{padding ->MistiaRecordRow(trade.string("kind_raw_value") ?: stringResource(R.string.investment_hub_activity),
                subtitle=trade.string("occurred_at"),trailing=if(currency==null || amount==null) "—" else formatMinorUnits(amount,currency),modifier=Modifier.padding(padding))}
        }
        item{Spacer(Modifier.height(32.dp))}
    }
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
