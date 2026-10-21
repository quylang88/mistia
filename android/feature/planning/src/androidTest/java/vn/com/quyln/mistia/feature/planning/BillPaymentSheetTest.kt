package vn.com.quyln.mistia.feature.planning

import androidx.compose.ui.test.*
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.asAndroidBitmap
import kotlinx.serialization.json.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.YearMonth
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.model.*

/** UI-only synthetic callback fixtures; no network or authenticated accounts. */
@RunWith(AndroidJUnit4::class)
class BillPaymentSheetTest {
    private val compose=createComposeRule()
    // Dialog owns its density from the Activity window. Set the actual emulator
    // configuration before launching that Activity, and always restore it.
    @get:Rule val rules=org.junit.rules.RuleChain.outerRule(org.junit.rules.TestRule {base,description ->
        object:org.junit.runners.model.Statement() {
            override fun evaluate() {
                if(description.methodName!="frozenExactAmountRemainsCompleteAtActual130InThreeLanguagesLightDark") {base.evaluate();return}
                val instrumentation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
                fun shell(command:String)=android.os.ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command)).bufferedReader().use {it.readText().trim()}
                val original=shell("settings get system font_scale").takeUnless {it=="null"} ?: "1.0"
                try {
                    shell("settings put system font_scale 1.3")
                    val end=android.os.SystemClock.uptimeMillis()+5000
                    while(instrumentation.targetContext.resources.configuration.fontScale!=1.3f && android.os.SystemClock.uptimeMillis()<end) android.os.SystemClock.sleep(20)
                    assertEquals(1.3f,instrumentation.targetContext.resources.configuration.fontScale,0.0001f)
                    base.evaluate()
                } finally {shell("settings put system font_scale $original")}
            }
        }
    }).around(compose)
    private val owner="11111111-1111-1111-1111-111111111111"
    private val id="22222222-2222-2222-2222-222222222222"
    private val walletId="33333333-3333-3333-3333-333333333333"
    private val now="2026-10-13T00:00:00Z"
    private val month=YearMonth.of(2026,10)
    private fun wallet(currency:String="JPY",walletID:String=walletId)=LedgerWalletRecord.fromCloudRecord(
        WalletDraft(id=walletID,name=currency,kind=WalletKind.CASH,currencyCode=currency).toMutation(UserId(owner),null,id,now).record)
    private fun row(amount:Long?=5000):RecurringBillDueRow {
        val bill=RecurringBillPlanRecord(id,owner,"Internet","wifi",null,amount,10,"recurring",10,null,
            "2026-09-30T15:00:00Z",false,null,false,null,null,1,walletId,"JPY",false,false,null,null,now,now,null,0,id)
        return recurringBillDueRows(UserId(owner),listOf(bill),emptyList(),month,ZoneId.of("Asia/Tokyo")).single()
    }
    @Test fun changedAmountWhileConfirmationIsOpenCannotSubmitTheOldConsent() {
        var current by mutableStateOf(row());val requests=mutableListOf<BillPaymentRequest>()
        compose.setContent {MistiaTheme(darkTheme=false) {BillPaymentSheet(owner,current,month,listOf(wallet()),false,
            onPay={requests+=it;Result.failure(Exception("fixture"))},onUndo={Result.success(Unit)},onDismiss={})}}
        compose.onNodeWithTag("bill.submitPayment").performClick()
        compose.runOnIdle {current=row(6000)}
        compose.onNodeWithTag("bill.confirmPayment").assertIsNotEnabled()
        compose.runOnIdle {assertTrue(requests.isEmpty())}
        compose.onNodeWithText(androidx.test.core.app.ApplicationProvider.getApplicationContext<android.content.Context>().getString(vn.com.quyln.mistia.core.designsystem.R.string.common_cancel)).performClick()
        compose.onNodeWithTag("bill.submitPayment").performClick();compose.onNodeWithTag("bill.confirmPayment").assertIsEnabled().performClick()
        compose.waitUntil(5000) {requests.size==1};assertEquals(6000L,requests.single().amountMinorOverride)
    }
    @Test fun sameMoneyButChangedScheduleInvalidatesFrozenConfirmationWhileAckMetadataDoesNot() {
        var current by mutableStateOf(row());val requests=mutableListOf<BillPaymentRequest>()
        compose.setContent {MistiaTheme(darkTheme=false) {BillPaymentSheet(owner,current,month,listOf(wallet()),false,
            onPay={requests+=it;Result.failure(Exception("fixture"))},onUndo={Result.success(Unit)},onDismiss={})}}
        compose.onNodeWithTag("bill.submitPayment").performClick()
        compose.runOnIdle {current=current.copy(bill=current.bill.copy(dueDay=20,hasExplicitDueDate=true))}
        compose.onNodeWithTag("bill.confirmPayment").assertIsNotEnabled()
        compose.runOnIdle {current=row().copy(bill=row().bill.copy(updatedAt="2026-10-13T00:01:00Z",syncVersion=1))}
        compose.onNodeWithTag("bill.confirmPayment").assertIsEnabled().performClick()
        compose.waitUntil(5000) {requests.size==1};assertEquals(5000L,requests.single().amountMinorOverride)
    }
    @Test fun changedCycleAmountOrCurrencyCannotReuseAnOpenFixedConfirmation() {
        var current by mutableStateOf(row());val requests=mutableListOf<BillPaymentRequest>()
        compose.setContent {MistiaTheme(darkTheme=false) {BillPaymentSheet(owner,current,month,listOf(wallet(),wallet("VND",id)),false,
            onPay={requests+=it;Result.failure(Exception("fixture"))},onUndo={Result.success(Unit)},onDismiss={})}}
        compose.onNodeWithTag("bill.submitPayment").performClick()
        compose.runOnIdle {current=current.copy(amountMinor=6000)}
        compose.onNodeWithTag("bill.confirmPayment").assertIsNotEnabled()
        compose.runOnIdle {current=row().copy(bill=row().bill.copy(currencyCode="VND"))}
        compose.onNodeWithTag("bill.confirmPayment").assertIsNotEnabled()
        compose.runOnIdle {assertTrue(requests.isEmpty())}
    }
    @androidx.test.filters.SdkSuppress(minSdkVersion=29)
    @Suppress("DEPRECATION")
    @Test fun frozenExactAmountRemainsCompleteAtActual130InThreeLanguagesLightDark() {
        val context=androidx.test.core.app.ApplicationProvider.getApplicationContext<android.content.Context>()
        var dark by mutableStateOf(false);var language by mutableStateOf("en");var current by mutableStateOf(row(9007199254740993L))
        val requests=mutableListOf<BillPaymentRequest>()
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            val config=android.content.res.Configuration(context.resources.configuration).apply {setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),
                androidx.compose.ui.platform.LocalConfiguration provides config,
                androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {
                MistiaTheme(darkTheme=dark) {BillPaymentSheet(owner,current,month,listOf(wallet()),false,onPay={requests+=it;Result.failure(Exception())},onUndo={Result.success(Unit)},onDismiss={})}
            }
        }
        compose.onNodeWithTag("bill.submitPayment").performClick()
        compose.runOnIdle {current=row(9007199254740994L)}
        val windows=if(android.os.Build.VERSION.SDK_INT>=29) android.view.inspector.WindowInspector.getGlobalWindowViews() else emptyList()
        val originalResources=windows.map {it.context.resources}.distinct().associateWith {android.content.res.Configuration(it.configuration)}
        try {
        for(code in listOf("en","vi","ja")) for(theme in listOf(false,true)) {
            compose.runOnIdle {
                // Dialog creates a separate Android owner, so configure its actual
                // window resources as well as the host's composition locals.
                originalResources.forEach {(resources,original) ->
                    val config=android.content.res.Configuration(original).apply {setLocale(java.util.Locale.forLanguageTag(code))}
                    resources.updateConfiguration(config,resources.displayMetrics)
                }
                windows.forEach {it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}
                language=code;dark=theme
            }
            compose.onNodeWithTag("bill.confirmPayment").assertIsNotEnabled()
            val localized=context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply {setLocale(java.util.Locale.forLanguageTag(code))})
            compose.onNode(hasText(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.planning_duepayment_pay_bill)) and hasAnyAncestor(hasTestTag("bill.paymentConfirmation"))).assertExists()
            compose.onNodeWithText(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.common_cancel)).assertExists()
            compose.onNodeWithTag("bill.confirmationAmount").assertTextEquals(vn.com.quyln.mistia.core.designsystem.formatMinorUnits(9007199254740993L,"JPY"))
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithTag("bill.confirmationAmount").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
            val layout=layouts.single();assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
            assertEquals(layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true))
            for(line in 0 until layout.lineCount) assertFalse(layout.isLineEllipsized(line))
            val bitmap=compose.onNodeWithTag("bill.paymentConfirmation").captureToImage().asAndroidBitmap()
            java.io.File(context.getExternalFilesDir(null),"bill-stale-confirmation-$code-${if(theme) "dark" else "light"}-font130.png").outputStream().use {
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)
            }
        }
        } finally {
            compose.runOnIdle {
                originalResources.forEach {(resources,original) ->resources.updateConfiguration(original,resources.displayMetrics)}
                windows.forEach {it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}
            }
        }
        assertTrue(requests.isEmpty())
    }
    @Test fun lateNonCancellablePayCannotDismissANewCycleConfirmation()=lateResultCannotDismissNewCycle(false)
    @Test fun lateNonCancellableUndoCannotDismissANewCycleConfirmation()=lateResultCannotDismissNewCycle(true)
    private fun lateResultCannotDismissNewCycle(undo:Boolean) {
        var selectedMonth by mutableStateOf(month);var dismissed by mutableStateOf(false)
        val release=kotlinx.coroutines.CompletableDeferred<Unit>();var started=false;var returned=false
        val saved=SavedBillPayment(LedgerTransactionRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner,buildJsonObject {
            put("id",id);put("user_id",owner);put("amount_minor",5000);put("is_archived",false)
        },now,null,0)),emptyList())
        compose.setContent {MistiaTheme(darkTheme=false) {
            if(!dismissed) key(selectedMonth) {
                val current=recurringBillDueRows(UserId(owner),listOf(row().bill),emptyList(),selectedMonth,ZoneId.of("Asia/Tokyo")).single()
                    .let {if(undo && selectedMonth==month) it.copy(status=DueStatus.PAID,linkedTransactionId=id) else it}
                BillPaymentSheet(owner,current,selectedMonth,listOf(wallet()),undo && selectedMonth==month,
                    onPay={started=true;kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable) {release.await();returned=true;Result.success(saved)}},
                    onUndo={started=true;kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable) {release.await();returned=true;Result.success(Unit)}},
                    onDismiss={dismissed=true})
            }
        }}
        compose.onNodeWithTag("bill.submitPayment").performClick()
        if(!undo) compose.onNodeWithTag("bill.confirmPayment").performClick()
        compose.waitUntil(5000) {started}
        compose.runOnIdle {selectedMonth=month.plusMonths(1)}
        compose.onNodeWithTag("bill.submitPayment").performClick()
        compose.onNodeWithTag("bill.confirmPayment").assertExists()
        compose.runOnIdle {release.complete(Unit)}
        compose.waitUntil(5000) {returned};compose.waitForIdle()
        compose.onNodeWithTag("bill.confirmPayment").assertExists()
        compose.runOnIdle {assertFalse(dismissed)}
    }
    @Test fun exactDisplayedPaymentNeedsConfirmationAndShowsAffordabilityError() {
        val requests=mutableListOf<BillPaymentRequest>()
        compose.setContent {MistiaTheme(darkTheme=false) {BillPaymentSheet(owner,row(9007199254740993L),month,listOf(wallet()),false,
            onPay={requests+=it;Result.failure(TransactionValidationException(TransactionValidationError.INSUFFICIENT_WALLET_BALANCE))},
            onUndo={Result.success(Unit)},onDismiss={})}}
        compose.onNodeWithTag("bill.submitPayment").performClick()
        assertTrue(requests.isEmpty())
        compose.onNodeWithTag("bill.confirmPayment").performClick()
        compose.waitUntil(5000) {requests.size==1}
        assertEquals(9007199254740993L,requests.single().amountMinorOverride)
        assertEquals(month,requests.single().month)
        compose.onNodeWithTag("bill.paymentError").assertExists()
    }
    @Test fun nilAmountCannotSubmitUntilPositiveAndPickerOmitsDifferentCurrency() {
        compose.setContent {MistiaTheme(darkTheme=true) {BillPaymentSheet(owner,row(null),month,
            listOf(wallet(),wallet("VND",id)),false,onPay={Result.failure(Exception())},onUndo={Result.success(Unit)},onDismiss={})}}
        compose.onNodeWithTag("bill.submitPayment").assertIsNotEnabled()
        compose.onNodeWithTag("bill.paymentAmount").performTextReplacement("5000")
        compose.onNodeWithTag("bill.submitPayment").assertIsEnabled()
        compose.onNodeWithTag("bill.paymentWallet").performClick()
        compose.onNodeWithTag("bill.payWallet.$walletId").assertExists()
        compose.onNodeWithTag("bill.payWallet.$id").assertDoesNotExist()
    }
    @Test fun changedFormRequiresDiscard() {
        var dismissed=false
        compose.setContent {MistiaTheme(darkTheme=false) {BillPaymentSheet(owner,row(null),month,listOf(wallet()),false,
            onPay={Result.failure(Exception())},onUndo={Result.success(Unit)},onDismiss={dismissed=true})}}
        compose.onNodeWithTag("bill.paymentAmount").performTextReplacement("500")
        val close=compose.onNodeWithTag("bill.closePayment")
        val beforeScroll=close.fetchSemanticsNode().boundsInRoot
        close.performScrollTo().assertIsDisplayed().performClick()
        assertFalse(dismissed)
        try {
            compose.waitUntil(5000) {compose.onAllNodesWithTag("bill.discardPayment").fetchSemanticsNodes().isNotEmpty()}
        } catch(failure:Throwable) {
            android.util.Log.e("MistiaBillPaymentDiagnostic","Close bounds before scroll=$beforeScroll")
            val roots=compose.onAllNodes(isRoot()).fetchSemanticsNodes()
            for(index in roots.indices) runCatching {android.util.Log.e("MistiaBillPaymentDiagnostic",compose.onAllNodes(isRoot())[index].printToString())}
            val bitmap=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
            bitmap?.let {
                val context=androidx.test.core.app.ApplicationProvider.getApplicationContext<android.content.Context>()
                java.io.File(context.getExternalFilesDir(null),"bill-payment-discard-failure.png").outputStream().use {output -> it.compress(android.graphics.Bitmap.CompressFormat.PNG,100,output)}
                it.recycle()
            }
            throw failure
        }
        compose.onNodeWithTag("bill.discardPayment").assertIsDisplayed().performClick()
        compose.runOnIdle {assertTrue(dismissed)}
    }
    @Test fun paidSheetUsesUndoCallbackAndHidesEditablePaymentFields() {
        var undone=false
        var dismissed=false
        compose.setContent {MistiaTheme(darkTheme=false) {BillPaymentSheet(owner,row().copy(status=DueStatus.PAID,linkedTransactionId=id),month,listOf(wallet()),true,
            onPay={throw IllegalStateException("Wrong callback")},onUndo={undone=true;Result.success(Unit)},onDismiss={dismissed=true})}}
        compose.onNodeWithTag("bill.paymentAmount").assertDoesNotExist()
        compose.onNodeWithTag("bill.paymentWallet").assertDoesNotExist()
        compose.onNodeWithTag("bill.submitPayment").performClick()
        compose.runOnIdle {assertTrue(undone);assertTrue(dismissed)}
    }

}
