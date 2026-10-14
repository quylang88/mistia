package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class CategoryReferenceRepairsTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val old="22222222-2222-2222-2222-222222222222"
    private val target="33333333-3333-3333-3333-333333333333"
    private val device="44444444-4444-4444-4444-444444444444"
    private val child="55555555-5555-5555-5555-555555555555"
    private val other="99999999-9999-9999-9999-999999999999"
    private val now="2026-10-14T00:00:00Z"
    private val version=9007199254740993L
    private fun category(id:String=old)=TransactionCategoryRecord(id,owner.value,"Home","Home","家","expense","house.fill","#123456",false,false,
        null,"parent","parent_expense_home_bills",true,0,false,null,now,now,null,version,device).toCloudRecord()
    private fun reference(entity:CloudEntity,deleted:Boolean=false)=CloudRecord(entity.table,child,owner.value,buildJsonObject {
        put("id",child);put("user_id",owner.value)
        put(if(entity==CloudEntity.TRANSACTION_CATEGORY) "parent_category_id" else "category_id",old)
        put("amount_minor",9007199254740995L);put("category_id_snapshot","Frozen ID")
        put("future_metadata",buildJsonObject {put("preserve",JsonNull)})
        put("sync_version",version);put("updated_at",now);put("deleted_at",if(deleted) JsonPrimitive(now) else JsonNull)
    },now,if(deleted) now else null,version)
    private fun queued(row:CloudRecord)=QueuedMutation(PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,
        if(row.deletedAt==null) MutationKind.UPSERT else MutationKind.DELETE,row.payload,now,row.syncVersion,device),2,Long.MAX_VALUE,"old_failure")
    private fun snapshot():CategoryReferenceSnapshot {
        val records=categoryReferenceEntities.associateWith { entity ->
            if(entity==CloudEntity.TRANSACTION_CATEGORY) listOf(category(),category(target),reference(entity)) else listOf(reference(entity,entity==CloudEntity.LEDGER_TRANSACTION))
        }
        val pending=records.values.flatten().filter {it.id==child}.map(::queued)
        val translation=QueuedCategoryTranslation(PendingCategoryTranslation(owner.value,child,"User name",CategoryNameLanguage.ENGLISH,now,device),2,Long.MAX_VALUE,"network_io")
        return CategoryReferenceSnapshot(owner,records,pending,listOf(translation))
    }
    @Test fun `all four references preserve pending versions kinds frozen fields and raw JSON`() {
        val snapshot=snapshot()
        val plan=planCategoryReferenceRepairs(snapshot,old,target,device,now)
        assertEquals(4,plan.mutations.size)
        plan.mutations.forEach {change ->
            val entity=CloudEntity.fromTable(change.record.entity)!!
            val original=snapshot.records.getValue(entity).single {it.id==child}
            val field=if(entity==CloudEntity.TRANSACTION_CATEGORY) "parent_category_id" else "category_id"
            assertEquals(JsonPrimitive(target),change.record.payload[field])
            val touched=setOf(field,"updated_at","last_modified_by_device_id")
            assertEquals(original.payload.filterKeys {it !in touched},change.record.payload.filterKeys {it !in touched})
            assertEquals(version,change.mutation.baseVersion)
            assertEquals(if(entity==CloudEntity.LEDGER_TRANSACTION) MutationKind.DELETE else MutationKind.UPSERT,change.mutation.kind)
            assertEquals(change.record.payload,change.mutation.payload)
        }
        val category=plan.mutations.single {it.record.entity==CloudEntity.TRANSACTION_CATEGORY.table}
        assertEquals("2026-10-14T00:00:00.001Z",category.record.updatedAt)
        assertEquals(category.record.updatedAt,plan.translations.single().savedUpdatedAt)
        assertEquals("User name",plan.translations.single().inputName)
        assertEquals(CategoryNameLanguage.ENGLISH,plan.translations.single().sourceLanguage)
    }
    @Test fun `complete snapshot rejects changed row pending failure task owner or missing table`() {
        val source=snapshot()
        source.requireUnchanged(source.copy(records=source.records.mapValues {it.value.reversed()},pending=source.pending.reversed()))
        val first=source.pending.first()
        val changedRecords=source.records.toMutableMap().also {it[CloudEntity.BUDGET_PLAN]=listOf(reference(CloudEntity.BUDGET_PLAN).copy(syncVersion=1))}
        listOf(source.copy(records=changedRecords),source.copy(pending=source.pending-first+first.copy(attemptCount=3)),
            source.copy(translations=emptyList()),source.copy(owner=UserId(other)),source.copy(records=source.records-CloudEntity.LEDGER_TRANSACTION)).forEach {
            assertThrows(IllegalArgumentException::class.java) {source.requireUnchanged(it)}
        }
    }
    @Test fun `foreign viewer reference and its translation task remain untouched`() {
        val original=snapshot()
        val foreign=reference(CloudEntity.TRANSACTION_CATEGORY).let {it.copy(payload=JsonObject(it.payload+("user_id" to JsonPrimitive(other))))}
        val records=original.records.toMutableMap().also {it[CloudEntity.TRANSACTION_CATEGORY]=listOf(category(),category(target),foreign)}
        val plan=planCategoryReferenceRepairs(original.copy(records=records,pending=original.pending.filter {it.mutation.entity!=CloudEntity.TRANSACTION_CATEGORY}),old,target,device,now)
        assertEquals(3,plan.mutations.size)
        assertTrue(plan.translations.isEmpty())
    }
    @Test fun `different key foreign target occupied metadata and stale dependent outbox fail closed`() {
        val source=snapshot()
        val targetCategory=TransactionCategoryRecord.fromCloudRecord(category(target))
        listOf(targetCategory.copy(systemKey="another"),targetCategory.copy(ownerUserId=other)).forEach {invalid ->
            val records=source.records.toMutableMap().also {it[CloudEntity.TRANSACTION_CATEGORY]=listOf(category(),invalid.toCloudRecord(),reference(CloudEntity.TRANSACTION_CATEGORY))}
            assertThrows(IllegalArgumentException::class.java) {planCategoryReferenceRepairs(source.copy(records=records),old,target,device,now)}
        }
        val bad=source.pending.first().let {it.copy(mutation=it.mutation.copy(payload=JsonObject(emptyMap())))}
        assertThrows(IllegalArgumentException::class.java) {planCategoryReferenceRepairs(source.copy(pending=source.pending.drop(1)+bad),old,target,device,now)}
    }
    @Test fun `retarget cannot make destination category its own parent`() {
        val source=snapshot()
        val cyclic=TransactionCategoryRecord.fromCloudRecord(category(target)).copy(parentCategoryId=old).toCloudRecord()
        val records=source.records.toMutableMap().also {it[CloudEntity.TRANSACTION_CATEGORY]=listOf(category(),cyclic,reference(CloudEntity.TRANSACTION_CATEGORY))}
        assertThrows(IllegalArgumentException::class.java) {planCategoryReferenceRepairs(source.copy(records=records),old,target,device,now)}
    }
    @Test fun `previously clean references get matching mutations without inventing base versions`() {
        val plan=planCategoryReferenceRepairs(snapshot().copy(pending=emptyList(),translations=emptyList()),old,target,device,now)
        assertEquals(4,plan.mutations.size)
        assertTrue(plan.mutations.all {it.record.syncVersion==version && it.mutation.baseVersion==version && it.record.payload==it.mutation.payload})
    }
    @Test fun `child identities require existing owned parent metadata`() {
        val source=snapshot()
        val parent=TransactionCategoryRecord.fromCloudRecord(category(device))
        val first=TransactionCategoryRecord.fromCloudRecord(category()).copy(systemKey="internet",parentCategoryId=device,hierarchyRoleWireValue="child")
        val second=first.copy(id=target)
        val records=source.records.toMutableMap().also {it[CloudEntity.TRANSACTION_CATEGORY]=listOf(parent.toCloudRecord(),first.toCloudRecord(),second.toCloudRecord())}
        assertEquals(3,planCategoryReferenceRepairs(source.copy(records=records,pending=source.pending.filter {it.mutation.entity!=CloudEntity.TRANSACTION_CATEGORY},translations=emptyList()),old,target,device,now).mutations.size)
        val missing=records.toMutableMap().also {it[CloudEntity.TRANSACTION_CATEGORY]=listOf(first.toCloudRecord(),second.toCloudRecord())}
        assertThrows(IllegalArgumentException::class.java) {planCategoryReferenceRepairs(source.copy(records=missing),old,target,device,now)}
    }
    @Test fun `tombstoned target requires identity reconciliation before reference repairs`() {
        val source=snapshot()
        val deleted=TransactionCategoryRecord.fromCloudRecord(category(target)).copy(deletedAt=now).toCloudRecord()
        val records=source.records.toMutableMap().also {it[CloudEntity.TRANSACTION_CATEGORY]=listOf(category(),deleted,reference(CloudEntity.TRANSACTION_CATEGORY))}
        assertThrows(IllegalArgumentException::class.java) {planCategoryReferenceRepairs(source.copy(records=records),old,target,device,now)}
    }
    @Test fun `stale translation task is retained for normal maintenance rather than retimed`() {
        val source=snapshot()
        val stale=source.translations.single().let {it.copy(translation=it.translation.copy(savedUpdatedAt="2020-01-01T00:00:00Z"))}
        val plan=planCategoryReferenceRepairs(source.copy(translations=listOf(stale)),old,target,device,now)
        assertTrue(plan.translations.isEmpty())
        assertEquals(4,plan.mutations.size)
    }
}
