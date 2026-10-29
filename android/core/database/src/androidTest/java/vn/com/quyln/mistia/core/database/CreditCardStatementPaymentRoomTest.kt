package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.*
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class CreditCardStatementPaymentRoomTest {
    private val context get()=ApplicationProvider.getApplicationContext<Context>()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="44444444-4444-4444-8444-444444444444"
    private val birth="2026-08-01T00:00:00Z"
    private val now="2026-10-22T00:00:02Z"
    private val zone=ZoneId.of("Asia/Tokyo")
    private val month=YearMonth.of(2026,9)
    private fun id(n:Int)=UUID(0,n.toLong()).toString()
    private suspend fun prepare(store:RoomLocalStore,reserve:Long=0):CreditCardStatementPaymentRequest {
        val repo=OfflineFirstFinanceRepository(store,zone)
        val wallet=repo.saveWallet(owner,WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=100),device,birth).getOrThrow()
        val account=repo.saveCreditCard(owner,CreditCardDraft(walletId=id(2),profileId=id(3),name="Card",creditLimitMinor=1000,statementClosingDay=10,paymentDueDay=26,paymentSourceWalletId=wallet.id),device,birth).getOrThrow()
        val parent=repo.saveCategory(owner,CategoryDraft(id=id(30),name="Parent",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,birth).getOrThrow()
        val child=repo.saveCategory(owner,CategoryDraft(id=id(31),name="Child",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,birth).getOrThrow()
        repo.saveTransaction(owner,TransactionDraft(id=id(5),primaryKind=TransactionPrimaryKind.EXPENSE,title="Charge",amountMinor=70,occurredAt="2026-09-12T00:00:00Z",sourceWalletId=account.wallet.id,categoryId=child.id),device,birth).getOrThrow()
        if(reserve>0) {
            val posting=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
                put("id",id(10));put("user_id",owner.value);put("sync_version",0);put("created_at",birth);put("updated_at",birth);put("deleted_at",JsonNull);put("last_modified_by_device_id",device)
                put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",wallet.id);put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
                put("amount_minor",reserve);put("accounting_amount_minor",reserve);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at",birth)
            },birth,null,0)
            store.commitMutation(posting,PendingMutation(CloudEntity.INVESTMENT_POSTING,posting.id,owner.value,MutationKind.UPSERT,posting.payload,birth,0,device))
        }
        val raw=store.transactionInvestmentSaveSnapshot(owner).recordsByEntity
        val statement=creditCardStatementItems(owner,listOf(account),raw.getValue(CloudEntity.LEDGER_TRANSACTION).map(LedgerTransactionRecord::fromCloudRecord),emptyList(),listOf(month),Instant.parse(now),zone,raw.getValue(CloudEntity.TRANSACTION_CATEGORY).map(TransactionCategoryRecord::fromCloudRecord)).single()
        return CreditCardStatementPaymentRequest(statement,BillInvestmentOperationContext(TransactionCreationIdentity(id(20),now),"JPY","Adjustment"),"Pay Card")
    }
    private suspend fun queues(store:RoomLocalStore)=CloudEntity.entries.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE,1000)}
    @Test fun actualRepositoryWritesTransferAndMarkerTogetherAndReplayPreservesEveryQueue()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val r=prepare(store);val before=store.creditCardStatementPaymentSnapshot(owner)
            val repo=OfflineFirstFinanceRepository(store,zone);val saved=repo.payCreditCardStatement(owner,r,device,now).getOrThrow()
            assertEquals(70L,saved.transaction.amountMinor);assertEquals(saved.transaction.id,saved.occurrence.linkedTransactionId)
            val after=store.creditCardStatementPaymentSnapshot(owner);val q=queues(store)
            assertEquals(1,q.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).size)
            assertEquals(before.money.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET),after.money.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET))
            assertEquals(before.money.recordsByEntity.getValue(CloudEntity.CREDIT_CARD_PROFILE),after.money.recordsByEntity.getValue(CloudEntity.CREDIT_CARD_PROFILE))
            assertEquals(saved,repo.payCreditCardStatement(owner,r,device,now).getOrThrow());assertEquals(q,queues(store));assertEquals(after,store.creditCardStatementPaymentSnapshot(owner))
        }finally{db.close()}
    }
    @Test fun fundedPaymentRequiresExactConsentAndPersistsConsumptionWithBothFinancialRows()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val r=prepare(store,60);val repo=OfflineFirstFinanceRepository(store,zone)
            val before=store.creditCardStatementPaymentSnapshot(owner);val queued=queues(store)
            val error=repo.payCreditCardStatement(owner,r,device,now).exceptionOrNull()
            assertTrue(error.toString(),error is InvestmentFundUsageConfirmationRequired)
            assertEquals(before,store.creditCardStatementPaymentSnapshot(owner));assertEquals(queued,queues(store))
            val consent=(error as InvestmentFundUsageConfirmationRequired).review.consent
            val result=repo.payCreditCardStatement(owner,r.copy(context=r.context.copy(consent=consent)),device,now).getOrThrow()
            val posting=store.recordsIncludingDeleted(owner,CloudEntity.INVESTMENT_POSTING.table).single{it.payload.financeRawString("event_id")==result.transaction.id}
            assertEquals(-30L,posting.payload.financeRawLong("amount_minor"));assertEquals("cashConsumption",posting.payload.financeRawString("role_raw_value"))
            assertEquals(result.occurrence.toCloudRecord(),store.record(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table,result.occurrence.id))
        }finally{db.close()}
    }
    @Test fun markerInsertFailureRollsBackTransferPostingAndEveryOutboxWrite()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val r=prepare(store,60);val s=store.creditCardStatementPaymentSnapshot(owner)
            val consent=(runCatching{planCreditCardStatementPayment(s,r,device,now,zone)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review.consent
            val q=queues(store)
            db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_statement BEFORE INSERT ON cloud_records WHEN NEW.entity='due_occurrence_records' BEGIN SELECT RAISE(ABORT,'fixture'); END")
            assertTrue(runCatching{store.commitCreditCardStatementPayment(s,r.copy(context=r.context.copy(consent=consent)),device,now,zone)}.isFailure)
            assertEquals(s,store.creditCardStatementPaymentSnapshot(owner));assertEquals(q,queues(store))
        }finally{db.close()}
    }
    @Test fun changedChargeAfterSnapshotRevokesTheWholeOperation()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val r=prepare(store);val s=store.creditCardStatementPaymentSnapshot(owner)
            val tx=s.money.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).single().let(LedgerTransactionRecord::fromCloudRecord).copy(amountMinor=80,updatedAt=now)
            val row=tx.toCloudRecord();store.commitMutation(row,PendingMutation(CloudEntity.LEDGER_TRANSACTION,row.id,owner.value,MutationKind.UPSERT,row.payload,now,row.syncVersion,device))
            val latest=store.creditCardStatementPaymentSnapshot(owner);val q=queues(store)
            assertTrue(runCatching{store.commitCreditCardStatementPayment(s,r,device,now,zone)}.isFailure)
            assertEquals(latest,store.creditCardStatementPaymentSnapshot(owner));assertEquals(q,queues(store))
        }finally{db.close()}
    }
    @Test fun finalOwnerRotationRollsBackAlreadyPlannedRows()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build();var rotate=false;var checks=0
        try {
            val store=RoomLocalStore(db,currentBillOwner={if(rotate && ++checks>=2)other else owner});val r=prepare(store);val s=store.creditCardStatementPaymentSnapshot(owner);val q=queues(store)
            rotate=true
            val error=runCatching{store.commitCreditCardStatementPayment(s,r,device,now,zone)}.exceptionOrNull();rotate=false
            assertTrue(error is CancellationException);assertEquals(s,store.creditCardStatementPaymentSnapshot(owner));assertEquals(q,queues(store))
        }finally{db.close()}
    }
    @Test fun callerCancellationCannotCommitAnyOfThePaymentGroup()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val r=prepare(store);val s=store.creditCardStatementPaymentSnapshot(owner);val q=queues(store)
            val job=async {currentCoroutineContext().cancel();store.commitCreditCardStatementPayment(s,r,device,now,zone)}
            assertTrue(runCatching{job.await()}.exceptionOrNull() is CancellationException)
            assertEquals(s,store.creditCardStatementPaymentSnapshot(owner));assertEquals(q,queues(store))
        }finally{db.close()}
    }
    @Test fun unsupportedAtomicStoreNeverFallsBackToGenericMutationWrites()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val r=prepare(store);val s=store.creditCardStatementPaymentSnapshot(owner);var generic=0
            val unsupported=object:LocalStore by store {
                override suspend fun commitCreditCardStatementPayment(expected:CreditCardStatementPaymentSnapshot,request:CreditCardStatementPaymentRequest,deviceId:String,now:String,zone:ZoneId):CreditCardStatementPaymentPlan=throw UnsupportedOperationException("atomic unavailable")
                override suspend fun commitMutation(record:CloudRecord,mutation:PendingMutation){generic++}
            }
            val result=OfflineFirstFinanceRepository(unsupported,zone).payCreditCardStatement(owner,r,device,now)
            assertEquals("atomic unavailable",result.exceptionOrNull()?.message);assertEquals(0,generic);assertEquals(s,store.creditCardStatementPaymentSnapshot(owner))
        }finally{db.close()}
    }
    @Test fun diskReopenRetainsExactPaymentAndIdempotentIntent()=runTest {
        val name="statement-payment-"+UUID.randomUUID()+".db";var db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build()
        try {
            var store=RoomLocalStore(db);val r=prepare(store);val saved=OfflineFirstFinanceRepository(store,zone).payCreditCardStatement(owner,r,device,now).getOrThrow();val s=store.creditCardStatementPaymentSnapshot(owner);val q=queues(store)
            db.close();db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build();store=RoomLocalStore(db)
            assertEquals(s,store.creditCardStatementPaymentSnapshot(owner));assertEquals(saved,OfflineFirstFinanceRepository(store,zone).payCreditCardStatement(owner,r,device,now).getOrThrow());assertEquals(q,queues(store))
        }finally{db.close();context.deleteDatabase(name)}
    }
}
