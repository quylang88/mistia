package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class BillInvestmentMoneyRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-23T00:00:00Z"
    private val at="2026-10-23T00:01:00Z"
    private val later="2026-10-23T00:02:00Z"
    private val month=YearMonth.of(2026,10)
    private val zone=ZoneId.of("Asia/Tokyo")
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private val catalog=SystemCategoryCatalog.parse("""[{"id":"home","kind":"expense","active":true,"icon":"mistia.category.parent.expense.home_bills","fallbackIcon":"house.fill","color":"#FF8A4C","translations":{"vi":"Nhà","en":"Home","ja":"住まい"},"aliases":[],"children":[{"id":"internet","active":true,"icon":"mistia.category.expense.home_bills.internet","fallbackIcon":"wifi","color":"#5B7BFF","translations":{"vi":"Mạng","en":"Internet","ja":"インターネット"},"aliases":[]}]}]""")
    @Before fun open()=runBlocking<Unit> {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={owner})
        val parent=catalog.definitions.single{it.parentKey==null}.seedRecord(owner,null,device,now)
        val child=catalog.definitions.single{it.parentKey!=null}.seedRecord(owner,parent.id,device,now)
        val wallet=WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=100).toMutation(owner,null,device,now).record
        val bill=RecurringBillDraft("Internet",child.id,70,wallet.id,"JPY",id=id(50),paymentStartDay=1,zoneId=zone).toBillRecord(owner,child,null,device,now).toCloudRecord()
        val posting=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("sync_version",0L);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",60L);put("accounting_amount_minor",60L);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at","2026-10-23T00:00:01Z")
        },now,null,0)
        for(row in listOf(wallet,parent.toCloudRecord(),child.toCloudRecord(),bill,posting))store.commitMutation(row,PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,MutationKind.UPSERT,row.payload,now,row.syncVersion,device))
    }
    @After fun close(){db.close()}
    private suspend fun source():BillMoneySnapshot {
        val records=CloudEntity.entries.associateWith{store.recordsIncludingDeleted(owner,it.table)}
        return BillMoneySnapshot(owner,records.getValue(CloudEntity.RECURRING_BILL_PLAN).single(),month,records,store.billMoneyReceiptTransactionIds(owner))
    }
    private suspend fun queues()=CloudEntity.entries.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
    private fun request(s:BillMoneySnapshot)=BillPaymentRequest(RecordId(s.bill.id),month,RecordId(id(1)),70,expectedBill=RecurringBillPlanRecord.fromCloudRecord(s.bill),
        investment=BillInvestmentOperationContext(TransactionCreationIdentity(id(20),at),"JPY","Adjustment"))
    private fun accepted(s:BillMoneySnapshot):BillInvestmentMoneyOperation.Pay {
        val r=request(s);val review=(runCatching{planBillInvestmentMoney(s,BillInvestmentMoneyOperation.Pay(r),catalog,device,at,zone)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        return BillInvestmentMoneyOperation.Pay(r.copy(investment=r.investment!!.copy(consent=review.consent)))
    }
    @Test fun snapshotAndPayUndoKnownReplayKeepEveryOwnedFinancialRowAndQueueCoherent()=runBlocking {
        var before=source();Assert.assertEquals(before,store.billInvestmentMoneySnapshot(owner,RecordId(id(50)),month))
        val operation=accepted(before);val paid=store.commitBillInvestmentMoney(before,operation,catalog,device,at,zone)
        Assert.assertEquals(3,paid.mutations.size);Assert.assertEquals(70L,paid.payment!!.transaction.amountMinor)
        before=source();val queued=queues();Assert.assertEquals(3,queued.values.flatten().count{it.mutation.modifiedAt==at})
        Assert.assertTrue(store.commitBillInvestmentMoney(before,operation,catalog,device,at,zone).mutations.isEmpty())
        Assert.assertEquals(before,source());Assert.assertEquals(queued,queues())
        val r=BillInvestmentUndoRequest(RecurringBillPlanRecord.fromCloudRecord(before.bill),month,70,id(20),BillInvestmentOperationContext(TransactionCreationIdentity(id(60),later),"JPY","Adjustment"))
        val undo=BillInvestmentMoneyOperation.Undo(r)
        val review=(runCatching{planBillInvestmentMoney(before,undo,catalog,device,later,zone)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        val confirmed=BillInvestmentMoneyOperation.Undo(r.copy(investment=r.investment.copy(consent=review.consent)))
        Assert.assertEquals(3,store.commitBillInvestmentMoney(before,confirmed,catalog,device,later,zone).mutations.size)
        before=source();val undone=queues();Assert.assertTrue(store.commitBillInvestmentMoney(before,confirmed,catalog,device,later,zone).mutations.isEmpty())
        Assert.assertEquals(before,source());Assert.assertEquals(undone,queues())
    }
    @Test fun noFundConsentMeansNoPrimaryOccurrenceOrQueueWrites()=runBlocking {
        val before=source();val queue=queues()
        val error=runCatching{store.commitBillInvestmentMoney(before,BillInvestmentMoneyOperation.Pay(request(before)),catalog,device,at,zone)}.exceptionOrNull()
        Assert.assertTrue(error.toString(),error is InvestmentFundUsageConfirmationRequired);Assert.assertEquals(before,source());Assert.assertEquals(queue,queues())
    }
    @Test fun actualFailureAtLastDerivedQueueRollsBackExpenseAndPaidCycle()=runBlocking {
        val before=source();val queue=queues();val id=investmentLedgerIdentity(id(20),"cash-consumption-booked")
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER bill_fund_queue_abort BEFORE INSERT ON sync_outbox WHEN NEW.record_id = '$id' BEGIN SELECT RAISE(ABORT, 'reject bill derived queue'); END")
        Assert.assertTrue(runCatching{store.commitBillInvestmentMoney(before,accepted(before),catalog,device,at,zone)}.isFailure)
        Assert.assertEquals(before,source());Assert.assertEquals(queue,queues())
    }
    @Test fun actualSourceChangeCannotSpendThePreviouslyReviewedMoney()=runBlocking {
        val before=source();val operation=accepted(before)
        val old=before.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).single();val changed=old.copy(payload=JsonObject(old.payload+("opening_balance_minor" to JsonPrimitive(101L))))
        store.commitMutation(changed,PendingMutation(CloudEntity.LEDGER_WALLET,changed.id,owner.value,MutationKind.UPSERT,changed.payload,now,changed.syncVersion,device))
        val current=source();val queue=queues()
        Assert.assertTrue(runCatching{store.commitBillInvestmentMoney(before,operation,catalog,device,at,zone)}.exceptionOrNull() is IllegalArgumentException)
        Assert.assertEquals(current,source());Assert.assertEquals(queue,queues())
    }
    @Test fun actualRepositoryRequiresConsentAndAnUnsupportedWriterNeverFallsBackToGenericBatches()=runBlocking {
        val before=source();val queue=queues();val repository=OfflineFirstFinanceRepository(store,zone,catalog)
        val error=repository.payRecurringBill(owner,request(before),device,at).exceptionOrNull()
        Assert.assertTrue(error.toString(),error is InvestmentFundUsageConfirmationRequired)
        Assert.assertEquals(before,source());Assert.assertEquals(queue,queues())
        val unsupported=object:LocalStore by store {override suspend fun commitBillInvestmentMoney(expected:BillMoneySnapshot,operation:BillInvestmentMoneyOperation,catalog:SystemCategoryCatalog,deviceId:String,now:String,zone:ZoneId):BillInvestmentMoneyPlan=
            super<LocalStore>.commitBillInvestmentMoney(expected,operation,catalog,deviceId,now,zone)}
        Assert.assertTrue(OfflineFirstFinanceRepository(unsupported,zone,catalog).payRecurringBill(owner,accepted(before).request,device,at).exceptionOrNull() is UnsupportedOperationException)
        Assert.assertEquals(before,source());Assert.assertEquals(queue,queues())
        Assert.assertEquals(id(20),repository.payRecurringBill(owner,accepted(before).request,device,at).getOrThrow().transaction.id)
    }
    @Test fun anOrphanDerivedQueueCannotBeOverwrittenByTheNewBillPayment()=runBlocking {
        var before=source();val operation=accepted(before)
        val planned=planBillInvestmentMoney(before,operation,catalog,device,at,zone)
        val derived=planned.mutations.single{it.first.entity==CloudEntity.INVESTMENT_POSTING.table}
        store.commitMutation(derived.first,derived.second)
        db.openHelper.writableDatabase.execSQL("DELETE FROM cloud_records WHERE owner_user_id = ? AND entity = ? AND record_id = ?",arrayOf(owner.value,derived.first.entity,derived.first.id))
        before=source();val queue=queues()
        Assert.assertTrue(runCatching{store.commitBillInvestmentMoney(before,operation,catalog,device,at,zone)}.exceptionOrNull() is IllegalArgumentException)
        Assert.assertEquals(before,source());Assert.assertEquals(queue,queues())
    }
    @Test fun realRoomObserverNeverSeesAnExpenseWithoutItsDerivedConsumption()=runBlocking {
        val before=source();val started=CompletableDeferred<Unit>()
        val observed=async(start=CoroutineStart.UNDISPATCHED){store.observeInvestmentCashSnapshot(owner).distinctUntilChanged().onEach{started.complete(Unit)}.take(2).toList()}
        withTimeout(5000){started.await()};store.commitBillInvestmentMoney(before,accepted(before),catalog,device,at,zone)
        val values=withTimeout(5000){observed.await()};Assert.assertEquals(2,values.size)
        for(value in values) {
            val primary=value.rows.any{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id(20)}
            val posting=value.rows.any{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.id==investmentLedgerIdentity(id(20),"cash-consumption-booked")}
            Assert.assertEquals(primary,posting)
        }
        Assert.assertTrue(values.last().rows.any{it.id==id(20)})
    }
    @Test fun aManualPaymentCannotInjectAnAutomaticSuccessNotificationAtTheMoneyBoundary()=runBlocking {
        val old=RecurringBillPlanRecord.fromCloudRecord(source().bill);val enabled=old.copy(autoPayEnabled=true,autoPayDay=23,paymentStartDay=23,dueDay=23).toCloudRecord()
        store.commitMutation(enabled,PendingMutation(CloudEntity.RECURRING_BILL_PLAN,enabled.id,owner.value,MutationKind.UPSERT,enabled.payload,now,enabled.syncVersion,device))
        val before=source();val queue=queues();val notifications=store.localNotifications(owner)
        val incoming=AppNotificationRecord(owner.value,"mistia.bill.autopay.success.${before.bill.id}.$month","Automatic payment complete","Paid","billAutoPaymentSucceeded",
            resourceType="bill",resourceId=before.bill.id,createdAt=at,updatedAt=at,source="system",metadata=buildJsonObject{
                put("sourceKind","recurringBill");put("sourceId",before.bill.id);put("dueMonthKey",month.toString());put("currencyCode","JPY");put("linkedPaymentWalletId",id(1))
            })
        Assert.assertTrue(runCatching{store.commitBillInvestmentMoney(before.copy(automaticPaymentNotification=incoming),accepted(before),catalog,device,at,zone)}.isFailure)
        Assert.assertEquals(before,source());Assert.assertEquals(queue,queues());Assert.assertEquals(notifications,store.localNotifications(owner))
    }
    private suspend fun enableAutomatic(amount:Long) {
        val bill=RecurringBillPlanRecord.fromCloudRecord(source().bill).copy(amountMinor=amount,autoPayEnabled=true,autoPayDay=23,paymentStartDay=23,dueDay=23).toCloudRecord()
        store.commitMutation(bill,PendingMutation(CloudEntity.RECURRING_BILL_PLAN,bill.id,owner.value,MutationKind.UPSERT,bill.payload,now,bill.syncVersion,device))
    }
    @Test fun actualAutomaticPaymentUsesOnlyOrdinaryMoneyAndPersistsItsSuccessNotificationAtomically()=runBlocking {
        enableAutomatic(30)
        val repository=OfflineFirstFinanceRepository(store,zone,catalog,automaticBillText={bill,amount->BillAutomaticPaymentText("Auto "+bill.name,"Done","Paid "+amount)},
            billInvestmentSettings={BillInvestmentSettings("JPY","Adjustment")})
        val p=repository.payRecurringBill(owner,BillPaymentRequest(RecordId(id(50)),month,automatic=true),device,at).getOrThrow()
        Assert.assertEquals(30L,p.transaction.amountMinor);Assert.assertEquals("Auto Internet",p.transaction.title)
        Assert.assertEquals(p.transaction.id,DueOccurrenceRecord.fromCloudRecord(source().recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single()).linkedTransactionId)
        Assert.assertEquals(1,source().recordsByEntity.getValue(CloudEntity.INVESTMENT_POSTING).size)
        val notification=store.localNotifications(owner).single();Assert.assertEquals("billAutoPaymentSucceeded",notification.kind)
        Assert.assertEquals("Paid 30",notification.body);Assert.assertEquals(JsonPrimitive(walletId()),notification.metadata!!["linkedPaymentWalletId"])
    }
    private fun walletId()=id(1)
    @Test fun actualAutomaticFundUseIsPausedBeforeAnyMoneyNotificationOrPresentation()=runBlocking {
        enableAutomatic(70);val before=source();val queue=queues();var presentations=0
        val repository=OfflineFirstFinanceRepository(store,zone,catalog,automaticBillText={_,_->presentations++;BillAutomaticPaymentText("Auto","Done","Paid")},
            billInvestmentSettings={BillInvestmentSettings("JPY","Adjustment")})
        val error=repository.payRecurringBill(owner,BillPaymentRequest(RecordId(id(50)),month,automatic=true),device,at).exceptionOrNull()
        Assert.assertEquals(BillPaymentError.INVESTMENT_USAGE_UNAVAILABLE,(error as? BillPaymentException)?.reason)
        Assert.assertEquals(before,source());Assert.assertEquals(queue,queues());Assert.assertTrue(store.localNotifications(owner).isEmpty());Assert.assertEquals(0,presentations)
    }
    @Test fun actualCallerCancellationAtFinalFenceRollsBackAllPaymentEffects()=runBlocking {
        val before=source();val queue=queues();val operation=accepted(before);var checks=0;var target:Job?=null
        val cancelling=RoomLocalStore(db,currentBillOwner={checks++;if(checks==4)target!!.cancel(CancellationException("last bill investment fence"));owner})
        val action=async(start=CoroutineStart.LAZY){cancelling.commitBillInvestmentMoney(before,operation,catalog,device,at,zone)};target=action;action.start()
        Assert.assertTrue(runCatching{action.await()}.exceptionOrNull() is CancellationException);Assert.assertEquals(4,checks)
        Assert.assertEquals(before,source());Assert.assertEquals(queue,queues())
    }
    @Test fun actualOwnerReplacementAtFinalFenceRollsBackAllPaymentEffects()=runBlocking {
        val before=source();val queue=queues();val operation=accepted(before);var checks=0
        val replaced=RoomLocalStore(db,currentBillOwner={checks++;if(checks>=4)UserId(id(99))else owner})
        Assert.assertTrue(runCatching{replaced.commitBillInvestmentMoney(before,operation,catalog,device,at,zone)}.exceptionOrNull() is CancellationException)
        Assert.assertEquals(4,checks);Assert.assertEquals(before,source());Assert.assertEquals(queue,queues())
    }
}
