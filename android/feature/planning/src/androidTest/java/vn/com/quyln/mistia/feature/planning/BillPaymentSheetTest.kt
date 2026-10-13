package vn.com.quyln.mistia.feature.planning

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
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
    @get:Rule val compose=createComposeRule()
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
        compose.onNodeWithTag("bill.closePayment").performClick()
        assertFalse(dismissed)
        compose.onNodeWithTag("bill.discardPayment").performClick()
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
