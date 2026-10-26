package vn.com.quyln.mistia.feature.investment

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File
import java.util.UUID
import kotlinx.coroutines.*
import androidx.compose.ui.res.painterResource
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@Composable
internal fun InvestmentProductThumbnail(owner:UserId,repository:InvestmentRepository,assetId:String,path:String?,
    modifier:Modifier=Modifier,size:Dp=44.dp,candidate:InvestmentProductImageCandidate?=null,isEditor:Boolean=false) {
    key(owner,repository,assetId,path,candidate) {
        InvestmentProductThumbnailContent(owner,repository,assetId,path,modifier,size,candidate,isEditor)
    }
}

@Composable
private fun InvestmentProductThumbnailContent(owner:UserId,repository:InvestmentRepository,assetId:String,path:String?,modifier:Modifier,size:Dp,candidate:InvestmentProductImageCandidate?,isEditor:Boolean) {
    var retry by remember(owner,repository,assetId,path,candidate){mutableIntStateOf(0)}
    val state by produceState<Result<ByteArray?>?>(null,owner,repository,assetId,path,candidate,retry) {
        value=null
        if(path!=null)value=if(candidate!=null)repository.stagedProductImageData(owner,candidate).map{it}
            else repository.productImageData(owner,assetId,path)
    }
    val bitmap=remember(state){state?.getOrNull()?.let{BitmapFactory.decodeByteArray(it,0,it.size)}?.asImageBitmap()}
    Box(modifier.size(size).clip(RoundedCornerShape(if(isEditor)22.dp else maxOf(10.dp,size*0.22f))).background(MaterialTheme.colorScheme.surfaceContainerHighest),contentAlignment=Alignment.Center) {
        if(bitmap!=null)Image(bitmap,contentDescription=null,modifier=Modifier.fillMaxSize().testTag("investment.image.loaded.$assetId"),contentScale=ContentScale.Crop)
        else Icon(painterResource(if(isEditor && path==null)vn.com.quyln.mistia.feature.investment.R.drawable.investment_photo_add else vn.com.quyln.mistia.feature.investment.R.drawable.investment_product_box),contentDescription=null,modifier=Modifier.size(size*(if(isEditor && path==null)0.5f else 0.36f)),tint=MaterialTheme.colorScheme.onSurfaceVariant)
        if(state?.isFailure==true)TextButton(onClick={retry++},modifier=Modifier.testTag("investment.image.retry.$assetId")){Text(stringResource(R.string.planning_installment_retry),style=MaterialTheme.typography.labelSmall)}
    }
}

@Composable
internal fun InvestmentProductImageField(owner:UserId,repository:InvestmentRepository,assetId:String,path:String?,
    candidate:InvestmentProductImageCandidate?,enabled:Boolean,onCandidate:(InvestmentProductImageCandidate)->Unit,
    onRemove:()->Unit,onBusy:(Boolean)->Unit,allowEmptyRemoval:Boolean=false) {
    val context=LocalContext.current
    val background=if(MaterialTheme.colorScheme.background.luminance()<0.5f)android.graphics.Color.BLACK else android.graphics.Color.WHITE
    val preparer=remember(context,background){AndroidInvestmentProductImagePreparer(context.contentResolver,backgroundColor=background)}
    val scope=key(repository){rememberCoroutineScope()}
    val latestEnabled by rememberUpdatedState(enabled)
    val latestCandidate by rememberUpdatedState(onCandidate)
    val latestBusy by rememberUpdatedState(onBusy)
    var active by remember(owner,repository,assetId){mutableStateOf(true)}
    var processing by remember{mutableStateOf(false)}
    var menu by remember{mutableStateOf(false)}
    var failed by remember{mutableStateOf(false)}
    val formNonce=rememberSaveable{UUID.randomUUID().toString()}
    var pendingLibrary by rememberSaveable{mutableStateOf<String?>(null)}
    var captureName by rememberSaveable{mutableStateOf<String?>(null)}
    var pendingCamera by rememberSaveable{mutableStateOf<String?>(null)}
    DisposableEffect(owner,repository,assetId){onDispose{active=false}}
    fun captureFile(name:String):File {
        require(Regex("[0-9a-f-]{36}\\.jpg").matches(name))
        return File(context.cacheDir,"investment-photo-capture/$name")
    }
    fun accept(uri:Uri,temporary:File?=null) {
        if(!active || !latestEnabled || processing){temporary?.delete();return}
        processing=true;latestBusy(true);failed=false
        scope.launch {
            var staged:InvestmentProductImageCandidate?=null
            var accepted=false
            try {
                val image=preparer.prepare(uri)
                ensureActive()
                if(!active || !latestEnabled)return@launch
                staged=repository.stageProductImage(owner,assetId,image).getOrThrow()
                ensureActive()
                if(active && latestEnabled){latestCandidate(requireNotNull(staged));accepted=true}
            }catch(cancelled:CancellationException){throw cancelled}
            catch(error:Exception){if(active)failed=true}
            finally {
                temporary?.delete()
                if(!accepted && staged!=null)withContext(NonCancellable){runCatching{repository.discardProductImage(owner,requireNotNull(staged))}}
                processing=false;latestBusy(false)
            }
        }
    }
    val picker=rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()){uri->
        val matches=pendingLibrary==formNonce;pendingLibrary=null
        if(matches && uri!=null)accept(uri)
    }
    val camera=rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()){saved->
        val matches=pendingCamera==formNonce;pendingCamera=null
        val name=captureName;captureName=null
        val file=name?.let{runCatching{captureFile(it)}.getOrNull()}
        if(saved && matches && file!=null)accept(Uri.fromFile(file),file) else file?.delete()
    }
    fun launchCamera() {
        if(!active || !latestEnabled || processing)return
        val name=UUID.randomUUID().toString()+".jpg"
        val file=captureFile(name)
        try {
            check(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs())
            check(file.createNewFile())
            captureName=name;pendingCamera=formNonce
            camera.launch(FileProvider.getUriForFile(context,context.packageName+".investment-product-images",file))
        }catch(error:Exception){file.delete();captureName=null;pendingCamera=null;failed=true}
    }
    val permission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()){granted->
        if(pendingCamera==formNonce && granted)launchCamera()
        else {pendingCamera=null;if(active && latestEnabled)failed=true}
    }
    Column(Modifier.fillMaxWidth(),verticalArrangement=Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.investment_asset_image_optional),style=MaterialTheme.typography.labelLarge)
        InvestmentProductThumbnail(owner,repository,assetId,path,Modifier.align(Alignment.CenterHorizontally),104.dp,candidate,isEditor=true)
        if(path!=null)TextButton(onClick={if(active && latestEnabled && !processing){failed=false;onRemove()}},enabled=enabled && !processing,
            modifier=Modifier.testTag("investment.asset.image.remove")){Text(stringResource(R.string.investment_asset_remove_image),color=MaterialTheme.colorScheme.error)}
        else Box {
            OutlinedButton(onClick={if(active && latestEnabled && !processing)menu=true},enabled=enabled && !processing,modifier=Modifier.testTag("investment.asset.image.add")){Text(stringResource(R.string.investment_asset_add_image))}
            DropdownMenu(menu,onDismissRequest={menu=false}) {
                DropdownMenuItem(text={Text(stringResource(R.string.investment_asset_take_photo))},modifier=Modifier.testTag("investment.asset.image.camera"),onClick={
                    menu=false
                    if(active && latestEnabled && !processing) {
                        if(ContextCompat.checkSelfPermission(context,Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED)launchCamera()
                        else {pendingCamera=formNonce;permission.launch(Manifest.permission.CAMERA)}
                    }
                })
                DropdownMenuItem(text={Text(stringResource(R.string.investment_asset_choose_photo))},modifier=Modifier.testTag("investment.asset.image.library"),onClick={
                    menu=false
                    if(active && latestEnabled && !processing){pendingLibrary=formNonce;picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))}
                })
                if(allowEmptyRemoval)DropdownMenuItem(text={Text(stringResource(R.string.investment_asset_remove_image))},modifier=Modifier.testTag("investment.asset.image.clear"),onClick={
                    menu=false
                    if(active && latestEnabled && !processing){failed=false;onRemove()}
                })
            }
        }
        if(processing)CircularProgressIndicator(Modifier.size(24.dp).testTag("investment.asset.image.processing"))
        if(failed)Text(stringResource(R.string.common_error),Modifier.testTag("investment.asset.image.error"),color=MaterialTheme.colorScheme.error)
    }
}
