package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class SystemCategoryReconciliationTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val old="22222222-2222-2222-2222-222222222222"
    private val target="33333333-3333-3333-3333-333333333333"
    private val device="44444444-4444-4444-4444-444444444444"
    private val now="2026-10-14T00:00:00Z"
    private val catalog=SystemCategoryCatalog.parse("""[
      {"id":"parent_expense_housing","kind":"expense","active":true,"icon":"house.fill","fallbackIcon":"house.fill","color":"#FF8A4C","translations":{"vi":"Nhà","en":"Home","ja":"住まい"},"aliases":[],"children":[
        {"id":"internet","active":true,"icon":"wifi","fallbackIcon":"wifi","color":"#5B7BFF","translations":{"vi":"Mạng","en":"Internet","ja":"インターネット"},"aliases":[]}
      ]}
    ]""")
    private fun remote(id:String=old,updated:String=now,deleted:String?=null,version:Long=9007199254740993L)=
        catalog.definitions.single {it.key=="internet"}.seedRecord(owner,SystemCategoryIdentity.cloudId("parent_expense_housing",owner),device,now)
            .copy(id=id,name="Personal internet",updatedAt=updated,deletedAt=deleted,syncVersion=version).toCloudRecord()
    @Test fun `single legacy remote uses actual ID with exact version and metadata`() {
        val row=remote()
        val selected=selectSystemCategoryRemote(owner,"internet",listOf(row))!!
        assertEquals(row,selected.identity);assertEquals(row,selected.values)
        assertEquals(listOf(row),selected.candidates)
        assertNull(selectSystemCategoryRemote(owner,"internet",emptyList()))
    }
    @Test fun `existing owner cloud identity and newer values remain separate`() {
        val canonical=remote(SystemCategoryIdentity.cloudId("internet",owner),"2026-10-13T00:00:00Z",version=17)
        val newer=remote()
        val selected=selectSystemCategoryRemote(owner,"internet",listOf(canonical,newer))!!
        assertEquals(canonical,selected.identity)
        assertEquals(newer,selected.values)
        assertEquals(listOf(canonical,newer),selected.candidates)
    }
    @Test fun `active values win tombstones while existing identity tombstone remains truthful`() {
        val tombstone=remote(SystemCategoryIdentity.cloudId("internet",owner),"2027-10-14T00:00:00Z",now)
        val live=remote()
        val selected=selectSystemCategoryRemote(owner,"internet",listOf(tombstone,live))!!
        assertEquals(tombstone,selected.identity);assertEquals(live,selected.values)
        assertNotNull(selected.identity.deletedAt)
        val deleted=selectSystemCategoryRemote(owner,"internet",listOf(remote(deleted=now)))!!
        assertNotNull(deleted.values.deletedAt)
    }
    @Test fun `Swift cloud ID priority bonus can beat a slightly newer legacy row`() {
        val cloud=remote(SystemCategoryIdentity.cloudId("internet",owner),"2026-10-13T23:50:00Z")
        assertEquals(cloud,selectSystemCategoryRemote(owner,"internet",listOf(remote(),cloud))!!.values)
    }
    @Test fun `foreign mismatched key non system duplicate ID and metadata mismatch fail closed`() {
        val row=remote()
        val typed=TransactionCategoryRecord.fromCloudRecord(row)
        listOf(row.copy(ownerUserId=other),typed.copy(ownerUserId=other).toCloudRecord().copy(ownerUserId=owner.value),
            typed.copy(systemKey="rent").toCloudRecord(),typed.copy(isSystem=false).toCloudRecord(),row.copy(syncVersion=1)).forEach {
            assertThrows(IllegalArgumentException::class.java) {selectSystemCategoryRemote(owner,"internet",listOf(it))}
        }
        assertThrows(IllegalArgumentException::class.java) {selectSystemCategoryRemote(owner,"internet",listOf(row,row))}
    }
    private fun reference(entity:CloudEntity,deleted:String?=null):CloudRecord {
        val field=if(entity==CloudEntity.TRANSACTION_CATEGORY) "parent_category_id" else "category_id"
        return CloudRecord(entity.table,device,owner.value,buildJsonObject {
            put("id",device);put("user_id",owner.value);put(field,old)
            put("amount_minor",9007199254740993L);put("currency_code","JPY")
            put("category_id_snapshot",SystemCategoryIdentity.canonicalId("internet"))
            put("category_name_snapshot","Frozen original name")
            put("future_wire_field",buildJsonObject {put("exact",9007199254740995L);put("nullable",JsonNull)})
            put("deleted_at",deleted?.let(::JsonPrimitive) ?: JsonNull)
            put("sync_version",9007199254740997L);put("updated_at",now);put("created_by_user_id",other)
        },now,deleted,9007199254740997L)
    }
    private fun pending(row:CloudRecord,kind:MutationKind=MutationKind.UPSERT)=PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,kind,row.payload,now,row.syncVersion,device)
    @Test fun `category ledger budget and bill FKs rewrite without monetary snapshot or unknown field loss`() {
        listOf(CloudEntity.TRANSACTION_CATEGORY,CloudEntity.LEDGER_TRANSACTION,CloudEntity.BUDGET_PLAN,CloudEntity.RECURRING_BILL_PLAN).forEach {entity ->
            val row=reference(entity)
            val change=rewriteOwnedCategoryReference(owner,row,pending(row),old,target,device,"2026-10-14T01:00:00Z")!!
            val field=if(entity==CloudEntity.TRANSACTION_CATEGORY) "parent_category_id" else "category_id"
            assertEquals(JsonPrimitive(target),change.record.payload[field])
            val touched=setOf(field,"updated_at","last_modified_by_device_id")
            assertEquals(row.payload.filterKeys {it !in touched},change.record.payload.filterKeys {it !in touched})
            assertEquals(row.syncVersion,change.record.syncVersion)
            assertEquals(row.syncVersion,change.mutation.baseVersion)
            assertEquals(change.record.payload,change.mutation.payload)
            assertEquals(MutationKind.UPSERT,change.mutation.kind)
        }
    }
    @Test fun `deleted reference preserves DELETE version and clock does not regress`() {
        val row=reference(CloudEntity.LEDGER_TRANSACTION,now)
        val change=rewriteOwnedCategoryReference(owner,row,pending(row,MutationKind.DELETE),old,target,device,"2020-01-01T00:00:00Z")!!
        assertEquals(now,change.record.updatedAt);assertEquals(now,change.record.deletedAt)
        assertEquals(MutationKind.DELETE,change.mutation.kind)
        assertEquals(row.syncVersion,change.mutation.baseVersion)
    }
    @Test fun `deleted category FK repair uses full upsert without resurrecting or inventing category delete`() {
        val row=reference(CloudEntity.TRANSACTION_CATEGORY,now)
        val change=rewriteOwnedCategoryReference(owner,row,null,old,target,device,now)!!
        assertEquals(MutationKind.UPSERT,change.mutation.kind)
        assertEquals(now,change.record.deletedAt)
        assertEquals(JsonPrimitive(target),change.record.payload["parent_category_id"])
        assertEquals(row.syncVersion,change.mutation.baseVersion)
        assertEquals(MutationKind.DELETE,rewriteOwnedCategoryReference(owner,row,pending(row,MutationKind.DELETE),old,target,device,now)!!.mutation.kind)
    }
    @Test fun `previously synced reference gets new matching outbox without incrementing remote version`() {
        val row=reference(CloudEntity.BUDGET_PLAN)
        val change=rewriteOwnedCategoryReference(owner,row,null,old,target,device,now)!!
        assertEquals(row.syncVersion,change.mutation.baseVersion)
        assertEquals(row.id,change.mutation.recordId)
        assertEquals(owner.value,change.mutation.subjectUserId)
    }
    @Test fun `foreign viewer unsupported unrelated and no op rows are never rewritten`() {
        val row=reference(CloudEntity.LEDGER_TRANSACTION)
        assertNull(rewriteOwnedCategoryReference(owner,row.copy(ownerUserId=other),null,old,target,device,now))
        val foreign=row.copy(payload=JsonObject(row.payload+mapOf("user_id" to JsonPrimitive(other))))
        assertNull(rewriteOwnedCategoryReference(owner,foreign,null,old,target,device,now))
        assertNull(rewriteOwnedCategoryReference(owner,row.copy(entity=CloudEntity.SAVINGS_GOAL.table),null,old,target,device,now))
        assertNull(rewriteOwnedCategoryReference(owner,row,null,target,old,device,now))
        assertNull(rewriteOwnedCategoryReference(owner,row,null,old,old,device,now))
    }
    @Test fun `stale or foreign outbox input cannot replace current dependent edits`() {
        val row=reference(CloudEntity.LEDGER_TRANSACTION)
        assertThrows(IllegalArgumentException::class.java) {rewriteOwnedCategoryReference(owner,row,pending(row).copy(payload=JsonObject(emptyMap())),old,target,device,now)}
        assertThrows(IllegalArgumentException::class.java) {rewriteOwnedCategoryReference(owner,row,pending(row).copy(subjectUserId=other),old,target,device,now)}
    }
    @Test fun `remote wire version and deletion null cannot contradict envelope metadata`() {
        val row=remote()
        val malformed=listOf(row.copy(payload=JsonObject(row.payload+mapOf("sync_version" to JsonPrimitive(row.syncVersion.toString())))),
            remote(deleted=now).let {it.copy(payload=JsonObject(it.payload+mapOf("deleted_at" to JsonNull)))})
        malformed.forEach { candidate ->
            assertThrows(IllegalArgumentException::class.java) {selectSystemCategoryRemote(owner,"internet",listOf(candidate))}
        }
    }

    @Test fun `reference metadata contradictions cannot regress a newer payload or hide deletion`() {
        val row=reference(CloudEntity.LEDGER_TRANSACTION)
        listOf(row.copy(payload=JsonObject(row.payload+mapOf("updated_at" to JsonPrimitive("2027-10-14T00:00:00Z")))),
            row.copy(payload=JsonObject(row.payload+mapOf("deleted_at" to JsonPrimitive(now)))),
            row.copy(payload=JsonObject(row.payload+mapOf("sync_version" to JsonPrimitive(row.syncVersion.toString()))))).forEach { candidate ->
            assertThrows(IllegalArgumentException::class.java) {rewriteOwnedCategoryReference(owner,candidate,null,old,target,device,now)}
        }
    }

}
