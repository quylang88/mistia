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
class CategoryReferenceRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val old="22222222-2222-2222-2222-222222222222"
    private val target="33333333-3333-3333-3333-333333333333"
    private val device="44444444-4444-4444-4444-444444444444"
    private val child="55555555-5555-5555-5555-555555555555"
    private val now="2026-10-14T00:00:00Z"
    private val version=9007199254740993L
    private fun category(id:String=old)=TransactionCategoryRecord(id,owner.value,"Home","Home","家","expense","house.fill","#123456",false,false,
        null,"parent","parent_expense_home_bills",true,0,false,null,now,now,null,version,device)
    private suspend fun seed(store:LocalStore) {
        val childCategory=category(child).copy(name="User",nameEnglish="User",nameJapanese=null,parentCategoryId=old,hierarchyRoleWireValue="child",systemKey=null,isSystem=false)
        listOf(category(),category(target)).forEach {store.commitMutation(it.toCloudRecord(),it.bootstrapMutation())}
        store.commitCategoryMutation(childCategory.toCloudRecord(),childCategory.bootstrapMutation(),PendingCategoryTranslation(owner.value,child,"User",CategoryNameLanguage.ENGLISH,now,device))
        listOf(CloudEntity.LEDGER_TRANSACTION,CloudEntity.BUDGET_PLAN,CloudEntity.RECURRING_BILL_PLAN).forEach {entity ->
            val deleted=if(entity==CloudEntity.LEDGER_TRANSACTION) now else null
            val record=CloudRecord(entity.table,child,owner.value,buildJsonObject {
                put("id",child);put("user_id",owner.value);put("category_id",old);put("amount_minor",9007199254740995L)
                put("category_id_snapshot","Frozen ID");put("future_metadata",buildJsonObject {put("value",JsonNull)})
                put("sync_version",version);put("updated_at",now);put("deleted_at",deleted?.let(::JsonPrimitive) ?: JsonNull)
            },now,deleted,version)
            store.commitMutation(record,PendingMutation(entity,child,owner.value,if(deleted==null) MutationKind.UPSERT else MutationKind.DELETE,record.payload,now,version,device))
        }
        val ledger=store.pendingMutations(owner,CloudEntity.LEDGER_TRANSACTION,0).single()
        store.recordMutationFailure(ledger,Long.MAX_VALUE,"old_failure")
        val translation=store.pendingCategoryTranslations(owner,0).single()
        store.recordCategoryTranslationFailure(translation,Long.MAX_VALUE,"network_io")
    }
    @Test fun repairReopenRetainsExactVersionsFrozenFieldsAndTranslationRequests()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val name="category-references-${UUID.randomUUID()}.db"
        var db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build()
        try {
            var store:LocalStore=RoomLocalStore(db)
            seed(store)
            val before=store.categoryReferenceSnapshot(owner)
            assertEquals(Long.MAX_VALUE,before.translations.single().nextAttemptAtEpochMillis)
            val oldTask=before.translations.single()
            assertTrue(store.commitCategoryReferenceRepairs(before,old,target,device,now))
            assertFalse(store.discardCategoryTranslation(oldTask))
            assertFalse(store.recordCategoryTranslationFailure(oldTask,Long.MAX_VALUE,"stale"))
            db.close();db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build();store=RoomLocalStore(db)
            val after=store.categoryReferenceSnapshot(owner)
            val plan=planCategoryReferenceRepairs(before,old,target,device,now)
            plan.mutations.forEach {change ->
                assertEquals(change.record,store.record(owner,change.record.entity,change.record.id))
                assertEquals(change.mutation,after.pending.single {it.mutation.entity.table==change.record.entity && it.mutation.recordId==change.record.id}.mutation)
            }
            assertEquals("Frozen ID",after.records.getValue(CloudEntity.BUDGET_PLAN).single().payload["category_id_snapshot"]!!.jsonPrimitive.content)
            assertEquals(plan.translations.single(),after.translations.single().translation)
            assertEquals(0,after.translations.single().attemptCount)
            assertTrue(store.categoryReferenceSnapshot(UserId(device)).pending.isEmpty())
            assertNotNull(store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,old)) // Identity removal is a separate operation.
        } finally {db.close();context.deleteDatabase(name)}
    }
    @Test fun dependentOutboxFailureRollsBackAllReferencesAndTranslationChanges()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);seed(store)
            val before=store.categoryReferenceSnapshot(owner)
            db.openHelper.writableDatabase.execSQL("""CREATE TRIGGER reject_category_repair BEFORE INSERT ON sync_outbox
                WHEN NEW.entity='budget_plans' BEGIN SELECT RAISE(ABORT,'simulated outbox failure'); END""")
            assertTrue(runCatching {store.commitCategoryReferenceRepairs(before,old,target,device,now)}.isFailure)
            assertEquals(before,store.categoryReferenceSnapshot(owner))
        } finally {db.close()}
    }
    @Test fun staleDependentEditOrRetryCannotBeOverwrittenByRepair()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);seed(store)
            val before=store.categoryReferenceSnapshot(owner)
            val current=store.record(owner,CloudEntity.BUDGET_PLAN.table,child)!!
            val edited=current.copy(payload=JsonObject(current.payload+("future_metadata" to JsonPrimitive("new user edit"))))
            store.commitMutation(edited,PendingMutation(CloudEntity.BUDGET_PLAN,child,owner.value,MutationKind.UPSERT,edited.payload,now,version,device))
            assertFalse(store.commitCategoryReferenceRepairs(before,old,target,device,now))
            assertEquals(edited,store.record(owner,CloudEntity.BUDGET_PLAN.table,child))
            val fresh=store.categoryReferenceSnapshot(owner)
            val queued=fresh.pending.first()
            store.recordMutationFailure(queued,Long.MAX_VALUE,"new_failure")
            assertFalse(store.commitCategoryReferenceRepairs(fresh,old,target,device,now))
        } finally {db.close()}
    }
}
