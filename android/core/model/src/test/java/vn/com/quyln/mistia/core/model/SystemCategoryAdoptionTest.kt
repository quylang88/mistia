package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class SystemCategoryAdoptionTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="22222222-2222-2222-2222-222222222222"
    private val legacy="33333333-3333-3333-3333-333333333333"
    private val now="2026-10-14T00:00:00Z"
    private val catalog=SystemCategoryCatalog.parse("""[
        {"id":"home","kind":"expense","active":true,"icon":"house.fill","fallbackIcon":"house.fill","color":"#123456",
        "translations":{"vi":"Nhà","en":"Home","ja":"家"},"aliases":[],"children":[]}
    ]""")
    private val seed=catalog.activeDefinitions.single().seedRecord(owner,null,device,now)
    private fun remote(id:String=legacy)=seed.copy(id=id,name="Cloud custom",nameEnglish="Cloud name",iconColorHex="#ABCDEF",syncVersion=9007199254740993L,
        createdAt="2020-01-01T00:00:00Z",updatedAt="2020-01-02T00:00:00Z").toCloudRecord()
    private fun snapshot(local:CloudRecord=seed.toCloudRecord(),translations:List<QueuedCategoryTranslation> = emptyList()):CategoryReferenceSnapshot {
        val mutation=PendingMutation(CloudEntity.TRANSACTION_CATEGORY,local.id,owner.value,MutationKind.UPSERT,local.payload,local.updatedAt!!,0,device)
        return CategoryReferenceSnapshot(owner,categoryReferenceEntities.associateWith {if(it==CloudEntity.TRANSACTION_CATEGORY) listOf(local) else emptyList()},listOf(QueuedMutation(mutation,0,0,null)),translations)
    }
    private fun prepare(snapshot:CategoryReferenceSnapshot,remote:List<CloudRecord> = listOf(remote()))=
        prepareSystemCategoryAdoption(snapshot,snapshot.pending.first(),remote,catalog,device,now)
    @Test fun `untouched seed adopts the exact real legacy wire row without a fabricated ACK`() {
        val snapshot=snapshot();val remote=remote()
        val plan=prepare(snapshot,listOf(remote))
        assertEquals(seed.toCloudRecord(),plan.source)
        assertEquals(remote,plan.target)
        assertEquals(legacy,plan.target.id)
        assertNull(plan.mutation)
        assertEquals(listOf(remote),plan.selection.candidates)
        assertEquals(seed.id,snapshot.pending.single().mutation.recordId)
    }
    @Test fun `favorite only edit preserves remote names color audit and exact base version`() {
        val local=seed.copy(isFavorite=true,updatedAt="2026-10-14T01:00:00Z").toCloudRecord()
        val plan=prepare(snapshot(local))
        val typed=TransactionCategoryRecord.fromCloudRecord(plan.target)
        assertTrue(typed.isFavorite)
        assertEquals("Cloud custom",typed.name)
        assertEquals("#ABCDEF",typed.iconColorHex)
        assertEquals("2020-01-01T00:00:00Z",typed.createdAt)
        assertEquals(9007199254740993L,typed.syncVersion)
        assertEquals(9007199254740993L,plan.mutation!!.baseVersion)
        assertEquals(plan.target.payload,plan.mutation!!.payload)
        assertEquals("2026-10-14T01:00:00.001Z",plan.target.updatedAt)
    }
    @Test fun `local name and unknown fields merge without dropping remote future fields`() {
        val exact=JsonObject(mapOf("minor" to JsonPrimitive(9007199254740995L)))
        val local=seed.copy(name="User edit").toCloudRecord().let {it.copy(payload=JsonObject(it.payload+("local_future" to exact)))}
        val remote=remote().let {it.copy(payload=JsonObject(it.payload+("remote_future" to JsonNull)))}
        val plan=prepare(snapshot(local),listOf(remote))
        assertEquals(JsonPrimitive("User edit"),plan.target.payload["name"])
        assertEquals(JsonPrimitive("Cloud name"),plan.target.payload["name_english"])
        assertEquals(exact,plan.target.payload["local_future"])
        assertTrue(plan.target.payload.containsKey("remote_future"))
        assertEquals(JsonNull,plan.target.payload["remote_future"])
    }
    @Test fun `authoritative tombstone stays deleted and edited seed conflict preserves local data`() {
        val deleted=TransactionCategoryRecord.fromCloudRecord(remote()).copy(deletedAt=now).toCloudRecord()
        assertEquals(deleted,prepare(snapshot(),listOf(deleted)).target)
        val edited=snapshot(seed.copy(isFavorite=true).toCloudRecord())
        assertThrows(IllegalArgumentException::class.java) {prepare(edited,listOf(deleted))}
        assertEquals(true,edited.records.getValue(CloudEntity.TRANSACTION_CATEGORY).single().payload["is_favorite"]!!.jsonPrimitive.boolean)
    }
    @Test fun `actual cloud identity uses its own version when values come from live duplicate`() {
        val identity=TransactionCategoryRecord.fromCloudRecord(remote(seed.id)).copy(deletedAt=now,syncVersion=42).toCloudRecord()
        val values=remote()
        val plan=prepare(snapshot(),listOf(identity,values))
        assertEquals(seed.id,plan.target.id)
        assertEquals(42L,plan.target.syncVersion)
        assertEquals(42L,plan.mutation!!.baseVersion)
        assertNull(plan.target.deletedAt)
        assertEquals("Cloud custom",TransactionCategoryRecord.fromCloudRecord(plan.target).name)
        assertEquals(listOf(identity,values),plan.selection.candidates)
    }
    @Test fun `stale source queue and occupied target mutation cannot be silently discarded`() {
        val source=snapshot()
        val changed=source.pending.single().let {it.copy(mutation=it.mutation.copy(payload=JsonObject(emptyMap())))}
        assertThrows(IllegalArgumentException::class.java) {prepareSystemCategoryAdoption(source,changed,listOf(remote()),catalog,device,now)}
        val remote=remote()
        val occupied=source.copy(records=source.records+mapOf(CloudEntity.TRANSACTION_CATEGORY to listOf(seed.toCloudRecord(),remote)),
            pending=source.pending+QueuedMutation(PendingMutation(CloudEntity.TRANSACTION_CATEGORY,legacy,owner.value,MutationKind.UPSERT,remote.payload,now,remote.syncVersion,device),0,0,null))
        assertThrows(IllegalArgumentException::class.java) {prepare(occupied)}
    }
    @Test fun `foreign remote values and target advancing beyond lookup reject adoption`() {
        val foreign=TransactionCategoryRecord.fromCloudRecord(remote()).copy(ownerUserId=device).toCloudRecord().copy(ownerUserId=owner.value)
        assertThrows(IllegalArgumentException::class.java) {prepare(snapshot(),listOf(foreign))}
        val original=snapshot()
        val newer=TransactionCategoryRecord.fromCloudRecord(remote()).copy(syncVersion=9007199254740994L).toCloudRecord()
        val changed=original.copy(records=original.records+mapOf(CloudEntity.TRANSACTION_CATEGORY to listOf(seed.toCloudRecord(),newer)))
        assertThrows(IllegalArgumentException::class.java) {prepare(changed)}
    }
    @Test fun `explicit translation source equal to default still preserves user input intent`() {
        val task=QueuedCategoryTranslation(PendingCategoryTranslation(owner.value,seed.id,"Home",CategoryNameLanguage.ENGLISH,now,device),0,0,null)
        val plan=prepare(snapshot(translations=listOf(task)))
        assertEquals("Home",plan.target.payload["name_english"]!!.jsonPrimitive.content)
        assertNotNull(plan.mutation)
        assertEquals("Home",plan.translation!!.inputName)
    }
    private fun migration(source:CategoryReferenceSnapshot,rows:List<CloudRecord> = listOf(remote())) =
        planSystemCategoryIdentityMigration(source,source.pending.first(),rows,catalog,device,now)
    private fun referencedSnapshot(foreign:Boolean=false):CategoryReferenceSnapshot {
        val source=snapshot()
        val ledger=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,device,owner.value,buildJsonObject {
            put("id",device);put("user_id",if(foreign) legacy else owner.value);put("category_id",seed.id)
            put("amount_minor",9007199254740995L);put("category_name_snapshot","Frozen name")
            put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",9007199254740993L)
        },now,null,9007199254740993L)
        return source.copy(records=source.records+mapOf(CloudEntity.LEDGER_TRANSACTION to listOf(ledger)))
    }
    @Test fun `identity plan combines exact adoption with lossless dependent repair`() {
        val plan=migration(referencedSnapshot())
        assertTrue(plan.removesSourceIdentity)
        assertEquals(remote(),plan.adoption.target)
        val ledger=plan.references.mutations.single()
        assertEquals(legacy,ledger.record.payload["category_id"]!!.jsonPrimitive.content)
        assertEquals(9007199254740995L,ledger.record.payload["amount_minor"]!!.jsonPrimitive.long)
        assertEquals("Frozen name",ledger.record.payload["category_name_snapshot"]!!.jsonPrimitive.content)
        assertEquals(9007199254740993L,ledger.mutation.baseVersion)
    }
    @Test fun `authoritative tombstone adoption repairs references without resurrecting target`() {
        val deleted=TransactionCategoryRecord.fromCloudRecord(remote()).copy(deletedAt=now).toCloudRecord()
        val plan=migration(referencedSnapshot(),listOf(deleted))
        assertEquals(deleted,plan.adoption.target)
        assertNull(plan.adoption.mutation)
        assertEquals(legacy,plan.references.mutations.single().record.payload["category_id"]!!.jsonPrimitive.content)
    }
    @Test fun `foreign references block source removal and duplicate remote cleanup stays explicit`() {
        assertThrows(IllegalArgumentException::class.java) {migration(referencedSnapshot(true))}
        assertThrows(IllegalArgumentException::class.java) {migration(snapshot(),listOf(remote(),remote(seed.id)))}
    }
    @Test fun `same identity adoption retains identity and needs no FK rewrite`() {
        val plan=migration(referencedSnapshot(),listOf(remote(seed.id)))
        assertFalse(plan.removesSourceIdentity)
        assertTrue(plan.references.mutations.isEmpty())
        assertEquals(seed.id,plan.adoption.target.id)
    }
    @Test fun `observed zero version queue is never mistaken for an unuploaded default seed`() {
        val source=snapshot()
        val known=source.pending.single().copy(remoteIdentityObserved=true)
        assertThrows(IllegalArgumentException::class.java) {prepareSystemCategoryAdoption(source.copy(pending=listOf(known)),known,listOf(remote()),catalog,device,now)}
    }
    @Test fun `pending source translation moves to the adopted wire identity preserving explicit language`() {
        val local=seed.copy(nameEnglish="User English").toCloudRecord()
        val task=QueuedCategoryTranslation(PendingCategoryTranslation(owner.value,seed.id,"User English",CategoryNameLanguage.ENGLISH,now,device),3,Long.MAX_VALUE,"old_failure")
        val plan=prepare(snapshot(local,listOf(task)))
        assertEquals(legacy,plan.translation!!.categoryId)
        assertEquals("User English",plan.translation!!.inputName)
        assertEquals(CategoryNameLanguage.ENGLISH,plan.translation!!.sourceLanguage)
        assertEquals(plan.target.updatedAt,plan.translation!!.savedUpdatedAt)
        assertNotNull(plan.mutation)
    }
}
