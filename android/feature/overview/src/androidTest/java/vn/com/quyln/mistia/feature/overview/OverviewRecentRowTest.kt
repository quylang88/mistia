package vn.com.quyln.mistia.feature.overview

import android.content.Context
import android.content.res.Configuration
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class OverviewRecentRowTest {
    @get:Rule val compose=createComposeRule()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val categoryId="22222222-2222-2222-2222-222222222222"
    private val date=Instant.parse("2026-10-16T12:00:00Z")
    private val zone=ZoneId.of("Asia/Tokyo")
    private fun row(number:Int,kind:String="expense"):OverviewRecentRow {
        val id=UUID(0,number.toLong()).toString();val payload=buildJsonObject {
            put("id",id);put("user_id",owner.value);put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("title","Original $number")
            put("amount_minor",9007199254740993L);put("source_currency_code","VND");put("occurred_at",date.toString());put("created_at",date.toString());put("updated_at",date.toString())
            put("category_id",categoryId);put("transfer_subtype_raw_value","internalTransfer")
        }
        val transaction=LedgerTransactionRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,payload,null,null,0))
        return OverviewRecentRow(transaction,Money(transaction.amountMinor,"VND"))
    }
    @Composable private fun Localized(language:String,content:@Composable ()->Unit) {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val config=Configuration(context.resources.configuration).apply {setLocale(Locale.forLanguageTag(language))}
        val localized=context.createConfigurationContext(config)
        CompositionLocalProvider(LocalContext provides localized,LocalConfiguration provides config) {MistiaTheme(darkTheme=false) {content()}}
    }
    @Test fun originalExactAmountsShowIncomeExpenseAndNeutralSignsWithTheirOwnKindIcons() {
        val records=listOf(row(1),row(2,"income"),row(3,"transfer"));val before=records.map {it.transaction.toPayload()}
        compose.setContent {Localized("en") {Column {records.forEach {OverviewRecentTransactionRow(it,null,date.plusSeconds(60),zone)}}}}
        for((record,prefix) in records.zip(listOf("-","+",""))) {
            compose.onNodeWithText(prefix+formatMinorUnits(record.money.minor,"VND")).assertExists()
            compose.onNodeWithTag("overview.recent.icon.${record.transaction.id}.mistia.flow.${record.transaction.primaryKindWireValue}").assertExists()
        }
        compose.onNodeWithText(date.toString()).assertDoesNotExist();Assert.assertEquals(before,records.map {it.transaction.toPayload()})
    }
    @Test fun relativeLabelsFollowLanguageAndLiveReferenceThenCrossJapanMidnight() {
        var language by mutableStateOf("en");var reference by mutableStateOf(date.plusSeconds(23*60))
        val record=row(1)
        compose.setContent {Localized(language) {OverviewRecentTransactionRow(record,null,reference,zone)}}
        compose.onNodeWithText("23 min ago").assertExists()
        compose.runOnIdle {language="vi"};compose.onNodeWithText("23 phút trước").assertExists()
        compose.runOnIdle {language="ja"};compose.onNodeWithText("23分前").assertExists()
        compose.runOnIdle {language="en";reference=date.plusSeconds(2*3600)};compose.onNodeWithText("2 hr ago").assertExists()
        compose.runOnIdle {reference=Instant.parse("2026-10-16T15:30:00Z")};compose.onNodeWithText("Yesterday").assertExists()
        compose.runOnIdle {reference=date.plusSeconds(3*86400)};compose.onNodeWithText("16/10").assertExists()
        compose.onNodeWithText("-"+formatMinorUnits(record.money.minor,"VND")).assertExists()
    }
    @Test fun ownedCategoryIconIsVisibleAndForeignCategoryCannotOverrideTransactionKind() {
        val record=row(1);var foreign by mutableStateOf(false)
        val category=CategoryDraft(id=categoryId,name="Home",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT,iconSymbolName="mistia.category.home")
            .toMutation(owner,null,null,categoryId,date.toString()).record
        compose.setContent {Localized("en") {OverviewRecentTransactionRow(record,if(foreign) category.copy(ownerUserId=categoryId) else category,date,zone)}}
        compose.onNodeWithTag("overview.recent.icon.${record.transaction.id}.${category.iconSymbolName}").assertExists()
        compose.runOnIdle {foreign=true}
        compose.onNodeWithTag("overview.recent.icon.${record.transaction.id}.${category.iconSymbolName}").assertDoesNotExist()
        compose.onNodeWithTag("overview.recent.icon.${record.transaction.id}.mistia.flow.expense").assertExists()
    }
    @Test fun resumingOverviewRefreshesRelativeTimeFromCurrentClock() {
        val lifecycleOwner=object:androidx.lifecycle.LifecycleOwner {
            val registry=androidx.lifecycle.LifecycleRegistry.createUnsafe(this)
            override val lifecycle:androidx.lifecycle.Lifecycle get()=registry
        }
        lifecycleOwner.registry.currentState=androidx.lifecycle.Lifecycle.State.RESUMED
        var clock=date.plusSeconds(60)
        val record=row(1)
        compose.setContent {Localized("en") {
            CompositionLocalProvider(androidx.lifecycle.compose.LocalLifecycleOwner provides lifecycleOwner) {
                OverviewRecentTransactionRow(record,null,rememberOverviewReferenceTime {clock},zone)
            }
        }}
        compose.onNodeWithText("1 min ago").assertExists()
        compose.runOnIdle {lifecycleOwner.registry.currentState=androidx.lifecycle.Lifecycle.State.STARTED;clock=date.plusSeconds(3600)}
        compose.onNodeWithText("1 min ago").assertExists()
        compose.runOnIdle {lifecycleOwner.registry.currentState=androidx.lifecycle.Lifecycle.State.RESUMED}
        compose.onNodeWithText("1 hr ago").assertExists()
    }
}
