package vn.com.quyln.mistia.feature.overview

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class OverviewRecentScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource() {override fun after() {if(::db.isInitialized) db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="22222222-2222-2222-2222-222222222222"
    private val time="2026-10-16T00:00:00Z"
    private val sync=MutableStateFlow<SyncStatus>(SyncStatus.Idle)
    private fun id(number:Int)=UUID(0,number.toLong()).toString()
    @Before fun setup() {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)
    }
    private fun row(number:Int,title:String="Row $number",subject:UserId=owner,occurred:String=time)=CloudRecord(
        CloudEntity.LEDGER_TRANSACTION.table,id(number),subject.value,buildJsonObject {
            put("id",id(number));put("user_id",subject.value);put("primary_kind_raw_value","expense");put("entry_status_raw_value","posted")
            put("title",title);put("amount_minor",9007199254740993L);put("source_currency_code","VND")
            put("occurred_at",occurred);put("created_at",occurred);put("updated_at",time);put("is_archived",false)
        },time,null,0)
    private fun CloudRecord.with(vararg fields:Pair<String,JsonElement>)=copy(payload=JsonObject(payload+fields.toMap()))
    private fun seed(raw:CloudRecord)=runBlocking {store.commitMutation(raw,PendingMutation(CloudEntity.LEDGER_TRANSACTION,raw.id,raw.ownerUserId,MutationKind.UPSERT,raw.payload,time,0,device))}
    @Composable private fun Screen(subject:UserId=owner,repository:FinanceRepository=repo,primary:String="JPY",dark:Boolean=false) {MistiaTheme(darkTheme=dark) {androidx.compose.material3.Scaffold {padding ->
        OverviewScreen(subject,repository,sync,modifier=androidx.compose.ui.Modifier.padding(padding),primaryCurrencyCode=primary)
    }}}
    private fun rows(subject:UserId=owner)=runBlocking {repo.observe(CloudEntity.LEDGER_TRANSACTION,subject).first()}
    private fun queue(subject:UserId=owner)=runBlocking {store.pendingMutations(subject,CloudEntity.LEDGER_TRANSACTION,Long.MAX_VALUE)}
    @Test fun recentRowsFilterHiddenDomainStatusAndKeepOnlyFiveInOccurredOrderWithoutWrites() {
        (1..7).forEach {seed(row(it,occurred="2026-10-${10+it}T00:00:00Z"))}
        seed(row(20,"Archived").with("is_archived" to JsonPrimitive(true)))
        seed(row(21,"Draft").with("entry_status_raw_value" to JsonPrimitive("draft")))
        seed(row(22,"Investment").with("settlement_role_raw_value" to JsonPrimitive("investmentFunding")))
        seed(row(23,"Malformed").with("amount_minor" to JsonPrimitive("broken")))
        seed(row(24,"Deleted").with("deleted_at" to JsonPrimitive(time)).copy(deletedAt=time))
        val before=rows();val pending=queue()
        compose.setContent {Screen()}
        compose.waitUntil(5000) {compose.onAllNodesWithText("Row 7").fetchSemanticsNodes().isNotEmpty()}
        for(title in listOf("Archived","Draft","Investment","Malformed","Deleted","Row 1","Row 2")) compose.onNodeWithText(title).assertDoesNotExist()
        val positions=(7 downTo 3).map {number -> compose.onNodeWithTag("overview.recent.${id(number)}").fetchSemanticsNode().boundsInRoot.top}
        Assert.assertEquals(positions.sorted(),positions)
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queue())
    }
    @Test fun foreignAndMismatchedRawEnvelopeNeverExposePrivateTitlesOrMoney() {
        val mixed=MutableStateFlow(listOf(row(1,"Public"),row(2,"Private",other),row(3,"Wrong payload").with("user_id" to JsonPrimitive(other.value)),row(4,"Wrong ID").with("id" to JsonPrimitive(id(99)))))
        val source=object:FinanceRepository by repo {
            override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(entity==CloudEntity.LEDGER_TRANSACTION) mixed else repo.observe(entity,ownerUserId)
        }
        compose.setContent {Screen(repository=source)}
        compose.onNodeWithText("Public").assertExists()
        for(title in listOf("Private","Wrong payload","Wrong ID")) compose.onNodeWithText(title).assertDoesNotExist()
        Assert.assertTrue(rows().isEmpty());Assert.assertTrue(queue().isEmpty())
    }
    @Test fun legacyMissingSourceCurrencyUsesCurrentPrimaryWithoutReportingOrDestinationRelabeling() {
        seed(row(1,"Legacy").with("source_currency_code" to JsonNull,"reporting_currency_code" to JsonPrimitive("USD"),"reporting_amount_minor" to JsonPrimitive(1),"destination_currency_code" to JsonPrimitive("JPY")))
        compose.setContent {Screen(primary=" vnd ")}
        compose.onNodeWithText(formatMinorUnits(9007199254740993L,"VND"),substring=true).assertExists()
        Assert.assertEquals(9007199254740993L,(rows().single().payload["amount_minor"] as JsonPrimitive).long)
    }
    @Test fun ownedSourceWalletCurrencyWinsWhileReportingPairNeverChangesOriginalMoney() {
        val wallet=runBlocking {repo.saveWallet(owner,WalletDraft(name="Cash VND",kind=WalletKind.CASH,currencyCode="VND"),device,time).getOrThrow()}
        seed(row(1,"Source").with("source_currency_code" to JsonNull,"source_wallet_id" to JsonPrimitive(wallet.id),"reporting_currency_code" to JsonPrimitive("JPY"),"reporting_amount_minor" to JsonPrimitive(1)))
        val before=rows();val pending=queue()
        compose.setContent {Screen()}
        compose.onNodeWithText(formatMinorUnits(9007199254740993L,"VND"),substring=true).assertExists()
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queue())
    }
    @Test fun ownerSwitchClearsPriorRowsAndCountsWhileReplacementFlowsHaveNotEmitted() {
        var subject by mutableStateOf(owner)
        val source=object:FinanceRepository by repo {
            override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = when {
                entity!=CloudEntity.LEDGER_TRANSACTION -> repo.observe(entity,ownerUserId)
                ownerUserId==owner -> MutableStateFlow(listOf(row(1,"Private old owner")))
                else -> emptyFlow()
            }
            override fun observeEntityCounts(ownerUserId:UserId):Flow<List<EntityCount>> = if(ownerUserId==owner) MutableStateFlow(listOf(EntityCount(CloudEntity.LEDGER_WALLET.table,12345))) else emptyFlow()
        }
        compose.setContent {Screen(subject,source)}
        compose.onNodeWithText("Private old owner").assertExists();compose.onNodeWithText("12345").assertExists()
        compose.runOnIdle {subject=other}
        compose.onNodeWithText("Private old owner").assertDoesNotExist();compose.onNodeWithText("12345").assertDoesNotExist()
        Assert.assertTrue(rows().isEmpty());Assert.assertTrue(rows(other).isEmpty())
    }
    @Test fun originalRecentMoneyRendersUnbrokenLightDarkAtFont130() {
        seed(row(1,"Exact VND"));seed(row(2,"Exact JPY",occurred="2026-10-15T00:00:00Z").with("source_currency_code" to JsonPrimitive("JPY")))
        val before=rows();val pending=queue();var dark by mutableStateOf(false)
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen(primary="VND",dark=dark)}
        }
        for(theme in listOf("light","dark")) {
            compose.runOnIdle {dark=theme=="dark"}
            for(code in listOf("VND","JPY")) {
                val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                compose.onNodeWithText("-"+formatMinorUnits(9007199254740993L,code)).performScrollTo()
                    .performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
                val layout=layouts.single()
                Assert.assertEquals("$code line count",1,layout.lineCount)
                Assert.assertFalse("$code ellipsis",layout.isLineEllipsized(0))
                Assert.assertEquals("$code complete text",layout.layoutInput.text.length,layout.getLineEnd(0,visibleEnd=true))
                for(index in layout.layoutInput.text.indices) {
                    val glyph=layout.getBoundingBox(index)
                    Assert.assertTrue("$code glyph $index outside $glyph in ${layout.size}",
                        glyph.left>=-1f && glyph.right<=layout.size.width+1f && glyph.top>=-1f && glyph.bottom<=layout.size.height+1f)
                }
            }
            capture("overview-recent-$theme-font130.png")
        }
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queue())
    }
    private fun capture(name:String) {
        compose.waitForIdle()
        val automation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline=android.os.SystemClock.uptimeMillis()+5000
        var previous:android.graphics.Bitmap?=null
        var stableFrames=0
        var stable:android.graphics.Bitmap?=null
        while(android.os.SystemClock.uptimeMillis()<deadline) {
            val frame=checkNotNull(automation.takeScreenshot())
            stableFrames=if(previous?.sameAs(frame)==true) stableFrames+1 else 0
            previous?.recycle();previous=frame
            if(stableFrames>=3) {stable=frame;break}
        }
        if(stable==null) previous?.recycle()
        val bitmap=checkNotNull(stable) {"Screenshot did not reach stable compositor frames: $name"}
        java.io.File(ApplicationProvider.getApplicationContext<Context>().getExternalFilesDir(null),name).outputStream().use {Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))}
        bitmap.recycle()
    }
}
