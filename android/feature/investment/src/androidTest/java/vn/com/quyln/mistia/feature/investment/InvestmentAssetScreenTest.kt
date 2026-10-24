package vn.com.quyln.mistia.feature.investment

import android.content.Context
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
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
class InvestmentAssetScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(org.junit.rules.TestRule{base,description ->
        object:org.junit.runners.model.Statement(){override fun evaluate(){
            if(description.methodName!="assetEditorAndArchiveErrorRemainCompleteInThreeLanguagesBothThemesAtActual130And320Dp"){base.evaluate();return}
            val instrumentation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
            fun shell(command:String)=android.os.ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command)).bufferedReader().use{it.readText().trim()}
            val originalFont=shell("settings get system font_scale").takeUnless{it=="null"} ?: "1.0"
            val originalSize=Regex("Override size: ([0-9]+x[0-9]+)").find(shell("wm size"))?.groupValues?.get(1)
            val metrics=instrumentation.targetContext.resources.displayMetrics
            val width=kotlin.math.round(320*metrics.density).toInt();val height=metrics.heightPixels
            try{
                shell("wm size "+width+"x"+height);shell("settings put system font_scale 1.3")
                val end=android.os.SystemClock.uptimeMillis()+5000
                while(instrumentation.targetContext.resources.configuration.fontScale!=1.3f && android.os.SystemClock.uptimeMillis()<end)android.os.SystemClock.sleep(20)
                Assert.assertEquals(1.3f,instrumentation.targetContext.resources.configuration.fontScale,0.0001f)
                base.evaluate()
            }finally{
                shell("settings put system font_scale "+originalFont)
                shell(if(originalSize==null)"wm size reset" else "wm size "+originalSize)
            }
        }}
    }).around(object:ExternalResource(){override fun after(){if(::db.isInitialized)db.close()}}).around(compose)
    private val context=ApplicationProvider.getApplicationContext<Context>()
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstInvestmentRepository
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val id="22222222-2222-2222-2222-222222222222"
    private val channel="33333333-3333-3333-3333-333333333333"
    private val device="44444444-4444-4444-4444-444444444444"
    private val now="2026-10-21T00:00:00Z"
    @Before fun setup() {
        val images=FileInvestmentProductImageCache(java.io.File(context.cacheDir,"asset-screen-images-${java.util.UUID.randomUUID()}"),{owner})
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db,productImages=images)
        repo=OfflineFirstInvestmentRepository(store,productImages=images)
        runBlocking{repo.saveChannel(owner,InvestmentChannelDraft(channel,"Cards"),"VND",device,now).getOrThrow()}
    }
    @Composable private fun Screen(subject:UserId=owner,source:InvestmentRepository=repo,dark:Boolean=false) {
        MistiaTheme(darkTheme=dark){Scaffold{padding ->
            InvestmentScreen(subject,source,{},Modifier.padding(padding),primaryCurrencyCode="VND",deviceIdProvider={device},enabledCurrencyCodes=listOf("JPY","VND"))
        }}
    }
    private fun rows(subject:UserId=owner)=runBlocking{store.investmentAssetSnapshot(subject)}
    private fun queues(subject:UserId=owner)=runBlocking{InvestmentAssetSnapshot.entities.associateWith{store.pendingMutations(subject,it,Long.MAX_VALUE)}}
    private fun await(tag:String){compose.waitUntil(5000){
        if(compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty())true
        else if(tag=="investment.assets.add" || tag.startsWith("investment.channels.") ||
            listOf("investment.asset.edit.","investment.asset.archive.","investment.asset.restore.","investment.channel.edit.","investment.channel.archive.","investment.channel.restore.").any(tag::startsWith))
            runCatching{compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag(tag));true}.getOrDefault(false)
        else false
    }}
    private fun add() {
        await("investment.assets.add")
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.assets.add") and isEnabled()).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("investment.assets.add").performScrollTo().performClick();await("investment.asset.name")
    }
    private fun save(){compose.onNodeWithTag("investment.asset.save").performScrollTo().assertIsEnabled().performClick()}
    private fun closed(){compose.waitUntil(5000){compose.onAllNodesWithTag("investment.asset.sheet").fetchSemanticsNodes().isEmpty()}}
    private fun seedAsset(unit:String?="box"):InvestmentAssetRecord {
        val asset=InvestmentAssetRecord(id,owner.value,channel,"Private product","VND","private-preserved.jpg",unit,0,false,null,now,now,null,0,device)
        runBlocking{val raw=asset.toCloudRecord();store.commitMutations(listOf(raw to PendingMutation(CloudEntity.INVESTMENT_ASSET,id,owner.value,MutationKind.UPSERT,raw.payload,now,0,device)))}
        return asset
    }
    @Test fun actualCreateRequiresNameAndUnitThenPersistsNormalizedAssetAndOneQueueWithoutFinancialEffects() {
        val wallets=rows().records(CloudEntity.LEDGER_WALLET);compose.setContent{Screen()};add()
        compose.onNodeWithTag("investment.asset.save").assertIsNotEnabled()
        compose.onNodeWithTag("investment.asset.name").performTextInput(" Product ");compose.onNodeWithTag("investment.asset.save").assertIsNotEnabled()
        compose.onNodeWithTag("investment.asset.unit").performTextInput(" Gift   Box ");save();closed()
        val asset=rows().records(CloudEntity.INVESTMENT_ASSET).single()
        Assert.assertEquals("Product",asset.payload.financeRawString("name"));Assert.assertEquals("Gift Box",asset.payload.financeRawString("default_unit_label"))
        Assert.assertEquals(channel,asset.payload.financeRawString("channel_id"));Assert.assertEquals("VND",asset.payload.financeRawString("currency_code"))
        Assert.assertSame(JsonNull,asset.payload["image_path"]);Assert.assertEquals(wallets,rows().records(CloudEntity.LEDGER_WALLET))
        Assert.assertTrue(rows().records(CloudEntity.LEDGER_TRANSACTION).isEmpty());Assert.assertTrue(rows().records(CloudEntity.INVESTMENT_POSTING).isEmpty())
        Assert.assertEquals(3,queues().values.sumOf{it.size});Assert.assertTrue(rows(other).rows.isEmpty());Assert.assertTrue(queues(other).values.all{it.isEmpty()})
    }
    @Test fun editArchiveAndRestorePreserveSourceIdentityImageAndCreatedMetadata() {
        val original=seedAsset();compose.setContent{Screen()};await("investment.asset.edit.$id")
        compose.onNodeWithTag("investment.asset.edit.$id").performScrollTo().performClick()
        compose.onNodeWithTag("investment.asset.name").performTextReplacement("Updated product");save();closed()
        compose.onNodeWithTag("investment.asset.archive.$id").performScrollTo().performClick();compose.onNodeWithTag("investment.asset.confirmArchive").performClick()
        await("investment.asset.restore.$id");compose.onNodeWithTag("investment.asset.restore.$id").performScrollTo().performClick();await("investment.asset.edit.$id")
        val actual=InvestmentAssetRecord.fromCloudRecord(rows().records(CloudEntity.INVESTMENT_ASSET).single())
        Assert.assertEquals(id,actual.id);Assert.assertEquals(original.createdAt,actual.createdAt);Assert.assertEquals(original.imagePath,actual.imagePath)
        Assert.assertEquals("Updated product",actual.name);Assert.assertFalse(actual.isArchived);Assert.assertNull(actual.archivedAt)
        Assert.assertEquals(3,queues().values.sumOf{it.size});Assert.assertTrue(rows().records(CloudEntity.INVESTMENT_TRADE).isEmpty())
    }
    @Test fun sixEntityReadFailureRetainsDraftAndRetryEnablesTheSameForm() {
        val initial=rows();var starts=0;val crash=MutableStateFlow(false)
        val source=object:InvestmentRepository by repo {
            override fun observeAssetSnapshot(owner:UserId):Flow<InvestmentAssetSnapshot> = flow {
                starts++;if(starts==1){emit(initial);crash.first{it};throw IllegalStateException("read failed")}
                emitAll(repo.observeAssetSnapshot(owner))
            }
        }
        compose.setContent{Screen(source=source)};add();compose.onNodeWithTag("investment.asset.name").performTextInput("Retained product")
        compose.onNodeWithTag("investment.asset.unit").performTextInput("pack");val before=rows();val pending=queues()
        compose.runOnIdle{crash.value=true};await("investment.asset.retry")
        compose.onNodeWithTag("investment.asset.save").assertIsNotEnabled();compose.onNodeWithTag("investment.asset.name").assertTextContains("Retained product")
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        compose.onNodeWithTag("investment.asset.retry").performScrollTo().performClick()
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.asset.save") and isEnabled()).fetchSemanticsNodes().isNotEmpty()}
        save();closed();Assert.assertEquals("Retained product",rows().records(CloudEntity.INVESTMENT_ASSET).single().payload.financeRawString("name"))
        Assert.assertEquals(2,starts);Assert.assertEquals(3,queues().values.sumOf{it.size})
    }
    @Test fun ownerReplacementClearsThePrivateAssetAndEditorWhileNextReadsAreWithheld() {
        seedAsset();var subject by mutableStateOf(owner)
        val source=object:InvestmentRepository by repo {
            override fun observeChannelSnapshot(owner:UserId)=if(owner==this@InvestmentAssetScreenTest.owner)repo.observeChannelSnapshot(owner) else emptyFlow()
            override fun observeAssetSnapshot(owner:UserId)=if(owner==this@InvestmentAssetScreenTest.owner)repo.observeAssetSnapshot(owner) else emptyFlow()
        }
        compose.setContent{Screen(subject,source)};await("investment.asset.edit.$id")
        compose.onNodeWithTag("investment.asset.edit.$id").performScrollTo().performClick();await("investment.asset.name")
        compose.runOnIdle{subject=other}
        compose.onNodeWithTag("investment.asset.sheet").assertDoesNotExist();compose.onAllNodesWithText("Private product").assertCountEquals(0)
        await("investment.assets.add");compose.onNodeWithTag("investment.assets.add").assertIsNotEnabled();Assert.assertTrue(rows(other).rows.isEmpty());Assert.assertTrue(queues(other).values.all{it.isEmpty()})
    }
    @Test fun visibleSourceChangeWhileEditorIsOpenDisablesSaveAndCannotBecomeCreate() {
        val original=seedAsset();compose.setContent{Screen()};await("investment.asset.edit.$id")
        compose.onNodeWithTag("investment.asset.edit.$id").performScrollTo().performClick();compose.onNodeWithTag("investment.asset.name").performTextReplacement("Older draft")
        runBlocking{repo.saveAsset(owner,InvestmentAssetDraft(id,channel,"Newer product","VND","box",original),device,"2026-10-22T00:00:00Z").getOrThrow()}
        await("investment.asset.unavailable");compose.onNodeWithTag("investment.asset.save").assertIsNotEnabled()
        compose.onNodeWithTag("investment.asset.name").assertTextContains("Older draft")
        Assert.assertEquals(1,rows().records(CloudEntity.INVESTMENT_ASSET).size)
        Assert.assertEquals("Newer product",rows().records(CloudEntity.INVESTMENT_ASSET).single().payload.financeRawString("name"))
    }
    private fun historyTrade(tradeId:String,kind:String="buy",gross:Long=100,assetReference:JsonElement=JsonPrimitive(id),unit:String?=null):CloudRecord {
        val p=buildJsonObject {
            put("id",tradeId);put("user_id",owner.value);put("channel_id",channel);put("asset_id",assetReference)
            put("kind_raw_value",kind);put("quantity_decimal_string","1");put("unit_label",unit?.let(::JsonPrimitive) ?: JsonNull)
            put("gross_amount_minor",gross);put("currency_code","VND");put("accounting_gross_amount_minor",gross);put("accounting_currency_code","VND")
            put("funding_wallet_id",if(kind=="buy")JsonPrimitive("88888888-8888-8888-8888-888888888888") else JsonNull)
            put("capital_return_wallet_id",if(kind=="sell")JsonPrimitive("99999999-9999-9999-9999-999999999999") else JsonNull)
            put("funding_wallet_currency_code",if(kind=="buy")JsonPrimitive("VND") else JsonNull)
            put("capital_return_wallet_currency_code",if(kind=="sell")JsonPrimitive("VND") else JsonNull)
            put("funding_wallet_amount_minor",if(kind=="buy")JsonPrimitive(gross) else JsonNull);put("capital_return_wallet_amount_minor",JsonNull)
            for(key in listOf("exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","funding_to_accounting_rate_decimal_string",
                "accounting_to_capital_return_rate_decimal_string","funding_ledger_transaction_id","capital_return_ledger_transaction_id","profit_loss_ledger_transaction_id","note"))put(key,JsonNull)
            put("released_cost_basis_minor",0L);put("realized_profit_loss_minor",0L);put("position_quantity_after_decimal_string","1");put("position_cost_basis_after_minor",gross)
            put("occurred_at",if(kind=="buy")"2026-10-20T00:00:00Z" else now);put("created_at",now);put("updated_at",now)
            put("deleted_at",JsonNull);put("sync_version",0L);put("last_modified_by_device_id",device)
        }
        return CloudRecord(CloudEntity.INVESTMENT_TRADE.table,tradeId,owner.value,p,now,null,0)
    }
    @Test fun knownHistoryCannotHideALaterMissingRequiredAssetReferenceFromEditorConsent() {
        seedAsset();val initial=rows()
        val known=historyTrade("66666666-6666-6666-6666-666666666666",unit="box")
        val unknown=historyTrade("77777777-7777-7777-7777-777777777777",assetReference=JsonNull,unit="box")
        val source=object:InvestmentRepository by repo {
            override fun observeAssetSnapshot(owner:UserId)=flowOf(initial.copy(rows=initial.rows+listOf(known,unknown)))
        }
        val before=rows();val pending=queues();compose.setContent{Screen(source=source)}
        await("investment.asset.edit."+id);compose.onNodeWithTag("investment.asset.edit."+id).performScrollTo().performClick();await("investment.asset.name")
        compose.waitUntil(5000){compose.onAllNodesWithTag("investment.asset.loading").fetchSemanticsNodes().isEmpty()}
        compose.onNodeWithTag("investment.asset.save").assertIsNotEnabled()
        compose.onNodeWithTag("investment.asset.unavailable").assertExists()
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }

    @Test fun declaredOwnerCannotRelabelForeignChannelRowsInsideTheAssetEditor() {
        seedAsset();val initial=rows();val foreignName="Other owner hidden channel"
        val foreign=InvestmentChannelRecord(channel,other.value,foreignName,"chart.line.uptrend.xyaxis","#9A67FF",0,false,null,now,now,null,0,device).toCloudRecord()
        val source=object:InvestmentRepository by repo {
            override fun observeAssetSnapshot(owner:UserId)=flowOf(initial.copy(rows=initial.rows.filterNot{it.entity==CloudEntity.INVESTMENT_CHANNEL.table}+foreign))
        }
        val before=rows();val pending=queues();compose.setContent{Screen(source=source)}
        await("investment.asset.edit."+id);compose.onNodeWithTag("investment.asset.edit."+id).performScrollTo().performClick();await("investment.asset.name")
        compose.waitUntil(5000){compose.onAllNodesWithTag("investment.asset.loading").fetchSemanticsNodes().isEmpty()}
        compose.onAllNodesWithText(foreignName).assertCountEquals(0)
        compose.onNodeWithTag("investment.asset.save").assertIsNotEnabled()
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }

    private fun seed(vararg records:CloudRecord)=runBlocking {
        store.commitMutations(records.map{raw ->raw to PendingMutation(CloudEntity.fromTable(raw.entity)!!,raw.id,owner.value,
            MutationKind.UPSERT,raw.payload,now,raw.syncVersion,device)})
    }
    @Test fun firstLegacyUnitResolutionLocksAccountingControlsAndRebuildsTheActualRoomFinancialBatch() {
        seedAsset(null)
        val wallets=listOf("88888888-8888-8888-8888-888888888888","99999999-9999-9999-9999-999999999999").map {
            WalletDraft(id=it,name="VND",kind=WalletKind.CASH,currencyCode="VND").toMutation(owner,null,device,now).record
        }
        seed(*(wallets+listOf(historyTrade("66666666-6666-6666-6666-666666666666"),historyTrade("77777777-7777-7777-7777-777777777777","sell",150))).toTypedArray())
        val beforeWallets=rows().records(CloudEntity.LEDGER_WALLET)
        compose.setContent{Screen()};await("investment.asset.edit."+id);compose.onNodeWithTag("investment.asset.edit."+id).performScrollTo().performClick()
        await("investment.asset.historyLocked")
        compose.onNodeWithTag("investment.asset.channel").assertIsNotEnabled();compose.onNodeWithTag("investment.asset.currency").assertIsNotEnabled()
        compose.onNodeWithTag("investment.asset.save").assertIsNotEnabled()
        compose.onNodeWithTag("investment.asset.unit").performScrollTo().performTextInput(" Box ");save();closed()
        val snapshot=rows()
        Assert.assertEquals("Box",snapshot.records(CloudEntity.INVESTMENT_ASSET).single().payload.financeRawString("default_unit_label"))
        val sale=snapshot.records(CloudEntity.INVESTMENT_TRADE).single{it.payload.financeRawString("kind_raw_value")=="sell"}
        Assert.assertEquals(100L,sale.payload.financeRawLong("released_cost_basis_minor"));Assert.assertEquals(50L,sale.payload.financeRawLong("realized_profit_loss_minor"))
        Assert.assertEquals("0",sale.payload.financeRawString("position_quantity_after_decimal_string"))
        Assert.assertEquals(3,snapshot.records(CloudEntity.LEDGER_TRANSACTION).size)
        val postings=snapshot.records(CloudEntity.INVESTMENT_POSTING);Assert.assertEquals(4,postings.size)
        Assert.assertEquals(50L,postings.single{it.payload.financeRawString("role_raw_value")=="cashAccrual"}.payload.financeRawLong("amount_minor"))
        Assert.assertEquals(beforeWallets,snapshot.records(CloudEntity.LEDGER_WALLET));Assert.assertEquals(14,queues().values.sumOf{it.size})
    }
    @Test fun positiveStockArchiveUsesTheSourceErrorDialogAndDoesNotWriteAnything() {
        seedAsset();seed(historyTrade("66666666-6666-6666-6666-666666666666",unit="box"))
        val before=rows();val pending=queues();compose.setContent{Screen()};await("investment.asset.archive."+id)
        compose.onNodeWithTag("investment.asset.archive."+id).performScrollTo().performClick();compose.onNodeWithTag("investment.asset.confirmArchive").performClick()
        await("investment.assets.error");compose.onNode(isDialog()).assertExists()
        compose.onNodeWithTag("investment.assets.error").assertTextEquals(context.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_error_close_positions_before_archive))
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun newAssetCanSelectItsOwnedChannelAndOnlyEnabledCurrencyOptions() {
        val second="55555555-5555-5555-5555-555555555555"
        runBlocking{repo.saveChannel(owner,InvestmentChannelDraft(second,"Books"),"VND",device,now).getOrThrow()}
        compose.setContent{Screen()};add()
        compose.onNodeWithTag("investment.asset.channel").performScrollTo().performClick()
        compose.onNodeWithTag("investment.asset.channel.option."+second).performClick()
        compose.onNodeWithTag("investment.asset.name").performTextInput("Book")
        compose.onNodeWithTag("investment.asset.unit").performTextInput("copy")
        compose.onNodeWithTag("investment.asset.currency").performScrollTo().performClick()
        compose.onNodeWithTag("investment.asset.currency.option.JPY").performClick();save();closed()
        val asset=rows().records(CloudEntity.INVESTMENT_ASSET).single()
        Assert.assertEquals(second,asset.payload.financeRawString("channel_id"));Assert.assertEquals("JPY",asset.payload.financeRawString("currency_code"))
        Assert.assertEquals("VND",rows().records(CloudEntity.LEDGER_WALLET).single().payload.financeRawString("currency_code"))
        Assert.assertEquals(4,queues().values.sumOf{it.size})
    }
    @Test fun failedSaveAndSavedStateRestoreKeepTheSameAssetUuidNameUnitAndChannelForRetry() {
        val ids=mutableListOf<String>()
        val source=object:InvestmentRepository by repo {
            override suspend fun saveAsset(owner:UserId,draft:InvestmentAssetDraft,deviceId:String,now:String):Result<InvestmentAssetRecord> {
                ids+=draft.id
                return if(ids.size==1)Result.failure(IllegalStateException("disk unavailable"))else repo.saveAsset(owner,draft,deviceId,now)
            }
        }
        val restoration=StateRestorationTester(compose);restoration.setContent{Screen(source=source)};add()
        compose.onNodeWithTag("investment.asset.name").performTextInput("Retained product");compose.onNodeWithTag("investment.asset.unit").performTextInput("pack")
        save();await("investment.asset.error");restoration.emulateSavedInstanceStateRestore();await("investment.asset.name")
        compose.onNodeWithTag("investment.asset.name").assertTextContains("Retained product");compose.onNodeWithTag("investment.asset.unit").assertTextContains("pack")
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.asset.save") and isEnabled()).fetchSemanticsNodes().isNotEmpty()}
        save();closed();Assert.assertEquals(2,ids.size);Assert.assertEquals(ids.first(),ids.last())
        val asset=rows().records(CloudEntity.INVESTMENT_ASSET).single()
        Assert.assertEquals(ids.first(),asset.id);Assert.assertEquals(channel,asset.payload.financeRawString("channel_id"));Assert.assertEquals(3,queues().values.sumOf{it.size})
    }
    @Test fun oldNonCancellableAssetSuccessCannotDismissAnotherOwnersNewDraft() {
        runBlocking{repo.saveChannel(other,InvestmentChannelDraft("55555555-5555-5555-5555-555555555555","Other channel"),"VND",device,now).getOrThrow()}
        val started=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();var subject by mutableStateOf(owner)
        val source=object:InvestmentRepository by repo {
            override suspend fun saveAsset(owner:UserId,draft:InvestmentAssetDraft,deviceId:String,now:String):Result<InvestmentAssetRecord> = withContext(NonCancellable) {
                started.complete(Unit);release.await()
                Result.success(InvestmentAssetRecord(draft.id,owner.value,draft.channelId,draft.name,draft.currencyCode,null,draft.defaultUnitLabel,0,false,null,now,now,null,0,deviceId))
            }
        }
        try {
            compose.setContent{Screen(subject,source)};add();compose.onNodeWithTag("investment.asset.name").performTextInput("Old draft")
            compose.onNodeWithTag("investment.asset.unit").performTextInput("box");save();compose.waitUntil(5000){started.isCompleted}
            compose.runOnIdle{subject=other};add();compose.onNodeWithTag("investment.asset.name").performTextInput("New owner draft")
            compose.onNodeWithTag("investment.asset.unit").performTextInput("pack");compose.runOnIdle{release.complete(Unit)};compose.waitForIdle()
            compose.onNodeWithTag("investment.asset.name").assertTextContains("New owner draft")
            compose.onNodeWithTag("investment.asset.save").assertIsEnabled();Assert.assertTrue(rows(other).records(CloudEntity.INVESTMENT_ASSET).isEmpty())
        }finally{release.complete(Unit)}
    }

    @androidx.test.filters.SdkSuppress(minSdkVersion=29)
    @Suppress("DEPRECATION")
    @Test fun assetEditorAndArchiveErrorRemainCompleteInThreeLanguagesBothThemesAtActual130And320Dp() {
        val original=seedAsset()
        runBlocking{repo.saveAsset(owner,InvestmentAssetDraft(id,channel,"Cards • カード","VND","box",original),device,now).getOrThrow()}
        seed(historyTrade("66666666-6666-6666-6666-666666666666",unit="box"))
        val before=rows();val pending=queues()
        var language by mutableStateOf("en");var dark by mutableStateOf(false)
        compose.setContent{
            val config=android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),
                androidx.compose.ui.platform.LocalConfiguration provides config){Screen(dark=dark)}
        }
        val originalResources=linkedMapOf<android.content.res.Resources,android.content.res.Configuration>()
        fun configure(code:String) {
            val windows=android.view.inspector.WindowInspector.getGlobalWindowViews()
            (windows.map{it.context.resources}+context.resources).distinct().forEach{resource ->
                originalResources.putIfAbsent(resource,android.content.res.Configuration(resource.configuration))
                resource.updateConfiguration(android.content.res.Configuration(resource.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))},resource.displayMetrics)
            }
            windows.forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}
        }
        fun complete(node:SemanticsNodeInteraction) {
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            node.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
            val layout=layouts.single()
            Assert.assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
            Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true));Assert.assertFalse(layout.didOverflowHeight)
            for(line in 0 until layout.lineCount) {
                Assert.assertFalse(layout.isLineEllipsized(line))
                Assert.assertTrue("Text "+layout.layoutInput.text+" right "+layout.getLineRight(line)+" width "+layout.size.width,layout.getLineRight(line)<=layout.size.width+1f)
                Assert.assertTrue(layout.getLineLeft(line)>=-1f)
            }
        }
        fun capture(kind:String,node:SemanticsNodeInteraction) {
            val bitmap=node.captureToImage().asAndroidBitmap()
            java.io.File(context.getExternalFilesDir(null),"investment-asset-"+kind+"-"+language+"-"+(if(dark)"dark" else "light")+"-font130-width320.png").outputStream().use {
                Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))
            }
        }
        try {
            for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)) {
                compose.runOnIdle{configure(code);language=code;dark=theme}
                val localized=context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))})
                await("investment.asset.edit."+id);compose.onNodeWithTag("investment.asset.edit."+id).performScrollTo().performClick()
                await("investment.asset.historyLocked");compose.runOnIdle{configure(code)}
                val title=compose.onNodeWithText(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_asset_new_title),useUnmergedTree=true)
                title.performScrollTo();complete(title)
                val width=compose.onNodeWithTag("investment.asset.sheet").fetchSemanticsNode().boundsInRoot.width
                Assert.assertEquals((320-40)*context.resources.displayMetrics.density,width,1f)
                complete(compose.onNodeWithText(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.common_save),useUnmergedTree=true))
                capture("editor-top",compose.onNodeWithTag("investment.asset.sheet"))
                compose.onNodeWithTag("investment.asset.unit").performScrollTo()
                complete(compose.onNodeWithText(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_asset_default_unit_placeholder),useUnmergedTree=true))
                compose.onNodeWithTag("investment.asset.historyLocked").performScrollTo().assertIsDisplayed();complete(compose.onNodeWithTag("investment.asset.historyLocked"))
                compose.onNodeWithTag("investment.asset.currency").assertIsNotEnabled();capture("editor-bottom",compose.onNodeWithTag("investment.asset.sheet"))
                compose.onNodeWithText(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.common_cancel)).performScrollTo().performClick();closed()
                compose.onNodeWithTag("investment.asset.archive."+id).performScrollTo().performClick();compose.onNodeWithTag("investment.asset.confirmArchive").performClick();await("investment.assets.error")
                compose.runOnIdle{configure(code)}
                compose.onNodeWithTag("investment.assets.error").assertTextEquals(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_error_close_positions_before_archive))
                complete(compose.onNodeWithTag("investment.assets.error"));capture("open-stock-error",compose.onNode(isDialog()))
                compose.onNodeWithText(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.common_ok)).performClick()
                Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
            }
        }finally{compose.runOnIdle{
            originalResources.forEach{(resource,originalConfig)->resource.updateConfiguration(originalConfig,resource.displayMetrics)}
            android.view.inspector.WindowInspector.getGlobalWindowViews().forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}
        }}
    }

    @Test fun actualNewAssetOffersPhotoLibraryAndCameraWithoutSavingAnEmptyDraft() {
        compose.setContent{Screen()};add()
        compose.onNodeWithTag("investment.asset.image.add").performScrollTo().performClick()
        compose.onNodeWithTag("investment.asset.image.library").assertIsDisplayed()
        compose.onNodeWithTag("investment.asset.image.camera").assertIsDisplayed()
        Assert.assertTrue(rows().records(CloudEntity.INVESTMENT_ASSET).isEmpty())
    }
    @Test fun actualExistingPhotoRemovalIsExplicitAndCancelPreservesTheCurrentReference() {
        seedAsset();compose.setContent{Screen()};await("investment.asset.edit.$id")
        compose.onNodeWithTag("investment.asset.edit.$id").performScrollTo().performClick();await("investment.asset.name")
        compose.onNodeWithTag("investment.asset.image.remove").performScrollTo().performClick()
        compose.onNodeWithText(context.getString(vn.com.quyln.mistia.core.designsystem.R.string.common_cancel)).performScrollTo().performClick();closed()
        Assert.assertEquals("private-preserved.jpg",rows().records(CloudEntity.INVESTMENT_ASSET).single().payload.financeRawString("image_path"))
        await("investment.asset.edit.$id");compose.onNodeWithTag("investment.asset.edit.$id").performScrollTo().performClick();await("investment.asset.name")
        compose.onNodeWithTag("investment.asset.image.remove").performScrollTo().performClick();save();closed()
        Assert.assertSame(JsonNull,rows().records(CloudEntity.INVESTMENT_ASSET).single().payload["image_path"])
        Assert.assertSame(JsonNull,queues().getValue(CloudEntity.INVESTMENT_ASSET).single().mutation.payload!!["image_path"])
    }

}
