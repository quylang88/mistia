package vn.com.quyln.mistia.feature.investment

import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import java.time.Instant
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun InvestmentAssetEditorSheet(
    owner:UserId,repository:InvestmentRepository,id:String,expectedToken:String?,
    primaryCurrency:String,enabledCurrencies:List<String>,deviceIdProvider:suspend ()->String,onDismiss:()->Unit,
) {
    val expected=remember(owner.value,expectedToken){expectedToken?.let{decodeInvestmentAsset(owner,it)}}
    var name by rememberSaveable{mutableStateOf(expected?.name.orEmpty())}
    var unit by rememberSaveable{mutableStateOf(expected?.defaultUnitLabel.orEmpty())}
    var channelId by rememberSaveable{mutableStateOf(expected?.channelId.orEmpty())}
    var currency by rememberSaveable{mutableStateOf(expected?.currencyCode ?: primaryCurrency)}
    var imageToken by rememberSaveable{mutableStateOf<String?>(null)}
    var removesImage by rememberSaveable{mutableStateOf(false)}
    var imageRevision by rememberSaveable{mutableStateOf(java.util.UUID.randomUUID().toString())}
    var submittedImageToken by rememberSaveable{mutableStateOf<String?>(null)}
    var imageBusy by remember{mutableStateOf(false)}
    var active by remember(repository){mutableStateOf(true)}
    DisposableEffect(repository){onDispose{active=false}}
    val candidateResult=remember(owner,id,imageToken){imageToken?.let{runCatching{decodeInvestmentImageCandidate(owner,id,it)}}}
    val candidate=candidateResult?.getOrNull()
    val imageChange=when {
        candidate!=null->InvestmentAssetImageChange.Replace(InvestmentProductImagePath.parse(owner,id,candidate.path))
        removesImage->InvestmentAssetImageChange.Remove
        else->InvestmentAssetImageChange.Keep
    }
    var retry by remember{mutableIntStateOf(0)}
    var saving by remember{mutableStateOf(false)}
    var error by remember{mutableStateOf<Int?>(null)}
    var channelMenu by remember{mutableStateOf(false)}
    var currencyMenu by remember{mutableStateOf(false)}
    val load by investmentAssetReadLoad(owner,repository,retry)
    val snapshot=(load as? InvestmentAssetReadLoad.Loaded)?.snapshot
    data class Source(val channels:List<InvestmentChannelRecord>,val current:InvestmentAssetRecord?,val hasHistory:Boolean)
    val parsed=remember(snapshot,id,expectedToken){snapshot?.let {source ->runCatching {
        val channels=source.records(CloudEntity.INVESTMENT_CHANNEL).filter{it.financeRawDeleted()!=true}
            .map(InvestmentChannelRecord::fromCloudRecord).filter{!it.isArchived}
            .sortedWith(compareBy(InvestmentChannelRecord::sortOrder).thenBy{Instant.parse(it.createdAt)}.thenBy(InvestmentChannelRecord::id))
        val raw=source.records(CloudEntity.INVESTMENT_ASSET).singleOrNull{it.id==id}
        val current=raw?.let(InvestmentAssetRecord::fromCloudRecord)?.takeIf{it.deletedAt==null}
        val history=source.records(CloudEntity.INVESTMENT_TRADE).map{trade ->
            val reference=trade.payload.financeRawReference("asset_id")
            require(reference.readable)
            requireNotNull(reference.id)
        }.any{it==id}
        Source(channels,current,history)
    }}}
    val source=parsed?.getOrNull()
    val readable=source!=null
    val consent=if(expectedToken==null)source?.current==null else expected!=null && source?.current?.let(expected::matchesVisibleInvestmentAsset)==true
    val channels=source?.channels.orEmpty()
    val selectedChannel=channels.singleOrNull{it.id==channelId}
    LaunchedEffect(channels,expectedToken) {
        if(expectedToken==null && channelId.isEmpty())channelId=channels.firstOrNull()?.id.orEmpty()
    }
    val historyLocked=expectedToken!=null && source?.hasHistory==true
    val currencies=(enabledCurrencies.mapNotNull{it.financeReportingCode()}+listOfNotNull(expected?.currencyCode)).distinct()
    val canSave=active && !imageBusy && candidateResult?.isFailure!=true && readable && consent && selectedChannel!=null && currency in currencies &&
        normalizedInvestmentChannelName(name).isNotEmpty() && InvestmentUnitLabel.normalizedDisplay(unit)!=null
    val scope=key(repository){rememberCoroutineScope()}
    val liveCanSave by rememberUpdatedState(canSave)
    val liveDraft by rememberUpdatedState(InvestmentAssetDraft(id,channelId,name,currency,unit,expected,imageChange))
    val liveCandidate by rememberUpdatedState(candidate)
    val liveRevision by rememberUpdatedState(imageRevision)
    val submitted=remember(owner,id,expected,submittedImageToken){submittedImageToken?.let{runCatching{decodeSubmittedImage(owner,id,expected,it)}.getOrNull()}}
    val retryAllowed=remember(snapshot,submitted,liveDraft,liveCandidate,liveRevision,active,imageBusy) {
        active && !imageBusy && snapshot!=null && submitted!=null && submitted.draft==liveDraft && submitted.candidate==liveCandidate && submitted.revision==liveRevision &&
            runCatching{planInvestmentAssetImageSave(snapshot,submitted.request(owner),submitted.device,submitted.now)}.isSuccess
    }
    val latestRetryAllowed by rememberUpdatedState(retryAllowed)
    val latestSubmitted by rememberUpdatedState(submitted)
    fun execute(draft:InvestmentAssetDraft,frozenCandidate:InvestmentProductImageCandidate?,revision:String,previous:SubmittedImageSave?=null) {
        if(saving || !active)return
        saving=true;error=null
        scope.launch {
            try {
                val device=previous?.device ?: deviceIdProvider();coroutineContext.ensureActive()
                val now=previous?.now ?: Instant.now().toString()
                if(draft.imageChange!=InvestmentAssetImageChange.Keep)
                    submittedImageToken=encodeSubmittedImage(owner,SubmittedImageSave(draft,frozenCandidate,revision,device,now))
                val result=if(draft.imageChange==InvestmentAssetImageChange.Keep)repository.saveAsset(owner,draft,device,now)
                    else repository.saveAssetImage(owner,draft,frozenCandidate,revision,device,now)
                coroutineContext.ensureActive()
                if(result.isSuccess){submittedImageToken=null;active=false;onDismiss()}
                else error=investmentAssetErrorResource(requireNotNull(result.exceptionOrNull()))
            }catch(cancelled:kotlinx.coroutines.CancellationException){throw cancelled}
            catch(failure:Exception){error=investmentAssetErrorResource(failure)}
            finally{saving=false}
        }
    }
    fun dismiss() {
        if(!active || saving || imageBusy)return
        active=false
        scope.launch {
            try{candidate?.let{repository.discardProductImage(owner,it)}}finally{onDismiss()}
        }
    }
    val sheet=rememberModalBottomSheetState(skipPartiallyExpanded=true,confirmValueChange={it!=SheetValue.Hidden || !saving})
    ModalBottomSheet(onDismissRequest={dismiss()},sheetState=sheet) {
        Column(Modifier.fillMaxWidth().padding(horizontal=20.dp).verticalScroll(rememberScrollState())
            .padding(bottom=24.dp).testTag("investment.asset.sheet"),verticalArrangement=Arrangement.spacedBy(14.dp)) {
            Text(stringResource(R.string.investment_asset_new_title),Modifier.fillMaxWidth(),style=MaterialTheme.typography.titleLarge)
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {
                TextButton(onClick={dismiss()},enabled=!saving && !imageBusy){Text(stringResource(R.string.common_cancel))}
                Button(onClick={
                    if(saving || !active || !liveCanSave)return@Button
                    execute(liveDraft,liveCandidate,liveRevision)
                },enabled=!saving && canSave,modifier=Modifier.testTag("investment.asset.save")){Text(stringResource(R.string.common_save))}
            }
            Text(stringResource(R.string.investment_hub_channels),style=MaterialTheme.typography.labelLarge)
            Box {
                OutlinedButton(onClick={channelMenu=true},enabled=readable && !saving && !historyLocked,
                    modifier=Modifier.fillMaxWidth().testTag("investment.asset.channel")) {
                    Text(selectedChannel?.name ?: stringResource(R.string.investment_hub_channels))
                }
                DropdownMenu(expanded=channelMenu,onDismissRequest={channelMenu=false}) {
                    channels.forEach{channel ->DropdownMenuItem(text={Text(channel.name)},
                        onClick={channelId=channel.id;channelMenu=false;error=null},modifier=Modifier.testTag("investment.asset.channel.option."+channel.id))}
                }
            }
            OutlinedTextField(value=name,onValueChange={name=it;error=null},enabled=!saving,
                label={Text(stringResource(R.string.investment_asset_name))},placeholder={Text(stringResource(R.string.investment_asset_name_placeholder))},
                singleLine=true,modifier=Modifier.fillMaxWidth().testTag("investment.asset.name"))
            OutlinedTextField(value=unit,onValueChange={unit=it;error=null},enabled=!saving,
                label={Text(stringResource(R.string.investment_asset_default_unit_placeholder))},
                singleLine=true,modifier=Modifier.fillMaxWidth().testTag("investment.asset.unit"))
            Text(stringResource(R.string.investment_asset_currency),style=MaterialTheme.typography.labelLarge)
            Box {
                OutlinedButton(onClick={currencyMenu=true},enabled=readable && !saving && !historyLocked,
                    modifier=Modifier.fillMaxWidth().testTag("investment.asset.currency")){Text(currency)}
                DropdownMenu(expanded=currencyMenu,onDismissRequest={currencyMenu=false}) {
                    currencies.forEach{code ->DropdownMenuItem(text={Text(code)},onClick={currency=code;currencyMenu=false;error=null},
                        modifier=Modifier.testTag("investment.asset.currency.option.$code"))}
                }
            }
            InvestmentProductImageField(owner,repository,id,when{candidate!=null->candidate.path;removesImage->null;else->expected?.imagePath},candidate,
                enabled=active && readable && consent && !saving,
                onCandidate={selected->
                    val previous=candidate
                    imageToken=encodeInvestmentImageCandidate(selected);removesImage=false;imageRevision=java.util.UUID.randomUUID().toString();error=null
                    if(previous!=null && previous!=selected)scope.launch{repository.discardProductImage(owner,previous)}
                },onRemove={
                    val previous=candidate;imageToken=null;removesImage=true;imageRevision=java.util.UUID.randomUUID().toString();error=null
                    if(previous!=null)scope.launch{repository.discardProductImage(owner,previous)}
                },onBusy={imageBusy=it},allowEmptyRemoval=expected!=null)
            if(candidateResult?.isFailure==true)Text(stringResource(R.string.common_error),Modifier.testTag("investment.asset.image.invalid"),color=MaterialTheme.colorScheme.error)
            if(historyLocked)Text(stringResource(R.string.investment_error_asset_history_locks_accounting),Modifier.testTag("investment.asset.historyLocked"),style=MaterialTheme.typography.bodySmall)
            if(!readable || !consent || (channelId.isNotEmpty() && selectedChannel==null))
                Text(stringResource(R.string.common_error),Modifier.testTag("investment.asset.unavailable"),color=MaterialTheme.colorScheme.error)
            if(load==InvestmentAssetReadLoad.Loading)CircularProgressIndicator(Modifier.size(24.dp).testTag("investment.asset.loading"))
            if(load==InvestmentAssetReadLoad.Failed || parsed?.isFailure==true)
                TextButton(onClick={retry++},modifier=Modifier.testTag("investment.asset.retry")){Text(stringResource(R.string.planning_installment_retry))}
            if(submitted!=null)TextButton(onClick={
                val attempt=latestSubmitted
                if(attempt!=null && latestRetryAllowed && !saving)execute(attempt.draft,attempt.candidate,attempt.revision,attempt)
            },enabled=!saving && retryAllowed,modifier=Modifier.testTag("investment.asset.image.retrySave")){Text(stringResource(R.string.planning_installment_retry))}
            error?.let{Text(stringResource(it),Modifier.testTag("investment.asset.error"),color=MaterialTheme.colorScheme.error)}
            if(saving)CircularProgressIndicator(Modifier.size(24.dp))
        }
    }
}

internal fun decodeInvestmentAsset(owner:UserId,token:String):InvestmentAssetRecord?=runCatching {
    val p=Json.parseToJsonElement(token).jsonObject
    InvestmentAssetRecord.fromCloudRecord(CloudRecord(CloudEntity.INVESTMENT_ASSET.table,requireNotNull(p.financeRawString("id")),owner.value,p,
        p.financeRawString("updated_at"),p.financeRawString("deleted_at"),requireNotNull(p.financeRawLong("sync_version"))))
}.getOrNull()

internal fun investmentAssetErrorResource(error:Throwable):Int=when((error as? InvestmentAssetException)?.reason) {
    InvestmentAssetError.OPEN_POSITION->R.string.investment_error_close_positions_before_archive
    InvestmentAssetError.HISTORY_LOCKS_ACCOUNTING->R.string.investment_error_asset_history_locks_accounting
    InvestmentAssetError.MISSING_WALLET->R.string.investment_error_missing_wallet
    InvestmentAssetError.MISSING_EXCHANGE_RATE->R.string.investment_error_missing_exchange_rate
    InvestmentAssetError.INVALID_ACCOUNTING->R.string.investment_error_invalid_trade_input
    InvestmentAssetError.STALE_RECORD->R.string.investment_cash_transfer_error_conflict
    else->R.string.common_error
}

internal fun encodeInvestmentImageCandidate(candidate:InvestmentProductImageCandidate)=buildJsonObject {
    put("owner",candidate.ownerUserId);put("asset",candidate.assetId);put("path",candidate.path)
    put("full",candidate.imageSha256);put("thumb",candidate.thumbnailSha256)
}.toString()
internal fun decodeInvestmentImageCandidate(owner:UserId,assetId:String,token:String):InvestmentProductImageCandidate {
    val value=Json.parseToJsonElement(token).jsonObject
    fun text(key:String)=value.getValue(key).jsonPrimitive.let{require(it.isString);it.content}
    require(text("owner")==owner.value && text("asset")==assetId)
    val path=InvestmentProductImagePath.parse(owner,assetId,text("path")).value
    val full=text("full");val thumb=text("thumb");require(Regex("[0-9a-f]{64}").matches(full) && Regex("[0-9a-f]{64}").matches(thumb))
    return InvestmentProductImageCandidate(owner.value,assetId,path,full,thumb)
}

private data class SubmittedImageSave(val draft:InvestmentAssetDraft,val candidate:InvestmentProductImageCandidate?,val revision:String,val device:String,val now:String) {
    fun request(owner:UserId)=InvestmentAssetImageSaveRequest(draft,InvestmentProductImagePublication(owner.value,draft.id,revision,
        ownedInvestmentImagePathOrNull(owner,draft.id,draft.expected?.imagePath),candidate))
}
private fun encodeSubmittedImage(owner:UserId,attempt:SubmittedImageSave)=buildJsonObject {
    put("owner",owner.value);put("id",attempt.draft.id);put("channel",attempt.draft.channelId);put("name",attempt.draft.name)
    put("currency",attempt.draft.currencyCode);put("unit",attempt.draft.defaultUnitLabel)
    put("candidate",attempt.candidate?.let{JsonPrimitive(encodeInvestmentImageCandidate(it))} ?: JsonNull)
    put("revision",attempt.revision);put("device",attempt.device);put("now",attempt.now)
}.toString()
private fun decodeSubmittedImage(owner:UserId,id:String,expected:InvestmentAssetRecord?,token:String):SubmittedImageSave {
    val value=Json.parseToJsonElement(token).jsonObject
    fun text(key:String)=value.getValue(key).jsonPrimitive.let{require(it.isString);it.content}
    require(text("owner")==owner.value && text("id")==id)
    val candidate=value["candidate"]?.takeIf{it!=JsonNull}?.let{decodeInvestmentImageCandidate(owner,id,it.jsonPrimitive.content)}
    val revision=text("revision");val device=text("device");require(financeRawUuid(revision)==revision && financeRawUuid(device)==device)
    val now=text("now");Instant.parse(now)
    val change=if(candidate==null)InvestmentAssetImageChange.Remove else InvestmentAssetImageChange.Replace(InvestmentProductImagePath.parse(owner,id,candidate.path))
    return SubmittedImageSave(InvestmentAssetDraft(id,text("channel"),text("name"),text("currency"),text("unit"),expected,change),candidate,revision,device,now)
}
