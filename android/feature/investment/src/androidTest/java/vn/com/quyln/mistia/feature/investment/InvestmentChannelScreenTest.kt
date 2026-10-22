package vn.com.quyln.mistia.feature.investment

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.test.*
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class InvestmentChannelScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(org.junit.rules.TestRule {base,description ->
        object:org.junit.runners.model.Statement(){override fun evaluate(){
            if(description.methodName!="editorAndArchiveErrorFollowThreeLanguagesLightDarkAtActual130WithoutWrites"){base.evaluate();return}
            val instrumentation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
            fun shell(command:String)=android.os.ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command)).bufferedReader().use{it.readText().trim()}
            val original=shell("settings get system font_scale").takeUnless{it=="null"} ?: "1.0"
            try{
                shell("settings put system font_scale 1.3")
                val end=android.os.SystemClock.uptimeMillis()+5000
                while(instrumentation.targetContext.resources.configuration.fontScale!=1.3f && android.os.SystemClock.uptimeMillis()<end)android.os.SystemClock.sleep(20)
                Assert.assertEquals(1.3f,instrumentation.targetContext.resources.configuration.fontScale,0.0001f)
                base.evaluate()
            }finally{shell("settings put system font_scale $original")}
        }}
    }).around(object:ExternalResource(){override fun after(){if(::db.isInitialized)db.close()}}).around(compose)
    private val context=ApplicationProvider.getApplicationContext<Context>()
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstInvestmentRepository
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="44444444-4444-4444-4444-444444444444"
    private val now="2026-10-21T00:00:00Z"
    @Before fun setup(){db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db);repo=OfflineFirstInvestmentRepository(store){context.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_wallet_name)}}
    @Composable private fun Screen(subject:UserId=owner,source:InvestmentRepository=repo,dark:Boolean=false){MistiaTheme(darkTheme=dark){androidx.compose.material3.Scaffold{padding ->
        InvestmentScreen(subject,source,{},androidx.compose.ui.Modifier.padding(padding),primaryCurrencyCode="VND",deviceIdProvider={device})
    }}}
    private fun channels(subject:UserId=owner)=runBlocking{store.recordsIncludingDeleted(subject,CloudEntity.INVESTMENT_CHANNEL.table)}
    private fun queues(subject:UserId=owner)=runBlocking{InvestmentChannelSnapshot.entities.associateWith{store.pendingMutations(subject,it,Long.MAX_VALUE)}}
    private fun channel(name:String="Cards")=runBlocking{repo.saveChannel(owner,InvestmentChannelDraft(id,name),"VND",device,now).getOrThrow()}
    private fun await(tag:String){compose.waitUntil(5000){
        if(compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty())true
        else if(tag=="investment.assets.add" || tag.startsWith("investment.channels.") ||
            listOf("investment.asset.edit.","investment.asset.archive.","investment.asset.restore.","investment.channel.edit.","investment.channel.archive.","investment.channel.restore.").any(tag::startsWith))
            runCatching{compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag(tag));true}.getOrDefault(false)
        else false
    }}
    private fun add(){await("investment.channels.add");compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.channels.add") and isEnabled()).fetchSemanticsNodes().isNotEmpty()};compose.onNodeWithTag("investment.channels.add").performScrollTo().performClick();await("investment.channel.name")}
    private fun save(){compose.onNodeWithTag("investment.channel.save").assertIsEnabled().performClick()}
    private fun awaitClosed(){compose.waitUntil(5000){compose.onAllNodesWithTag("investment.channel.sheet").fetchSemanticsNodes().isEmpty()}}
    @Test fun actualRoomCreateTrimsNameAndWritesCanonicalWalletAndExactlyTwoOwnedQueues(){
        compose.setContent{Screen()};add();compose.onNodeWithTag("investment.channel.save").assertIsNotEnabled()
        compose.onNodeWithTag("investment.channel.name").performTextInput("\u0085 \u00a0\u200b");compose.onNodeWithTag("investment.channel.save").assertIsNotEnabled()
        compose.onNodeWithTag("investment.channel.name").performTextReplacement("\u0085\u200b Sealed cards \u200b\u0085");save();awaitClosed()
        compose.onNodeWithText("Sealed cards").assertExists();val channel=channels().single();Assert.assertEquals(JsonPrimitive("Sealed cards"),channel.payload["name"])
        val wallet=runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_WALLET.table)}.single();Assert.assertEquals(investmentSystemWalletId(owner),wallet.id);Assert.assertEquals(JsonPrimitive("VND"),wallet.payload["currency_code"])
        Assert.assertEquals(JsonPrimitive(context.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_wallet_name)),wallet.payload["name"])
        Assert.assertEquals(2,queues().values.sumOf{it.size});Assert.assertTrue(channels(other).isEmpty());Assert.assertTrue(queues(other).values.all{it.isEmpty()})
    }
    @Test fun actualRenameArchiveAndRestorePreserveSourceIdentityAndNeverCreateAnotherWallet(){
        val original=channel();compose.setContent{Screen()};await("investment.channel.edit.$id")
        compose.onNodeWithTag("investment.channel.edit.$id").performScrollTo().performClick();compose.onNodeWithTag("investment.channel.name").performTextReplacement("Cards updated");save();awaitClosed()
        compose.onNodeWithTag("investment.channel.archive.$id").performScrollTo().performClick();compose.onNodeWithTag("investment.channel.confirmArchive").performClick()
        await("investment.channel.restore.$id");Assert.assertEquals(JsonPrimitive(true),channels().single().payload["is_archived"])
        compose.onNodeWithTag("investment.channel.restore.$id").performScrollTo().performClick();await("investment.channel.edit.$id")
        val restored=InvestmentChannelRecord.fromCloudRecord(channels().single());Assert.assertEquals("Cards updated",restored.name);Assert.assertEquals(original.id,restored.id);Assert.assertEquals(original.createdAt,restored.createdAt);Assert.assertFalse(restored.isArchived);Assert.assertNull(restored.archivedAt)
        Assert.assertEquals(1,runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_WALLET.table)}.size);Assert.assertEquals(2,queues().values.sumOf{it.size})
    }
    @Test fun archiveWithOpenStockShowsLocalizedErrorAndDoesNotChangeRowsOrQueues(){
        channel();val assetId="33333333-3333-3333-3333-333333333333";val tradeId="55555555-5555-5555-5555-555555555555"
        fun row(entity:CloudEntity,rowId:String,fields:JsonObject)=CloudRecord(entity.table,rowId,owner.value,JsonObject(buildJsonObject{put("id",rowId);put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("is_archived",false)}+fields),now,null,0)
        val asset=row(CloudEntity.INVESTMENT_ASSET,assetId,buildJsonObject{put("channel_id",id);put("name","Booster box");put("currency_code","VND")})
        val trade=row(CloudEntity.INVESTMENT_TRADE,tradeId,buildJsonObject{put("asset_id",assetId);put("occurred_at",now);put("position_quantity_after_decimal_string","0.5")})
        runBlocking{store.commitMutations(listOf(asset,trade).map{it to PendingMutation(CloudEntity.fromTable(it.entity)!!,it.id,owner.value,MutationKind.UPSERT,it.payload,now,0,device)})}
        val before=channels();val pending=queues();compose.setContent{Screen()};await("investment.channel.archive.$id");compose.onNodeWithTag("investment.channel.archive.$id").performScrollTo().performClick();compose.onNodeWithTag("investment.channel.confirmArchive").performClick()
        await("investment.channels.error");compose.onNode(isDialog()).assertExists();compose.onNodeWithText(context.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_error_close_positions_before_archive)).assertExists();Assert.assertEquals(before,channels());Assert.assertEquals(pending,queues())
    }
    @Test fun ownerReplacementClosesPrivateEditorWhileNextSnapshotIsWithheld(){
        channel("Private collectibles");var subject by mutableStateOf(owner)
        val source=object:InvestmentRepository by repo{override fun observeChannelSnapshot(owner:UserId)=if(owner==this@InvestmentChannelScreenTest.owner) repo.observeChannelSnapshot(owner) else emptyFlow()}
        compose.setContent{Screen(subject,source)};await("investment.channel.edit.$id");compose.onNodeWithTag("investment.channel.edit.$id").performScrollTo().performClick();await("investment.channel.name")
        compose.runOnIdle{subject=other};compose.onNodeWithTag("investment.channel.sheet").assertDoesNotExist();compose.onAllNodesWithText("Private collectibles").assertCountEquals(0);compose.onNodeWithTag("investment.channels.add").assertIsNotEnabled()
        Assert.assertTrue(channels(other).isEmpty());Assert.assertTrue(queues(other).values.all{it.isEmpty()})
    }
    @Test fun failedSaveAndSavedStateRestoreKeepTheSameDraftIdentityAndNameForRetry(){
        val ids=mutableListOf<String>();val source=object:InvestmentRepository by repo{override suspend fun saveChannel(owner:UserId,draft:InvestmentChannelDraft,primaryCurrency:String,deviceId:String,now:String):Result<InvestmentChannelRecord>{
            ids.add(draft.id);if(ids.size==1)return Result.failure(IllegalStateException("disk unavailable"));return repo.saveChannel(owner,draft,primaryCurrency,deviceId,now)
        }}
        val restoration=StateRestorationTester(compose);restoration.setContent{Screen(source=source)};add();compose.onNodeWithTag("investment.channel.name").performTextInput("Saved draft");save();await("investment.channel.error")
        restoration.emulateSavedInstanceStateRestore();await("investment.channel.name");compose.onNodeWithTag("investment.channel.name").assertTextContains("Saved draft");compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.channel.save") and isEnabled()).fetchSemanticsNodes().isNotEmpty()};save();awaitClosed()
        Assert.assertEquals(2,ids.size);Assert.assertEquals(ids.first(),ids.last());Assert.assertEquals(ids.first(),channels().single().id);Assert.assertEquals(2,queues().values.sumOf{it.size})
    }
    @Test fun readFailureWhileEditingRetainsDraftAndDisablesSaveUntilSameSourceRetries(){
        channel();val complete=runBlocking{store.investmentChannelSnapshot(owner)};val crash=MutableStateFlow(false);var starts=0
        val source=object:InvestmentRepository by repo{override fun observeChannelSnapshot(owner:UserId):Flow<InvestmentChannelSnapshot> = flow{
            starts++;if(starts==1){emit(complete);crash.first{it};throw IllegalStateException("read failed")}
            emitAll(repo.observeChannelSnapshot(owner))
        }}
        compose.setContent{Screen(source=source)};await("investment.channel.edit.$id");compose.onNodeWithTag("investment.channel.edit.$id").performScrollTo().performClick();compose.onNodeWithTag("investment.channel.name").performTextReplacement("Retained edit")
        val before=channels();val pending=queues();compose.runOnIdle{crash.value=true};await("investment.channel.retry");compose.onNodeWithTag("investment.channel.save").assertIsNotEnabled();compose.onNodeWithTag("investment.channel.name").assertTextContains("Retained edit")
        Assert.assertEquals(before,channels());Assert.assertEquals(pending,queues());compose.onNodeWithTag("investment.channel.retry").performClick()
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.channel.save") and isEnabled()).fetchSemanticsNodes().isNotEmpty()};save();awaitClosed();Assert.assertEquals(JsonPrimitive("Retained edit"),channels().single().payload["name"]);Assert.assertEquals(2,starts)
    }
    @Test fun sourceRenameAfterOpeningCannotOverwriteNewerNameOrBecomeCreate(){
        val original=channel();compose.setContent{Screen()};await("investment.channel.edit.$id");compose.onNodeWithTag("investment.channel.edit.$id").performScrollTo().performClick();compose.onNodeWithTag("investment.channel.name").performTextReplacement("Older edit")
        runBlocking{repo.saveChannel(owner,InvestmentChannelDraft(id,"Newer device name",original),"VND",device,"2026-10-22T00:00:00Z").getOrThrow()}
        await("investment.channel.unavailable");compose.onNodeWithTag("investment.channel.save").assertIsNotEnabled();compose.onNodeWithTag("investment.channel.name").assertTextContains("Older edit")
        Assert.assertEquals(1,channels().size);Assert.assertEquals(JsonPrimitive("Newer device name"),channels().single().payload["name"]);Assert.assertEquals(2,queues().values.sumOf{it.size})
    }
    @Test fun oldNonCancellableSuccessCannotDismissAnotherOwnersNewDraft(){
        val started=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();var subject by mutableStateOf(owner)
        val source=object:InvestmentRepository by repo{override suspend fun saveChannel(owner:UserId,draft:InvestmentChannelDraft,primaryCurrency:String,deviceId:String,now:String):Result<InvestmentChannelRecord> = withContext(NonCancellable){
            started.complete(Unit);release.await();Result.success(InvestmentChannelRecord(draft.id,owner.value,draft.name,"chart.line.uptrend.xyaxis","#9A67FF",0,false,null,now,now,null,0,deviceId))
        }}
        try {
        compose.setContent{Screen(subject,source)};add();compose.onNodeWithTag("investment.channel.name").performTextInput("Old owner draft");save();compose.waitUntil(5000){started.isCompleted}
        compose.runOnIdle{subject=other};add();compose.onNodeWithTag("investment.channel.name").performTextInput("New owner draft");compose.runOnIdle{release.complete(Unit)};compose.waitForIdle()
        compose.onNodeWithTag("investment.channel.name").assertTextContains("New owner draft");compose.onNodeWithTag("investment.channel.save").assertIsEnabled();Assert.assertTrue(channels(other).isEmpty());Assert.assertTrue(queues(other).values.all{it.isEmpty()})
        } finally {release.complete(Unit)}
    }

    @androidx.test.filters.SdkSuppress(minSdkVersion=29)
    @Suppress("DEPRECATION")
    @Test fun editorAndArchiveErrorFollowThreeLanguagesLightDarkAtActual130WithoutWrites(){
        channel("Cards • カード")
        val assetId="33333333-3333-3333-3333-333333333333";val tradeId="55555555-5555-5555-5555-555555555555"
        fun row(entity:CloudEntity,rowId:String,fields:JsonObject)=CloudRecord(entity.table,rowId,owner.value,JsonObject(buildJsonObject{put("id",rowId);put("user_id",owner.value);put("created_at",now);put("occurred_at",now);put("updated_at",now);put("is_archived",false)}+fields),now,null,0)
        val asset=row(CloudEntity.INVESTMENT_ASSET,assetId,buildJsonObject{put("channel_id",id);put("name","Booster box");put("currency_code","VND")})
        val trade=row(CloudEntity.INVESTMENT_TRADE,tradeId,buildJsonObject{put("asset_id",assetId);put("position_quantity_after_decimal_string","1")})
        runBlocking{store.commitMutations(listOf(asset,trade).map{it to PendingMutation(CloudEntity.fromTable(it.entity)!!,it.id,owner.value,MutationKind.UPSERT,it.payload,now,0,device)})}
        val before=runBlocking{store.investmentChannelSnapshot(owner)};val pending=queues()
        var language by mutableStateOf("en");var dark by mutableStateOf(false)
        compose.setContent{
            val density=androidx.compose.ui.platform.LocalDensity.current
            val config=android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),androidx.compose.ui.platform.LocalConfiguration provides config,
                androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)){Screen(dark=dark)}
        }
        fun complete(node:SemanticsNodeInteraction){
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>();node.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
            val layout=layouts.single();Assert.assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
            Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true))
            Assert.assertFalse(layout.didOverflowHeight)
            // Compose rounds intrinsic paragraph widths to integral pixels. Check
            // actual line bounds with only that subpixel rounding allowance.
            for(line in 0 until layout.lineCount){
                Assert.assertFalse(layout.isLineEllipsized(line))
                Assert.assertTrue("${layout.layoutInput.text}: line right=${layout.getLineRight(line)} width=${layout.size.width}",layout.getLineRight(line)<=layout.size.width+1f)
                Assert.assertTrue(layout.getLineLeft(line)>=-1f)
            }
        }
        fun capture(kind:String,node:SemanticsNodeInteraction){
            val bitmap=node.captureToImage().asAndroidBitmap()
            java.io.File(context.getExternalFilesDir(null),"investment-channel-$kind-$language-${if(dark) "dark" else "light"}-font130.png").outputStream().use{Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))}
        }
        val originalResources=linkedMapOf<android.content.res.Resources,android.content.res.Configuration>()
        fun configureWindows(code:String){
            val windows=android.view.inspector.WindowInspector.getGlobalWindowViews()
            val resources=(windows.map{it.context.resources}+context.resources).distinct()
            resources.forEach{resource ->
                originalResources.putIfAbsent(resource,android.content.res.Configuration(resource.configuration))
                resource.updateConfiguration(android.content.res.Configuration(resource.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))},resource.displayMetrics)
            }
            windows.forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}
        }
        try{
        for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)){
            compose.runOnIdle{configureWindows(code);language=code;dark=theme}
            val localized=context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))})
            await("investment.channel.edit.$id");compose.onNodeWithTag("investment.channel.edit.$id").performScrollTo().performClick();await("investment.channel.name")
            compose.runOnIdle{configureWindows(code)}
            val title=compose.onNodeWithText(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_channel_new_title),useUnmergedTree=true)
            title.assertExists();capture("editor",compose.onNodeWithTag("investment.channel.sheet"));complete(title);complete(compose.onNodeWithText(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.common_save),useUnmergedTree=true))
            capture("editor",compose.onNodeWithTag("investment.channel.sheet"));compose.onNodeWithText(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.common_cancel)).performClick();awaitClosed()
            compose.onNodeWithTag("investment.channel.archive.$id").performScrollTo().performClick();compose.onNodeWithTag("investment.channel.confirmArchive").performClick();await("investment.channels.error")
            compose.runOnIdle{configureWindows(code)}
            compose.onNodeWithTag("investment.channels.error").assertTextEquals(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_error_close_positions_before_archive));complete(compose.onNodeWithTag("investment.channels.error"))
            compose.onNodeWithTag("investment.channel.error.dismiss").assertTextEquals(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.common_ok));capture("open-stock-error",compose.onNode(isDialog()))
            compose.onNodeWithTag("investment.channel.error.dismiss").performClick();Assert.assertEquals(before,runBlocking{store.investmentChannelSnapshot(owner)});Assert.assertEquals(pending,queues())
        }
        }finally{compose.runOnIdle{
            originalResources.forEach{(resource,original)->resource.updateConfiguration(original,resource.displayMetrics)}
            android.view.inspector.WindowInspector.getGlobalWindowViews().forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}
        }}
    }

    @Test fun channelOrderUsesCreationInstantWhenSortOrdersMatch(){
        val early=InvestmentChannelRecord(id,owner.value,"Earlier instant","chart.line.uptrend.xyaxis","#9A67FF",0,false,null,"2026-10-21T09:00:00+09:00",now,null,0,device)
        val late=early.copy(id="66666666-6666-6666-6666-666666666666",name="Later instant",createdAt="2026-10-21T01:00:00Z")
        runBlocking{store.commitMutations(listOf(late,early).map{record ->val raw=record.toCloudRecord();raw to PendingMutation(CloudEntity.INVESTMENT_CHANNEL,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,0,device)})}
        val before=runBlocking{store.investmentChannelSnapshot(owner)};val pending=queues()
        compose.setContent{Screen()};await("investment.channel.edit.$id");await("investment.channel.edit."+late.id)
        Assert.assertTrue(compose.onNodeWithText(early.name).fetchSemanticsNode().boundsInRoot.top < compose.onNodeWithText(late.name).fetchSemanticsNode().boundsInRoot.top)
        Assert.assertEquals(before,runBlocking{store.investmentChannelSnapshot(owner)});Assert.assertEquals(pending,queues())
    }

}
