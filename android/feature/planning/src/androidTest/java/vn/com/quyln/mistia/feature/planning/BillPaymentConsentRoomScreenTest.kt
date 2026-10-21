package vn.com.quyln.mistia.feature.planning

import android.content.Context
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.systemCategoryCatalog
import vn.com.quyln.mistia.core.model.*

/** Real repository source change after the user's visible confirmation, before repository read. */
@RunWith(AndroidJUnit4::class)
class BillPaymentConsentRoomScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource(){override fun after(){if(::db.isInitialized) db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private val context=ApplicationProvider.getApplicationContext<Context>()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="22222222-2222-2222-2222-222222222222"
    private val time="2026-10-13T00:00:00Z"
    private val zone=ZoneId.of("Asia/Tokyo")
    private val month=YearMonth.of(2026,10)
    @Test fun changedRoomSourceAfterConfirmationCannotWriteStaleMoneyEvenWhenVisibleRowIsWithheld()=runBlocking<Unit> {
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build()
        val store=RoomLocalStore(db);val catalog=systemCategoryCatalog(context)
        val repo=OfflineFirstFinanceRepository(store,zone,catalog)
        repo.ensureDefaultSystemCategories(owner,catalog,device,time).getOrThrow()
        val category=repo.observeCategories(owner).first().first {it.kind==TransactionCategoryKind.EXPENSE && it.hierarchyRole==CategoryHierarchyRole.CHILD}
        val wallet=repo.saveWallet(owner,WalletDraft(name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=10000),device,time).getOrThrow()
        val visible=repo.saveRecurringBill(owner,RecurringBillDraft("Internet",category.id,5000,wallet.id,"JPY",paymentStartDay=10,zoneId=zone),device,time).getOrThrow()
        val due=recurringBillDueRows(owner,listOf(visible),emptyList(),month,zone).single()
        var error:Throwable?=null;var invoked=false;var intact=false
        compose.setContent {MistiaTheme(darkTheme=false) {BillPaymentSheet(owner.value,due,month,listOf(wallet),false,
            onPay={request ->
                val changed=visible.copy(amountMinor=6000)
                store.commitMutation(changed.toCloudRecord(),changed.pendingMutation())
                val before=CloudEntity.entries.associateWith {store.recordsIncludingDeleted(owner,it.table)}
                val queue=CloudEntity.entries.associateWith {store.pendingMutations(owner,it,Long.MAX_VALUE)}
                val result=repo.payRecurringBill(owner,request,device,time)
                error=result.exceptionOrNull()
                intact=before==CloudEntity.entries.associateWith {store.recordsIncludingDeleted(owner,it.table)} && queue==CloudEntity.entries.associateWith {store.pendingMutations(owner,it,Long.MAX_VALUE)}
                invoked=true;result
            },onUndo={Result.success(Unit)},onDismiss={})}}
        compose.onNodeWithTag("bill.submitPayment").performScrollTo().performClick()
        compose.onNodeWithTag("bill.confirmPayment").performClick()
        compose.waitUntil(5000) {invoked}
        Assert.assertEquals(BillPaymentError.SOURCE_CHANGED,(error as? BillPaymentException)?.reason)
        Assert.assertTrue(intact);Assert.assertTrue(repo.observeTransactions(owner).first().isEmpty())
        Assert.assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
        Assert.assertEquals(6000L,repo.observeRecurringBills(owner).first().single().amountMinor)
        compose.onNodeWithTag("bill.paymentError").assertExists()
    }
}
