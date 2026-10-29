package vn.com.quyln.mistia.feature.management

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.*
import java.util.UUID
import kotlinx.coroutines.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

/** Real route, repository and Room; no fabricated successful financial callback. */
@RunWith(AndroidJUnit4::class)
class CreditCardStatementPaymentScreenTest {
    @get:Rule val compose=createComposeRule()
    private val context get()=ApplicationProvider.getApplicationContext<Context>()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="44444444-4444-4444-8444-444444444444"
    private val birth="2026-08-01T00:00:00Z"
    private val now="2026-10-22T00:00:02Z"
    private val zone=ZoneId.systemDefault()
    private fun id(n:Int)=UUID(0,n.toLong()).toString()
    @Volatile private var activeOwner=owner
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    @Before fun setup()=runBlocking {
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={activeOwner});repo=OfflineFirstFinanceRepository(store,zone)
        repo.saveWallet(owner,WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=100),device,birth).getOrThrow()
        repo.saveCreditCard(owner,CreditCardDraft(walletId=id(2),profileId=id(3),name="Card",creditLimitMinor=1000,statementClosingDay=10,paymentDueDay=26,paymentSourceWalletId=id(1)),device,birth).getOrThrow()
        val parent=repo.saveCategory(owner,CategoryDraft(id=id(30),name="Parent",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,birth).getOrThrow()
        val child=repo.saveCategory(owner,CategoryDraft(id=id(31),name="Child",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,birth).getOrThrow()
        repo.saveTransaction(owner,TransactionDraft(id=id(5),primaryKind=TransactionPrimaryKind.EXPENSE,title="Charge",amountMinor=70,occurredAt="2026-09-12T00:00:00Z",sourceWalletId=id(2),categoryId=child.id),device,birth).getOrThrow()
        Unit
    }
    @After fun close(){db.close()}
    private fun fund()=runBlocking {
        val row=vn.com.quyln.mistia.core.model.CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,kotlinx.serialization.json.buildJsonObject {
            put("id",kotlinx.serialization.json.JsonPrimitive(id(10)));put("user_id",kotlinx.serialization.json.JsonPrimitive(owner.value));put("sync_version",kotlinx.serialization.json.JsonPrimitive(0));put("created_at",kotlinx.serialization.json.JsonPrimitive(birth));put("updated_at",kotlinx.serialization.json.JsonPrimitive(birth));put("deleted_at",kotlinx.serialization.json.JsonNull);put("last_modified_by_device_id",kotlinx.serialization.json.JsonPrimitive(device))
            for((key,value) in mapOf("event_id" to id(11),"ledger_transaction_id" to id(11),"wallet_id" to id(1),"role_raw_value" to "cashAccrual","cash_bucket_raw_value" to "booked","cash_origin_raw_value" to "derived","currency_code" to "JPY","accounting_currency_code" to "JPY","occurred_at" to birth))put(key,kotlinx.serialization.json.JsonPrimitive(value))
            put("amount_minor",kotlinx.serialization.json.JsonPrimitive(60));put("accounting_amount_minor",kotlinx.serialization.json.JsonPrimitive(60))
        },birth,null,0)
        store.commitMutation(row,PendingMutation(CloudEntity.INVESTMENT_POSTING,row.id,owner.value,MutationKind.UPSERT,row.payload,birth,0,device))
    }
    private fun open(repository:FinanceRepository=repo,subject:()->UserId={owner},restoration:StateRestorationTester?=null) {
        val ui:@Composable ()->Unit={MistiaTheme(darkTheme=false){CreditCardStatementScreen(subject(),id(2),repository,onBack={},deviceIdProvider={device},primaryCurrencyCode="JPY",referenceProvider={Instant.parse(now)})}}
        if(restoration==null)compose.setContent(ui) else restoration.setContent(ui)
        compose.waitUntil(5000){runCatching{compose.onAllNodesWithTag("statement.previousMonth").fetchSemanticsNodes().isNotEmpty()}.getOrDefault(false)}
        compose.onNodeWithTag("statement.previousMonth").performClick()
        compose.onNodeWithTag("statement.status.payable").assertExists()
    }
    private fun pay() {compose.onNodeWithText(context.getString(R.string.management_managementcreditcardstatement_pay_now)).performScrollTo().assertIsEnabled().performClick()}
    private fun review() {
        compose.waitUntil(5000){runCatching{compose.onAllNodesWithTag("statement.funds.review").fetchSemanticsNodes().isNotEmpty()}.getOrDefault(false)}
        compose.onNodeWithTag("statement.funds.review").assertExists()
    }
    private fun message(resource:Int) {
        val expected=context.getString(resource)
        compose.waitUntil(5000){runCatching{compose.onAllNodesWithText(expected).fetchSemanticsNodes().isNotEmpty()}.getOrDefault(false)}
        compose.onNodeWithText(expected).assertExists()
    }
    private fun payments()=runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_TRANSACTION.table).filter{it.payload.financeRawString("destination_wallet_id")==id(2) && it.deletedAt==null}}
    @Test fun payNowCommitsActualTransferAndOwnedCycleThenShowsPaidSuccess() {
        val before=runBlocking{store.creditCardStatementPaymentSnapshot(owner)}
        open();assertTrue(payments().isEmpty());pay()
        compose.waitUntil(5000){payments().size==1}
        message(R.string.management_managementcreditcardstatement_statement_paid)
        val p=payments().single();assertEquals(70L,p.payload.financeRawLong("amount_minor"))
        val cycle=runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table).single()}
        assertEquals(owner.value,cycle.ownerUserId);assertEquals(p.id,cycle.payload.financeRawString("linked_transaction_id"));assertEquals("2026-09",cycle.payload.financeRawString("selected_month_key"))
        assertEquals(before.money.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET),runBlocking{store.creditCardStatementPaymentSnapshot(owner)}.money.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET))
    }
    @Test fun fundedPayRequiresExplicitReviewAndCommitsThirtyMinorConsumption() {
        fund();open();pay();review();assertTrue(payments().isEmpty())
        compose.onNodeWithTag("statement.funds.confirm").performClick();compose.waitUntil(5000){payments().size==1}
        val p=payments().single();val posting=runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.INVESTMENT_POSTING.table).single{it.payload.financeRawString("event_id")==p.id}}
        assertEquals(-30L,posting.payload.financeRawLong("amount_minor"));assertEquals("cashConsumption",posting.payload.financeRawString("role_raw_value"))
    }
    @Test fun cancelFundReviewLeavesEveryFinancialRowAndQueueUntouched() {
        fund();val before=runBlocking{store.creditCardStatementPaymentSnapshot(owner)}
        open();pay();review();compose.onNodeWithTag("statement.funds.cancel").performClick()
        assertEquals(before,runBlocking{store.creditCardStatementPaymentSnapshot(owner)});assertTrue(payments().isEmpty())
    }
    @Test fun legacyForeignLinkedWalletShowsCurrencyErrorWithoutPaying() {
        runBlocking{repo.saveWallet(owner,WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=100),device,now).getOrThrow()}
        open();pay()
        message(R.string.management_managementcreditcardstatement_currency_mismatch)
        assertTrue(payments().isEmpty());assertTrue(runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table).isEmpty()})
    }
    @Test fun changedLinkedWalletRevokesTheOpenFundReview() {
        fund();open();pay();review()
        runBlocking{
            repo.saveWallet(owner,WalletDraft(id=id(8),name="Other cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=100),device,now).getOrThrow()
            repo.saveCreditCard(owner,CreditCardDraft(walletId=id(2),profileId=id(3),name="Card",creditLimitMinor=1000,statementClosingDay=10,paymentDueDay=26,paymentSourceWalletId=id(8)),device,now).getOrThrow()
        }
        compose.waitUntil(5000){compose.onAllNodesWithTag("statement.funds.review").fetchSemanticsNodes().isEmpty()}
        message(R.string.management_managementcreditcardstatement_payment_changed);assertTrue(payments().isEmpty())
    }
    @Test fun ownerRotationCancelsAPendingPaymentAndCannotShowSuccess() {
        var selected by mutableStateOf(owner);val entered=CompletableDeferred<Unit>();val gate=CompletableDeferred<Unit>();val cancelled=CompletableDeferred<Unit>()
        var calls=0
        val delayed=object:FinanceRepository by repo {
            override suspend fun payCreditCardStatement(owner:UserId,request:CreditCardStatementPaymentRequest,deviceId:String,now:String):Result<SavedCreditCardStatementPayment> {
                calls++;entered.complete(Unit)
                try{gate.await();return repo.payCreditCardStatement(owner,request,deviceId,now)}finally{cancelled.complete(Unit)}
            }
        }
        open(delayed,{selected});pay();compose.waitUntil(5000){entered.isCompleted}
        compose.onNodeWithText(context.getString(R.string.management_managementcreditcardstatement_pay_now)).assertIsNotEnabled()
        compose.runOnIdle{activeOwner=other;selected=other}
        compose.waitUntil(5000){cancelled.isCompleted};assertEquals(1,calls);assertTrue(payments().isEmpty())
        compose.onNodeWithText(context.getString(R.string.management_managementcreditcardstatement_statement_paid)).assertDoesNotExist()
    }
    @Test fun restoredStatementKeepsMonthButDiscardsUnconfirmedFundConsent() {
        fund();val restoration=StateRestorationTester(compose)
        open(restoration=restoration);pay();review();assertTrue(payments().isEmpty())
        restoration.emulateSavedInstanceStateRestore()
        compose.waitUntil(5000){runCatching{compose.onAllNodesWithTag("statement.pay").fetchSemanticsNodes().isNotEmpty()}.getOrDefault(false)}
        compose.onNodeWithTag("statement.funds.review").assertDoesNotExist();compose.onNodeWithTag("statement.status.payable").assertExists()
        assertTrue(payments().isEmpty());pay();review();assertTrue(payments().isEmpty())
    }
    @Test fun missingLinkedWalletThenInsufficientBalanceRemainActionableWithoutPaymentWrites() {
        runBlocking{repo.saveCreditCard(owner,CreditCardDraft(walletId=id(2),profileId=id(3),name="Card",creditLimitMinor=1000,statementClosingDay=10,paymentDueDay=26,paymentSourceWalletId=null),device,now).getOrThrow()}
        val failure=java.util.concurrent.atomic.AtomicReference<Throwable?>()
        val observed=object:FinanceRepository by repo {
            override suspend fun payCreditCardStatement(owner:UserId,request:CreditCardStatementPaymentRequest,deviceId:String,now:String):Result<SavedCreditCardStatementPayment> =
                repo.payCreditCardStatement(owner,request,deviceId,now).also{failure.set(it.exceptionOrNull())}
        }
        open(observed);pay()
        compose.waitUntil(5000){failure.get()!=null}
        assertEquals(CreditCardStatementPaymentError.MISSING_LINKED_WALLET,(failure.get() as? CreditCardStatementPaymentException)?.reason)
        message(R.string.management_managementcreditcardstatement_please_set_a_linked_payment_wallet_for)
        assertTrue(payments().isEmpty());compose.onNodeWithTag("statement.payment.close").performClick()
        runBlocking{
            repo.saveCreditCard(owner,CreditCardDraft(walletId=id(2),profileId=id(3),name="Card",creditLimitMinor=1000,statementClosingDay=10,paymentDueDay=26,paymentSourceWalletId=id(1)),device,now).getOrThrow()
            repo.saveTransaction(owner,TransactionDraft(id=id(6),primaryKind=TransactionPrimaryKind.EXPENSE,title="Cash spending",amountMinor=40,occurredAt=now,sourceWalletId=id(1),categoryId=id(31)),device,now).getOrThrow()
        }
        val total=vn.com.quyln.mistia.core.designsystem.formatMinorUnits(70,"JPY")
        compose.waitUntil(5000){runCatching{compose.onAllNodesWithText(total).fetchSemanticsNodes().isNotEmpty() && compose.onAllNodesWithText("Cash").fetchSemanticsNodes().isNotEmpty()}.getOrDefault(false)}
        val before=runBlocking{store.creditCardStatementPaymentSnapshot(owner)}
        pay();message(R.string.management_managementcreditcardstatement_the_linked_wallet_balance_is_not_enough)
        assertTrue(payments().isEmpty());assertEquals(before,runBlocking{store.creditCardStatementPaymentSnapshot(owner)})
    }

}
