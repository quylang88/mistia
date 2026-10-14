package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class SystemCategoryIdentityRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="22222222-2222-2222-2222-222222222222"
    private val legacy="33333333-3333-3333-3333-333333333333"
    private val child="44444444-4444-4444-4444-444444444444"
    private val now="2026-10-14T00:00:00Z"
    private val catalog=SystemCategoryCatalog.parse("""[
        {"id":"home","kind":"expense","active":true,"icon":"house.fill","fallbackIcon":"house.fill","color":"#123456",
        "translations":{"vi":"Nhà","en":"Home","ja":"家"},"aliases":[],"children":[]}
    ]""")
    private val seed=catalog.activeDefinitions.single().seedRecord(owner,null,device,now)
    private fun remote(id:String=legacy)=seed.copy(id=id,name="Cloud custom",iconColorHex="#ABCDEF",syncVersion=9007199254740993L,
        createdAt="2020-01-01T00:00:00Z",updatedAt="2020-01-02T00:00:00Z").toCloudRecord()
    private suspend fun seed(store:LocalStore,edited:Boolean=false) {
        val local=if(edited) seed.copy(nameEnglish="User English",updatedAt="2026-10-14T01:00:00Z") else seed
        val task=PendingCategoryTranslation(owner.value,seed.id,"User English",CategoryNameLanguage.ENGLISH,local.updatedAt,device)
        if(edited) store.commitCategoryMutation(local.toCloudRecord(),local.bootstrapMutation(),task)
        else store.commitMutation(local.toCloudRecord(),local.bootstrapMutation())
        val custom=seed.copy(id=child,name="User child",nameEnglish="User child",nameJapanese=null,systemKey=null,isSystem=false,
            parentCategoryId=seed.id,hierarchyRoleWireValue="child",syncVersion=23)
        store.commitCategoryMutation(custom.toCloudRecord(),custom.bootstrapMutation(),task.copy(categoryId=child,inputName="User child",savedUpdatedAt=now))
        listOf(CloudEntity.LEDGER_TRANSACTION,CloudEntity.BUDGET_PLAN,CloudEntity.RECURRING_BILL_PLAN).forEach {entity ->
            val row=CloudRecord(entity.table,child,owner.value,buildJsonObject {
                put("id",child);put("user_id",owner.value);put("category_id",seed.id);put("category_name_snapshot","Frozen name")
                put("amount_minor",9007199254740995L);put("future_metadata",buildJsonObject {put("nullable",JsonNull)})
                put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",9007199254740993L)
            },now,null,9007199254740993L)
            store.commitMutation(row,PendingMutation(entity,child,owner.value,MutationKind.UPSERT,row.payload,now,row.syncVersion,device))
        }
    }
    private fun source(snapshot:CategoryReferenceSnapshot)=snapshot.pending.single {it.mutation.entity==CloudEntity.TRANSACTION_CATEGORY && it.mutation.recordId==seed.id}

    @Test fun adoptReopenMovesReferencesAndKeepsExactVersionsAndPendingTranslation()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val name="category-identity-${UUID.randomUUID()}.db"
        var db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build()
        try {
            var store:LocalStore=RoomLocalStore(db);seed(store,true)
            val before=store.categoryReferenceSnapshot(owner)
            val oldTask=before.translations.single {it.translation.categoryId==seed.id}
            assertTrue(store.commitSystemCategoryIdentityMigration(before,source(before),listOf(remote()),catalog,device,now))
            db.close();db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build();store=RoomLocalStore(db)
            assertNull(store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,seed.id))
            val target=store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,legacy)!!
            assertEquals("Cloud custom",target.payload["name"]!!.jsonPrimitive.content)
            assertEquals("User English",target.payload["name_english"]!!.jsonPrimitive.content)
            assertEquals(9007199254740993L,target.syncVersion)
            val after=store.categoryReferenceSnapshot(owner)
            val queued=after.pending.single {it.mutation.recordId==legacy}
            assertEquals(target.payload,queued.mutation.payload)
            assertEquals(9007199254740993L,queued.mutation.baseVersion)
            assertTrue(after.pending.none {it.mutation.recordId==seed.id})
            assertEquals("User English",after.translations.single {it.translation.categoryId==legacy}.translation.inputName)
            assertFalse(store.discardCategoryTranslation(oldTask))
            assertFalse(store.recordCategoryTranslationFailure(oldTask,Long.MAX_VALUE,"stale"))
            val ledger=store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,child)!!
            assertEquals(legacy,ledger.payload["category_id"]!!.jsonPrimitive.content)
            assertEquals(9007199254740995L,ledger.payload["amount_minor"]!!.jsonPrimitive.long)
            assertEquals("Frozen name",ledger.payload["category_name_snapshot"]!!.jsonPrimitive.content)
            assertEquals(legacy,store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,child)!!.payload["parent_category_id"]!!.jsonPrimitive.content)
            assertTrue(store.categoryReferenceSnapshot(UserId(device)).pending.isEmpty())
        } finally {db.close();context.deleteDatabase(name)}
    }
    @Test fun zeroVersionRemoteProvenanceSurvivesReopenAndSubsequentEdits()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val name="category-provenance-${UUID.randomUUID()}.db"
        var db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build()
        try {
            var store:LocalStore=RoomLocalStore(db);seed(store,true)
            val before=store.categoryReferenceSnapshot(owner)
            val target=TransactionCategoryRecord.fromCloudRecord(remote()).copy(syncVersion=0).toCloudRecord()
            assertTrue(store.commitSystemCategoryIdentityMigration(before,source(before),listOf(target),catalog,device,now))
            db.close();db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build();store=RoomLocalStore(db)
            val queued=store.pendingMutations(owner,CloudEntity.TRANSACTION_CATEGORY,Long.MAX_VALUE).single {it.mutation.recordId==legacy}
            assertTrue(queued.remoteIdentityObserved)
            assertEquals(0L,queued.mutation.baseVersion)
            val installed=store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,legacy)!!
            assertFalse(store.acknowledgeMutation(queued.copy(remoteIdentityObserved=false),installed))
            assertFalse(store.recordMutationFailure(queued.copy(remoteIdentityObserved=false),Long.MAX_VALUE,"old_unknown_provenance"))
            val edited=TransactionCategoryRecord.fromCloudRecord(store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,legacy)!!).copy(name="After reopen")
            store.commitMutation(edited.toCloudRecord(),edited.bootstrapMutation())
            assertTrue(store.pendingMutations(owner,CloudEntity.TRANSACTION_CATEGORY,Long.MAX_VALUE).single {it.mutation.recordId==legacy}.remoteIdentityObserved)
            assertFalse(store.acknowledgeMutation(queued.copy(remoteIdentityObserved=false),edited.toCloudRecord()))
            assertFalse(store.recordMutationFailure(queued.copy(remoteIdentityObserved=false),Long.MAX_VALUE,"old_unknown_provenance"))
        } finally {db.close();context.deleteDatabase(name)}
    }

    @Test fun editOfCleanPulledZeroVersionRowRecordsObservedProvenance()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db)
            val pulled=TransactionCategoryRecord.fromCloudRecord(remote()).copy(syncVersion=0)
            store.replacePullSnapshot(owner,CloudEntity.TRANSACTION_CATEGORY.table,listOf(pulled.toCloudRecord()))
            val edited=pulled.copy(name="User edit")
            store.commitMutation(edited.toCloudRecord(),edited.bootstrapMutation())
            val queued=store.pendingMutations(owner,CloudEntity.TRANSACTION_CATEGORY,Long.MAX_VALUE).single()
            assertTrue(queued.remoteIdentityObserved)
            assertEquals(0L,queued.mutation.baseVersion)
            assertFalse(queued.mutation.payload!!.containsKey("remote_identity_observed"))
        } finally {db.close()}
    }

    @Test fun failureAfterIdentityRemovalRollsBackSourceTargetOutboxReferencesAndTasks()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);seed(store,true)
            val before=store.categoryReferenceSnapshot(owner)
            db.openHelper.writableDatabase.execSQL("""CREATE TRIGGER reject_identity_repair BEFORE INSERT ON sync_outbox
                WHEN NEW.entity='budget_plans' BEGIN SELECT RAISE(ABORT,'simulated outbox failure'); END""")
            assertTrue(runCatching {store.commitSystemCategoryIdentityMigration(before,source(before),listOf(remote()),catalog,device,now)}.isFailure)
            assertEquals(before,store.categoryReferenceSnapshot(owner))
            assertNull(store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,legacy))
        } finally {db.close()}
    }
    @Test fun staleSourceAndLateAcknowledgementCannotEraseNewLocalEdits()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);seed(store)
            val before=store.categoryReferenceSnapshot(owner)
            val changed=seed.copy(nameEnglish="Newer English")
            store.commitMutation(changed.toCloudRecord(),changed.bootstrapMutation())
            assertFalse(store.commitSystemCategoryIdentityMigration(before,source(before),listOf(remote()),catalog,device,now))
            assertEquals(changed.toCloudRecord(),store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,seed.id))
            val fresh=store.categoryReferenceSnapshot(owner)
            val sent=source(fresh)
            assertTrue(store.commitSystemCategoryIdentityMigration(fresh,sent,listOf(remote()),catalog,device,now))
            assertFalse(store.acknowledgeMutation(sent,seed.copy(syncVersion=1).toCloudRecord()))
            assertFalse(store.recordMutationFailure(sent,Long.MAX_VALUE,"old_failure"))
            assertNotNull(store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,legacy))
        } finally {db.close()}
    }
    @Test fun untouchedRemoteTombstoneAndSameIdentityAdoptionDoNotInventMutations()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        for(sameId in listOf(false,true)) {
            val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
            try {
                val store=RoomLocalStore(db);seed(store)
                val before=store.categoryReferenceSnapshot(owner)
                val target=TransactionCategoryRecord.fromCloudRecord(remote(if(sameId) seed.id else legacy)).copy(deletedAt=now).toCloudRecord()
                assertTrue(store.commitSystemCategoryIdentityMigration(before,source(before),listOf(target),catalog,device,now))
                assertEquals(target,store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,target.id))
                assertTrue(store.categoryReferenceSnapshot(owner).pending.none {it.mutation.recordId in setOf(seed.id,target.id)})
            } finally {db.close()}
        }
    }
}
