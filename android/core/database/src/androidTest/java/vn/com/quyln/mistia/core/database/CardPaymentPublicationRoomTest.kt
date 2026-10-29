package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.YearMonth
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

/** Real Room publication authority: full dependency snapshots and transactional rollback. */
@RunWith(AndroidJUnit4::class)
class CardPaymentPublicationRoomTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val id = UUID(0,2).toString()
    private val other = "99999999-9999-9999-9999-999999999999"
    private val now = "2026-10-22T00:00:02Z"
    private val later = "2026-10-22T01:00:00Z"
    private val version = 9007199254740995L
    private val birth="2026-08-01T00:00:00Z"
    private val month=YearMonth.of(2026,9)
    private fun id(n:Int)=UUID(0,n.toLong()).toString()
    private suspend fun request(store:RoomLocalStore,reserve:Long=0):CreditCardStatementPaymentRequest {
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
    private suspend fun prepared(store:RoomLocalStore):CardPaymentPublicationSnapshot {
        val r=request(store)
        OfflineFirstFinanceRepository(store,zone).payCreditCardStatement(owner,r,device,now).getOrThrow()
        for(entity in CardPaymentPublicationSnapshot.entities.filter{it!=CloudEntity.DUE_OCCURRENCE_RECORD}) {
            for(q in store.pendingMutations(owner,entity,Long.MAX_VALUE,1000)) {
                val row=requireNotNull(store.record(owner,entity.table,q.mutation.recordId))
                val clean=row.copy(syncVersion=version,payload=JsonObject(row.payload+("sync_version" to JsonPrimitive(version))))
                assertTrue(store.acknowledgeMutation(q,clean))
            }
        }
        return store.cardPaymentPublicationSnapshot(owner,id)
    }
    private fun q(s:CardPaymentPublicationSnapshot)=s.queues.single{it.mutation.entity==CloudEntity.DUE_OCCURRENCE_RECORD && it.mutation.payload?.financeRawString("source_id")==id}
    private fun observed(s:CardPaymentPublicationSnapshot):CardPaymentPublicationObservation {
        val c=s.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single{it.id==q(s).mutation.recordId}
        val saved=c.copy(syncVersion=1,payload=JsonObject(c.payload+("sync_version" to JsonPrimitive(1))))
        val link=requireNotNull(c.payload.financeRawString("linked_transaction_id"))
        return CardPaymentPublicationObservation(listOf(saved),
            s.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).filter{it.id==link}.associateBy{it.id},
            s.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).associateBy{it.id})
    }
    private val zone=ZoneId.of("Asia/Tokyo")
    @Test fun exactActualCycleACKConsumesOnlyItsQueueAndKeepsMoneyAndSource()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val s=prepared(store);val o=observed(s)
            assertTrue(store.acknowledgeCardPaymentPublication(s,q(s),o,zone))
            val current=store.cardPaymentPublicationSnapshot(owner,id)
            assertTrue(current.queues.isEmpty());assertTrue(current.dirtyKeys.isEmpty())
            assertEquals(o.cycles.single(),current.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single())
            assertEquals(s.recordsByEntity.filterKeys{it!=CloudEntity.DUE_OCCURRENCE_RECORD},current.recordsByEntity.filterKeys{it!=CloudEntity.DUE_OCCURRENCE_RECORD})
        }finally{db.close()}
    }
    @Test fun lateMutationOrRetryGenerationRejectsBothOldACKAndFailure()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val s=prepared(store);val o=observed(s)
            assertTrue(store.recordCardPaymentPublicationFailure(s,q(s),123456,"network_io"))
            val current=store.cardPaymentPublicationSnapshot(owner,id)
            assertEquals(1,q(current).attemptCount)
            assertFalse(store.acknowledgeCardPaymentPublication(s,q(s),o,zone))
            assertFalse(store.recordCardPaymentPublicationFailure(s,q(s),123457,"network_io"))
            assertEquals(current,store.cardPaymentPublicationSnapshot(owner,id))
        }finally{db.close()}
    }
    @Test fun lateInvestmentPostingQueueRevokesCapturedCycleAuthority()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val s=prepared(store);val o=observed(s)
            val postId=UUID.randomUUID().toString();val link=o.ledger.keys.single()
            val post=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,postId,owner.value,buildJsonObject{
                put("id",postId);put("user_id",owner.value);put("event_id",link);put("ledger_transaction_id",link)
                put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",0);put("last_modified_by_device_id",device)
            },now,null,0)
            store.commitMutation(post,PendingMutation(CloudEntity.INVESTMENT_POSTING,post.id,owner.value,MutationKind.UPSERT,post.payload,now,0,device))
            val current=store.cardPaymentPublicationSnapshot(owner,id)
            assertFalse(store.acknowledgeCardPaymentPublication(s,q(s),o,zone))
            assertFalse(store.recordCardPaymentPublicationFailure(s,q(s),1,"network_io"))
            assertEquals(current,store.cardPaymentPublicationSnapshot(owner,id))
        }finally{db.close()}
    }
    @Test fun finalSessionRotationRollsBackACKAndFailureWrites()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val s=prepared(store);val o=observed(s)
            for(ack in listOf(true,false)) {
                var checks=0
                val error=runCatching{if(ack)store.acknowledgeCardPaymentPublication(s,q(s),o,zone){++checks<3}
                    else store.recordCardPaymentPublicationFailure(s,q(s),1,"network_io"){++checks<3}}.exceptionOrNull()
                assertTrue(error is CancellationException);assertEquals(s,store.cardPaymentPublicationSnapshot(owner,id))
            }
        }finally{db.close()}
    }
    @Test fun databaseImportFailureRollsBackTheQueueRemoval()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val s=prepared(store)
            db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_installment_publication BEFORE INSERT ON cloud_records WHEN NEW.entity='due_occurrence_records' BEGIN SELECT RAISE(ABORT,'fixture'); END")
            assertTrue(runCatching{store.acknowledgeCardPaymentPublication(s,q(s),observed(s),zone)}.isFailure)
            assertEquals(s,store.cardPaymentPublicationSnapshot(owner,id))
        }finally{db.close()}
    }
    @Test fun fullSnapshotAndACKPreserveMoreThanOneHundredUnrelatedQueues()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val first=prepared(store)
            repeat(127) {i->
                val cycle=DueOccurrenceRecord(UUID.randomUUID().toString(),owner.value,"creditCard",other,"2026-10",now,null,"pending",null,null,now,now,null,0,device)
                store.commitMutation(cycle.toCloudRecord(),cycle.pendingMutation(MutationKind.UPSERT))
            }
            val s=store.cardPaymentPublicationSnapshot(owner,id);assertEquals(128,s.queues.size)
            assertTrue(store.acknowledgeCardPaymentPublication(s,q(s),observed(first),zone))
            val current=store.cardPaymentPublicationSnapshot(owner,id);assertEquals(127,current.queues.size)
            assertEquals(s.queues.filterNot{it==q(s)},current.queues)
        }finally{db.close()}
    }
    @Test fun currentProfileEditRevokesOldACKWithoutLosingTheNewerProfileIntent()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val s=prepared(store);val o=observed(s)
            val old=s.recordsByEntity.getValue(CloudEntity.CREDIT_CARD_PROFILE).single()
            val changed=old.copy(updatedAt=later,payload=JsonObject(old.payload+buildJsonObject{put("payment_due_day",27);put("updated_at",later);put("last_modified_by_device_id",device)}))
            store.commitMutation(changed,PendingMutation(CloudEntity.CREDIT_CARD_PROFILE,changed.id,owner.value,MutationKind.UPSERT,changed.payload,later,changed.syncVersion,device))
            val current=store.cardPaymentPublicationSnapshot(owner,id)
            assertFalse(store.acknowledgeCardPaymentPublication(s,q(s),o,zone))
            assertFalse(store.recordCardPaymentPublicationFailure(s,q(s),1,"network_io"))
            assertEquals(current,store.cardPaymentPublicationSnapshot(owner,id))
            assertTrue(store.acknowledgeCardPaymentPublication(current,q(current),o,zone))
            assertEquals(listOf(changed),store.cardPaymentPublicationSnapshot(owner,id).recordsByEntity.getValue(CloudEntity.CREDIT_CARD_PROFILE))
            assertEquals(1,store.cardPaymentPublicationSnapshot(owner,id).queues.size)
        }finally{db.close()}
    }
    @Test fun actualOwnerRotationAtTheFinalCheckRollsBackACKAndRetry()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        var rotate=false;var checks=0
        try {
            val store=RoomLocalStore(db,currentBillOwner={if(rotate && ++checks>=2)UserId(other) else owner})
            val s=prepared(store);val o=observed(s)
            for(ack in listOf(true,false)) {
                rotate=true;checks=0
                val error=runCatching{if(ack)store.acknowledgeCardPaymentPublication(s,q(s),o,zone)
                    else store.recordCardPaymentPublicationFailure(s,q(s),1,"network_io")}.exceptionOrNull()
                rotate=false
                assertTrue(error is CancellationException);assertEquals(s,store.cardPaymentPublicationSnapshot(owner,id))
            }
        }finally{db.close()}
    }
    @Test fun publicationAuthoritySurvivesDiskReopenAndConsumesOnlyTheSavedGeneration()=runTest {
        val name="installment-publication-"+UUID.randomUUID()+".db"
        var db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build()
        try {
            val s=prepared(RoomLocalStore(db));val o=observed(s);db.close()
            db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build()
            val store=RoomLocalStore(db)
            assertEquals(s,store.cardPaymentPublicationSnapshot(owner,id))
            assertTrue(store.acknowledgeCardPaymentPublication(s,q(s),o,zone))
            assertTrue(store.cardPaymentPublicationSnapshot(owner,id).queues.isEmpty())
        }finally{db.close();context.deleteDatabase(name)}
    }

    @Test fun callerCancellationCannotAcknowledgeOrBookkeepFailure()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val s=prepared(store);val o=observed(s)
            for(ack in listOf(true,false)) {
                val job=async{currentCoroutineContext().cancel();if(ack)store.acknowledgeCardPaymentPublication(s,q(s),o,zone)else store.recordCardPaymentPublicationFailure(s,q(s),1,"network_io")}
                assertTrue(runCatching{job.await()}.exceptionOrNull() is CancellationException)
                assertEquals(s,store.cardPaymentPublicationSnapshot(owner,id))
            }
        }finally{db.close()}
    }
}
