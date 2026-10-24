package vn.com.quyln.mistia.feature.investment

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import androidx.activity.compose.LocalActivityResultRegistryOwner
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.core.app.ActivityOptionsCompat
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import java.util.UUID
import kotlinx.coroutines.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class InvestmentProductImageScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=org.junit.rules.RuleChain.outerRule(org.junit.rules.TestRule{base,description->
        object:org.junit.runners.model.Statement(){override fun evaluate() {
            if(description.methodName!="photoPreviewAndActionsRemainCompleteInThreeLanguagesBothThemesAtActual130And320Dp"){base.evaluate();return}
            val instrumentation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
            fun shell(command:String)=android.os.ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command)).bufferedReader().use{it.readText().trim()}
            val font=shell("settings get system font_scale").takeUnless{it=="null"} ?: "1.0"
            val originalSize=Regex("Override size: ([0-9]+x[0-9]+)").find(shell("wm size"))?.groupValues?.get(1)
            val metrics=instrumentation.targetContext.resources.displayMetrics
            try {
                shell("wm size "+kotlin.math.round(320*metrics.density).toInt()+"x"+metrics.heightPixels)
                shell("settings put system font_scale 1.3")
                val until=android.os.SystemClock.uptimeMillis()+5000
                while(instrumentation.targetContext.resources.configuration.fontScale!=1.3f && android.os.SystemClock.uptimeMillis()<until)android.os.SystemClock.sleep(20)
                assertEquals(1.3f,instrumentation.targetContext.resources.configuration.fontScale,0.0001f)
                base.evaluate()
            }finally{shell("settings put system font_scale "+font);shell(if(originalSize==null)"wm size reset" else "wm size "+originalSize)}
        }}
    }).around(compose)
    private val context=ApplicationProvider.getApplicationContext<Context>()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val assetId="22222222-2222-2222-2222-222222222222"
    private val channelId="33333333-3333-3333-3333-333333333333"
    private val device="44444444-4444-4444-4444-444444444444"
    private val now="2026-10-24T00:00:00Z"
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var cache:FileInvestmentProductImageCache
    private lateinit var repository:InvestmentRepository
    private lateinit var directory:File
    private var dismissed by mutableStateOf(false)
    private val registry=object:ActivityResultRegistry() {
        var grantCameraPermission=true
        var request:Int?=null
        var input:Any?=null
        override fun <I,O> onLaunch(requestCode:Int,contract:ActivityResultContract<I,O>,input:I,options:ActivityOptionsCompat?) {
            when(contract) {
                is ActivityResultContracts.RequestPermission->dispatchResult(requestCode,grantCameraPermission)
                else->{request=requestCode;this.input=input}
            }
        }
    }
    private val registryOwner=object:ActivityResultRegistryOwner {override val activityResultRegistry=registry}
    @Before fun setup() {
        directory=File(context.cacheDir,"product-image-screen-${UUID.randomUUID()}")
        cache=FileInvestmentProductImageCache(directory,{owner})
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,productImages=cache)
        repository=OfflineFirstInvestmentRepository(store,productImages=cache)
        runBlocking{repository.saveChannel(owner,InvestmentChannelDraft(channelId,"Shop"),"VND",device,now).getOrThrow()}
    }
    @After fun close(){db.close();directory.deleteRecursively()}
    @Composable private fun Editor(id:String=assetId,source:InvestmentRepository=repository,darkTheme:Boolean=false) {
        MistiaTheme(darkTheme=darkTheme) {CompositionLocalProvider(LocalActivityResultRegistryOwner provides registryOwner) {
            Scaffold{padding->androidx.compose.foundation.layout.Box(Modifier.padding(padding)) {
                if(!dismissed)InvestmentAssetEditorSheet(owner,source,id,null,"VND",listOf("VND"),{device},{dismissed=true})
            }}
        }}
    }
    private fun await(tag:String){compose.waitUntil(8000){compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()}}
    private fun fill() {
        await("investment.asset.name")
        compose.onNodeWithTag("investment.asset.name").performTextInput("Cards")
        compose.onNodeWithTag("investment.asset.unit").performTextInput("box")
    }
    private fun sourcePhoto():Uri {
        val file=File(directory,"source.png");file.parentFile!!.mkdirs()
        val bitmap=Bitmap.createBitmap(480,240,Bitmap.Config.ARGB_8888);bitmap.eraseColor(Color.BLUE)
        try{file.outputStream().use{bitmap.compress(Bitmap.CompressFormat.PNG,100,it)}}finally{bitmap.recycle()}
        return Uri.fromFile(file)
    }
    private fun pick() {
        compose.onNodeWithTag("investment.asset.image.add").performScrollTo().performClick()
        compose.onNodeWithTag("investment.asset.image.library").performClick()
        compose.runOnIdle{registry.dispatchResult(requireNotNull(registry.request),Activity.RESULT_OK,Intent().setData(sourcePhoto()))}
        await("investment.asset.image.remove")
        await("investment.image.loaded.$assetId")
    }
    private fun save(){compose.onNodeWithTag("investment.asset.save").performScrollTo().assertIsEnabled().performClick();compose.waitUntil(8000){dismissed}}
    @Test fun actualLibrarySelectionStagesPreviewAndSavesPrivateMetadataWithDurableThumbnail() {
        compose.setContent{Editor()};fill();pick();save()
        val saved=runBlocking{store.record(owner,CloudEntity.INVESTMENT_ASSET.table,assetId)}!!
        val path=saved.payload.financeRawString("image_path")!!
        assertTrue(path.startsWith(owner.value+"/"+assetId+"/"));assertTrue(path.endsWith(".jpg"))
        val full=runBlocking{cache.cachedImageData(owner,assetId,path,false).getOrThrow()}!!
        val thumb=runBlocking{cache.cachedImageData(owner,assetId,path).getOrThrow()}!!
        val bitmap=android.graphics.BitmapFactory.decodeByteArray(thumb,0,thumb.size)
        try{assertEquals(240,bitmap.width);assertEquals(120,bitmap.height)}finally{bitmap.recycle()}
        assertNotEquals(full.size,thumb.size)
        assertEquals(path,runBlocking{cache.pendingUploads(owner).getOrThrow()}.single().path)
    }
    @Test fun actualStagedPhotoAndMetadataInputsSurviveSavedStateRestoration() {
        val restoration=StateRestorationTester(compose);restoration.setContent{Editor()};fill();pick()
        restoration.emulateSavedInstanceStateRestore();await("investment.image.loaded.$assetId")
        compose.onNodeWithTag("investment.asset.name").assertTextContains("Cards")
        compose.onNodeWithTag("investment.asset.unit").assertTextContains("box")
        save();assertNotNull(runBlocking{store.record(owner,CloudEntity.INVESTMENT_ASSET.table,assetId)}?.payload?.financeRawString("image_path"))
    }
    @Test fun actualCancelDiscardsAnUnreservedPickerSelectionWithoutCreatingAnAsset() {
        compose.setContent{Editor()};fill();pick()
        compose.onNodeWithText(context.getString(vn.com.quyln.mistia.core.designsystem.R.string.common_cancel)).performScrollTo().performClick()
        compose.waitUntil(8000){dismissed}
        assertNull(runBlocking{store.record(owner,CloudEntity.INVESTMENT_ASSET.table,assetId)})
        assertTrue(directory.walkTopDown().none{it.extension=="jpg"})
        assertTrue(runBlocking{cache.pendingUploads(owner).getOrThrow()}.isEmpty())
    }
    @Test fun actualCameraWritesOnlyToTheNarrowProviderThenStagesNormalizedPhoto() {
        compose.setContent{Editor()};fill()
        compose.onNodeWithTag("investment.asset.image.add").performScrollTo().performClick()
        compose.onNodeWithTag("investment.asset.image.camera").performClick()
        compose.waitUntil(8000){registry.input is Uri}
        compose.runOnIdle {
            val uri=registry.input as Uri
            assertEquals(context.packageName+".investment-product-images",uri.authority)
            val bitmap=Bitmap.createBitmap(480,240,Bitmap.Config.ARGB_8888);bitmap.eraseColor(Color.RED)
            try{context.contentResolver.openOutputStream(uri)!!.use{bitmap.compress(Bitmap.CompressFormat.JPEG,90,it)}}finally{bitmap.recycle()}
            registry.dispatchResult(requireNotNull(registry.request),true)
        }
        await("investment.image.loaded.$assetId");save()
        assertNotNull(runBlocking{store.record(owner,CloudEntity.INVESTMENT_ASSET.table,assetId)}?.payload?.financeRawString("image_path"))
    }
    @Test fun actualInventoryListDisplaysTheSavedProductThumbnail() {
        val prepared=runBlocking{AndroidInvestmentProductImagePreparer(context.contentResolver).prepare(sourcePhoto())}
        val candidate=runBlocking{repository.stageProductImage(owner,assetId,prepared).getOrThrow()}
        val path=InvestmentProductImagePath.parse(owner,assetId,candidate.path)
        runBlocking{repository.saveAssetImage(owner,InvestmentAssetDraft(assetId,channelId,"Cards","VND","box",imageChange=InvestmentAssetImageChange.Replace(path)),candidate,UUID.randomUUID().toString(),device,now).getOrThrow()}
        compose.setContent{MistiaTheme(darkTheme=false) {Scaffold{padding->InvestmentScreen(owner,repository,{},Modifier.padding(padding),primaryCurrencyCode="VND",deviceIdProvider={device},enabledCurrencyCodes=listOf("VND"))}}}
        compose.waitUntil(8000){runCatching{compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag("investment.image.loaded.$assetId"));true}.getOrDefault(false)}
        compose.onNodeWithTag("investment.image.loaded.$assetId").assertIsDisplayed()
    }
    @Test fun dismissedPickerResultCannotAttachToAnotherNewAssetForm() {
        var currentId by mutableStateOf(assetId)
        compose.setContent{key(currentId){Editor(currentId)}};fill()
        compose.onNodeWithTag("investment.asset.image.add").performScrollTo().performClick()
        compose.onNodeWithTag("investment.asset.image.library").performClick()
        var oldRequest=0
        compose.runOnIdle{oldRequest=requireNotNull(registry.request);currentId="66666666-6666-6666-6666-666666666666"}
        await("investment.asset.name")
        compose.runOnIdle{registry.dispatchResult(oldRequest,Activity.RESULT_OK,Intent().setData(sourcePhoto()))}
        compose.waitForIdle()
        compose.onNodeWithTag("investment.asset.image.add").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("investment.asset.image.remove").assertDoesNotExist()
        assertTrue(runBlocking{store.investmentAssetSnapshot(owner)}.records(CloudEntity.INVESTMENT_ASSET).isEmpty())
        assertTrue(directory.walkTopDown().none{it.extension=="jpg"})
    }
    @Test fun deniedCameraPermissionShowsRecoverableErrorWithoutCreatingAnAsset() {
        registry.grantCameraPermission=false
        compose.setContent{Editor()};fill()
        compose.onNodeWithTag("investment.asset.image.add").performScrollTo().performClick()
        compose.onNodeWithTag("investment.asset.image.camera").performClick()
        await("investment.asset.image.error")
        assertNull(registry.input)
        compose.onNodeWithTag("investment.asset.image.add").performScrollTo().assertIsEnabled()
        assertTrue(runBlocking{store.investmentAssetSnapshot(owner)}.records(CloudEntity.INVESTMENT_ASSET).isEmpty())
    }

    @androidx.test.filters.SdkSuppress(minSdkVersion=29)
    @Suppress("DEPRECATION")
    @Test fun photoPreviewAndActionsRemainCompleteInThreeLanguagesBothThemesAtActual130And320Dp() {
        var language by mutableStateOf("en");var dark by mutableStateOf(false);var scenario by mutableIntStateOf(0)
        compose.setContent {
            val config=android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),
                androidx.compose.ui.platform.LocalConfiguration provides config){key(scenario){Editor(darkTheme=dark)}}
        }
        val originals=linkedMapOf<android.content.res.Resources,android.content.res.Configuration>()
        fun configure(code:String) {
            val windows=android.view.inspector.WindowInspector.getGlobalWindowViews()
            (windows.map{it.context.resources}+context.resources).distinct().forEach{resource->
                originals.putIfAbsent(resource,android.content.res.Configuration(resource.configuration))
                resource.updateConfiguration(android.content.res.Configuration(resource.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))},resource.displayMetrics)
            }
            windows.forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}
        }
        fun complete(text:String) {
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithText(text,useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
            val layout=layouts.single()
            assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
            assertFalse(layout.didOverflowHeight)
            assertEquals(layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true))
            for(line in 0 until layout.lineCount){assertFalse(layout.isLineEllipsized(line));assertTrue(layout.getLineLeft(line)>=-1f);assertTrue(layout.getLineRight(line)<=layout.size.width+1f)}
        }
        try {
            for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)) {
                compose.runOnIdle{configure(code);language=code;dark=theme;dismissed=false;scenario++}
                fill();pick();compose.runOnIdle{configure(code)}
                compose.onNodeWithTag("investment.asset.image.remove").performScrollTo().assertIsDisplayed()
                compose.onNodeWithTag("investment.image.loaded.$assetId").assertIsDisplayed()
                val localized=context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))})
                complete(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_asset_image_optional))
                complete(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_asset_remove_image))
                val width=compose.onNodeWithTag("investment.asset.sheet").fetchSemanticsNode().boundsInRoot.width
                assertEquals(280*context.resources.displayMetrics.density,width,1f)
                val bitmap=compose.onNodeWithTag("investment.asset.sheet").captureToImage().asAndroidBitmap()
                File(context.getExternalFilesDir(null),"investment-product-photo-"+code+"-"+(if(theme)"dark" else "light")+"-font130-width320.png").outputStream().use{assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG,100,it))}
                compose.onNodeWithText(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.common_cancel)).performScrollTo().performClick()
                compose.waitUntil(8000){dismissed}
                assertTrue(runBlocking{store.investmentAssetSnapshot(owner)}.records(CloudEntity.INVESTMENT_ASSET).isEmpty())
                assertTrue(runBlocking{cache.pendingUploads(owner).getOrThrow()}.isEmpty())
            }
        }finally{compose.runOnIdle{
            originals.forEach{(resource,configuration)->resource.updateConfiguration(configuration,resource.displayMetrics)}
            android.view.inspector.WindowInspector.getGlobalWindowViews().forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}
        }}
    }

    @Test fun lostCommitReplyAndTemporarilyFailedProbeOfferAnExactNoWriteImageRetry()=lostReplyRetry(false)
    @Test fun restoredUncertainImageSaveRetriesOnlyItsFrozenInputsAndRevokesOldCallbacks()=lostReplyRetry(true)
    private fun lostReplyRetry(restore:Boolean) {
        var failProbe=false;var loseReply=true
        val racing=object:LocalStore by store {
            override suspend fun investmentAssetSnapshot(owner:UserId):InvestmentAssetSnapshot {
                if(failProbe){failProbe=false;throw java.io.IOException("synthetic temporary probe failure")}
                return store.investmentAssetSnapshot(owner)
            }
            override suspend fun commitInvestmentAssetImageMutation(expected:InvestmentAssetSnapshot,request:InvestmentAssetImageSaveRequest,deviceId:String,now:String):Boolean {
                val saved=store.commitInvestmentAssetImageMutation(expected,request,deviceId,now)
                if(loseReply){loseReply=false;failProbe=true;throw java.io.IOException("synthetic lost commit reply")}
                return saved
            }
        }
        val retryRepository=OfflineFirstInvestmentRepository(racing,productImages=cache)
        val restoration=StateRestorationTester(compose)
        restoration.setContent{Editor(source=retryRepository)};fill();pick()
        compose.onNodeWithTag("investment.asset.save").performScrollTo().performClick();await("investment.asset.error")
        val before=runBlocking{store.investmentAssetSnapshot(owner)}
        assertNotNull(before.records(CloudEntity.INVESTMENT_ASSET).single().payload.financeRawString("image_path"))
        assertTrue(runBlocking{cache.pendingUploads(owner).getOrThrow()}.isEmpty())
        if(restore){restoration.emulateSavedInstanceStateRestore();await("investment.asset.image.retrySave")}
        compose.onNodeWithTag("investment.asset.image.retrySave").performScrollTo().assertIsEnabled()
        if(restore) {
            val oldClick=compose.onNodeWithTag("investment.asset.image.retrySave").fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsActions.OnClick].action!!
            compose.onNodeWithTag("investment.asset.name").performScrollTo().performTextReplacement("Different input")
            compose.onNodeWithTag("investment.asset.image.retrySave").assertIsNotEnabled()
            compose.runOnIdle{oldClick()};compose.waitForIdle()
            assertFalse(dismissed);assertEquals(before,runBlocking{store.investmentAssetSnapshot(owner)})
            assertTrue(runBlocking{cache.pendingUploads(owner).getOrThrow()}.isEmpty())
            compose.onNodeWithTag("investment.asset.name").performTextReplacement("Cards")
            compose.onNodeWithTag("investment.asset.image.retrySave").performScrollTo().assertIsEnabled()
        }
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_retry_write BEFORE INSERT ON cloud_records WHEN NEW.entity = 'investment_assets' BEGIN SELECT RAISE(ABORT, 'exact retry must not write'); END")
        compose.onNodeWithTag("investment.asset.image.retrySave").performClick();compose.waitUntil(8000){dismissed}
        assertEquals(before,runBlocking{store.investmentAssetSnapshot(owner)})
        assertEquals(1,runBlocking{cache.pendingUploads(owner).getOrThrow()}.size)
    }

    private fun seedPhotographedLiquidation()=runBlocking {
        val prepared=AndroidInvestmentProductImagePreparer(context.contentResolver).prepare(sourcePhoto())
        val candidate=repository.stageProductImage(owner,assetId,prepared).getOrThrow()
        val asset=repository.saveAssetImage(owner,InvestmentAssetDraft(assetId,channelId,"Cards","VND","box",imageChange=InvestmentAssetImageChange.Replace(InvestmentProductImagePath.parse(owner,assetId,candidate.path))),candidate,UUID.randomUUID().toString(),device,now).getOrThrow()
        val funding=WalletDraft(id="88888888-8888-8888-8888-888888888888",name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=100).toMutation(owner,null,device,now)
        store.commitMutations(listOf(funding.record to funding.pending))
        val wallet=LedgerWalletRecord.fromCloudRecord(funding.record)
        repository.savePurchase(owner,InvestmentPurchaseRequest(InvestmentPurchaseDraft("66666666-6666-6666-6666-666666666666",assetId,"1","box",100,100,"VND",null,null,null,wallet.id,100,null,null,"2026-10-23T00:00:00Z","2026-10-23T00:00:00Z"),asset,wallet,null,"Reserve"),device,now).getOrThrow()
        repository.saveSale(owner,InvestmentSaleRequest(InvestmentSaleDraft("77777777-7777-7777-7777-777777777777",assetId,"1","box",0,0,"VND",null,null,null,null,null,null,now,now),asset,null,null,"Reserve"),device,now).getOrThrow()
        assertEquals(candidate.path,store.record(owner,CloudEntity.INVESTMENT_ASSET.table,assetId)!!.payload.financeRawString("image_path"))
        assertNotNull(repository.productImageData(owner,assetId,candidate.path).getOrThrow())
    }
    @Composable private fun Inventory() {
        MistiaTheme(darkTheme=false){Scaffold{padding->InvestmentScreen(owner,repository,{},Modifier.padding(padding),primaryCurrencyCode="VND",deviceIdProvider={device},enabledCurrencyCodes=listOf("VND"))}}
    }
    @Test fun actualActivityRowDisplaysItsOwnedProductPhoto() {
        seedPhotographedLiquidation();compose.setContent{Inventory()}
        val tradeTag="investment.trade.77777777-7777-7777-7777-777777777777"
        compose.waitUntil(8000){runCatching{compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag(tradeTag));true}.getOrDefault(false)}
        val photo=hasTestTag("investment.image.loaded.$assetId") and hasAnyAncestor(hasTestTag(tradeTag))
        try{compose.waitUntil(8000){compose.onAllNodes(photo,useUnmergedTree=true).fetchSemanticsNodes().isNotEmpty()}}
        catch(error:Throwable){File(context.getExternalFilesDir(null),"photo-activity-debug.txt").writeText(compose.onRoot(useUnmergedTree=true).printToString());throw error}
        compose.onNode(photo,useUnmergedTree=true).assertIsDisplayed()
    }
    @Test fun actualLiquidationCashHistoryDisplaysItsOwnedProductPhoto() {
        seedPhotographedLiquidation();compose.setContent{Inventory()}
        await("investment.cash.history.seeAll")
        compose.onNodeWithTag("investment.cash.history.seeAll").performScrollTo().performClick()
        await("investment.cash.history.screen")
        compose.waitUntil(8000){compose.onAllNodesWithTag("investment.cash.history.empty").fetchSemanticsNodes().isEmpty() && compose.onAllNodesWithTag("investment.cash.history.item.77777777-7777-7777-7777-777777777777").fetchSemanticsNodes().isNotEmpty()}
        try{compose.waitUntil(8000){compose.onAllNodesWithTag("investment.image.loaded.$assetId",useUnmergedTree=true).fetchSemanticsNodes().isNotEmpty()}}
        catch(error:Throwable){File(context.getExternalFilesDir(null),"photo-history-debug.txt").writeText(compose.onRoot(useUnmergedTree=true).printToString());throw error}
        compose.onNodeWithTag("investment.image.loaded.$assetId",useUnmergedTree=true).assertIsDisplayed()
    }

}
