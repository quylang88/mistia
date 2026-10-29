package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.YearMonth
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

/** Real Room publication authority: full dependency snapshots and transactional rollback. */
@RunWith(AndroidJUnit4::class)
class InstallmentPaymentPublicationRoomTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val id = "33333333-3333-3333-3333-333333333333"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val now = "2026-10-15T00:00:00Z"
    private val later = "2026-10-15T01:00:00Z"
    private val version = 9007199254740995L
    private suspend fun prepare(store: RoomLocalStore): Triple<InstallmentPaymentAcknowledgementSnapshot, QueuedMutation, CloudRecord> {
        val catalog = SystemCategoryCatalog.parse(context.assets.open("MistiaSystemCategories.json").bufferedReader().use { it.readText() })
        val repo = OfflineFirstFinanceRepository(store, ZoneId.of("Asia/Tokyo"), catalog)
        val wallet = repo.saveWallet(owner, WalletDraft(name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY", openingBalanceMinor = 9007199254740993), device, now).getOrThrow()
        val plan = repo.saveInstallment(owner, InstallmentDraft(id, "Loan", 9007199254740993, 15, 1, 12, wallet.id, "JPY"), device, now).getOrThrow()
        val saved = repo.payInstallment(owner, InstallmentPaymentRequest(plan, YearMonth.of(2026, 10)), device, now).getOrThrow()
        for (entity in listOf(CloudEntity.TRANSACTION_CATEGORY, CloudEntity.LEDGER_WALLET, CloudEntity.INSTALLMENT_PLAN, CloudEntity.LEDGER_TRANSACTION)) {
            for (q in store.pendingMutations(owner, entity, Long.MAX_VALUE)) {
                val current = store.record(owner, entity.table, q.mutation.recordId)!!
                val remote = current.copy(syncVersion = version, payload = JsonObject(current.payload + ("sync_version" to JsonPrimitive(version))))
                assertTrue(store.acknowledgeMutation(q, remote))
            }
        }
        val snapshot = store.installmentPaymentAcknowledgementSnapshot(owner, id)
        val remote = saved.occurrences.single().copy(updatedAt = later, syncVersion = version + 1).toCloudRecord()
        return Triple(snapshot, snapshot.queues.single(), remote)
    }
    private suspend fun prepared(store:RoomLocalStore):InstallmentPaymentPublicationSnapshot {
        prepare(store);return store.installmentPaymentPublicationSnapshot(owner,id)
    }
    private fun q(s:InstallmentPaymentPublicationSnapshot)=s.base.queues.single{it.mutation.entity==CloudEntity.DUE_OCCURRENCE_RECORD && it.mutation.payload?.financeRawString("source_id")==id}
    private fun observed(s:InstallmentPaymentPublicationSnapshot):InstallmentPaymentPublicationObservation {
        val c=s.base.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single{it.id==q(s).mutation.recordId}
        val saved=c.copy(syncVersion=1,payload=JsonObject(c.payload+("sync_version" to JsonPrimitive(1))))
        return InstallmentPaymentPublicationObservation(s.base.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).single(),listOf(saved),
            s.base.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).associateBy{it.id},s.base.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).associateBy{it.id})
    }
    private val zone=ZoneId.of("Asia/Tokyo")
    @Test fun exactActualCycleACKConsumesOnlyItsQueueAndKeepsMoneyAndSource()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val s=prepared(store);val o=observed(s)
            assertTrue(store.acknowledgeInstallmentPaymentPublication(s,q(s),o,zone))
            val current=store.installmentPaymentPublicationSnapshot(owner,id)
            assertTrue(current.base.queues.isEmpty());assertTrue(current.dirtyKeys.isEmpty())
            assertEquals(o.cycles.single(),current.base.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single())
            assertEquals(s.base.recordsByEntity.filterKeys{it!=CloudEntity.DUE_OCCURRENCE_RECORD},current.base.recordsByEntity.filterKeys{it!=CloudEntity.DUE_OCCURRENCE_RECORD})
            assertEquals(s.postings,current.postings)
        }finally{db.close()}
    }
    @Test fun lateMutationOrRetryGenerationRejectsBothOldACKAndFailure()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val s=prepared(store);val o=observed(s)
            assertTrue(store.recordInstallmentPaymentPublicationFailure(s,q(s),123456,"network_io"))
            val current=store.installmentPaymentPublicationSnapshot(owner,id)
            assertEquals(1,q(current).attemptCount)
            assertFalse(store.acknowledgeInstallmentPaymentPublication(s,q(s),o,zone))
            assertFalse(store.recordInstallmentPaymentPublicationFailure(s,q(s),123457,"network_io"))
            assertEquals(current,store.installmentPaymentPublicationSnapshot(owner,id))
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
            val current=store.installmentPaymentPublicationSnapshot(owner,id)
            assertFalse(store.acknowledgeInstallmentPaymentPublication(s,q(s),o,zone))
            assertFalse(store.recordInstallmentPaymentPublicationFailure(s,q(s),1,"network_io"))
            assertEquals(current,store.installmentPaymentPublicationSnapshot(owner,id))
        }finally{db.close()}
    }
    @Test fun finalSessionRotationRollsBackACKAndFailureWrites()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val s=prepared(store);val o=observed(s)
            for(ack in listOf(true,false)) {
                var checks=0
                val error=runCatching{if(ack)store.acknowledgeInstallmentPaymentPublication(s,q(s),o,zone){++checks<3}
                    else store.recordInstallmentPaymentPublicationFailure(s,q(s),1,"network_io"){++checks<3}}.exceptionOrNull()
                assertTrue(error is CancellationException);assertEquals(s,store.installmentPaymentPublicationSnapshot(owner,id))
            }
        }finally{db.close()}
    }
    @Test fun databaseImportFailureRollsBackTheQueueRemoval()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val s=prepared(store)
            db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_installment_publication BEFORE INSERT ON cloud_records WHEN NEW.entity='due_occurrence_records' BEGIN SELECT RAISE(ABORT,'fixture'); END")
            assertTrue(runCatching{store.acknowledgeInstallmentPaymentPublication(s,q(s),observed(s),zone)}.isFailure)
            assertEquals(s,store.installmentPaymentPublicationSnapshot(owner,id))
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
            val s=store.installmentPaymentPublicationSnapshot(owner,id);assertEquals(128,s.base.queues.size)
            assertTrue(store.acknowledgeInstallmentPaymentPublication(s,q(s),observed(first),zone))
            val current=store.installmentPaymentPublicationSnapshot(owner,id);assertEquals(127,current.base.queues.size)
            assertEquals(s.base.queues.filterNot{it==q(s)},current.base.queues)
        }finally{db.close()}
    }
    @Test fun sourceDeletionBatchCannotBeLostByAnOldCycleAcknowledgement()=runTest {
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val s=prepared(store);val o=observed(s)
            val plan=InstallmentPlanRecord.fromCloudRecord(s.base.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).single())
            OfflineFirstFinanceRepository(store).deleteInstallment(owner,plan,device,later).getOrThrow()
            val current=store.installmentPaymentPublicationSnapshot(owner,id);assertNotNull(current.base.batch)
            assertFalse(store.acknowledgeInstallmentPaymentPublication(s,q(s),o,zone))
            assertFalse(store.recordInstallmentPaymentPublicationFailure(s,q(s),1,"network_io"))
            assertEquals(current,store.installmentPaymentPublicationSnapshot(owner,id))
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
                val error=runCatching{if(ack)store.acknowledgeInstallmentPaymentPublication(s,q(s),o,zone)
                    else store.recordInstallmentPaymentPublicationFailure(s,q(s),1,"network_io")}.exceptionOrNull()
                rotate=false
                assertTrue(error is CancellationException);assertEquals(s,store.installmentPaymentPublicationSnapshot(owner,id))
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
            assertEquals(s,store.installmentPaymentPublicationSnapshot(owner,id))
            assertTrue(store.acknowledgeInstallmentPaymentPublication(s,q(s),o,zone))
            assertTrue(store.installmentPaymentPublicationSnapshot(owner,id).base.queues.isEmpty())
        }finally{db.close();context.deleteDatabase(name)}
    }

}
