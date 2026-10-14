package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.EntityCount
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.MutationKind
import vn.com.quyln.mistia.core.model.PendingMutation
import vn.com.quyln.mistia.core.model.QueuedMutation
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.network.SupabaseHttpException

import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.model.seedRecord
import vn.com.quyln.mistia.core.model.bootstrapMutation
class SystemCategorySeedPushTest {
    private val catalog=vn.com.quyln.mistia.core.model.SystemCategoryCatalog.parse("""[
      {"id":"parent_expense_housing","kind":"expense","active":true,"icon":"mistia.category.parent.expense.housing","fallbackIcon":"house.fill","color":"#FF8A4C","translations":{"vi":"Home","en":"Home","ja":"Home"},"aliases":[],"children":[
      {"id":"rent","active":true,"icon":"mistia.category.expense.home.rent","fallbackIcon":"house.fill","color":"#FF8A4C","translations":{"vi":"Rent","en":"Rent","ja":"Rent"},"aliases":[]}]}
    ]""")
    private val parent=catalog.definitions.single {it.parentKey==null}.seedRecord(UserId(OWNER),null,DEVICE,NOW).copy(id=PARENT_ID)
    private fun row(name:String="Rent",time:String=NOW,version:Long=0)=catalog.definitions.single {it.key=="rent"}.seedRecord(UserId(OWNER),PARENT_ID,DEVICE,NOW)
        .copy(name=name,updatedAt=time,syncVersion=version).toCloudRecord()
    private fun pending(record:CloudRecord)=QueuedMutation(vn.com.quyln.mistia.core.model.TransactionCategoryRecord.fromCloudRecord(record).bootstrapMutation(),0,0,null)
    private fun local(record:CloudRecord=row())=FakeLocalStore(mapOf(record.id to record,parent.id to parent.toCloudRecord()),mutableListOf(pending(record)))
    private fun coordinator(local:LocalStore,remote:RemoteMutationStore)=CategoryPushCoordinator(local,remote,true,catalog) {NOW_MILLIS}

    @Test fun `untouched seed accepts older remote customization without any write`()=runTest {
        val local=local()
        val remoteRow=row("Remote custom","2026-09-22T00:00:00Z",7)
        val remote=FakeRemoteStore().apply {fetchedResults.add(remoteRow)}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).reconciled)
        assertEquals(0,remote.writeCalls);assertEquals(remoteRow,local.records[CATEGORY_ID]);assertTrue(local.queued.isEmpty())
    }
    @Test fun `explicit edit follows normal local winner instead of bootstrap preference`()=runTest {
        val local=local(row("User edit",LATER))
        val remote=FakeRemoteStore().apply {fetchedResults.add(row("Remote custom",NOW,7));updatedResults.add(row("User edit",LATER,8))}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).reconciled)
        assertEquals(0,remote.writeCalls)
        assertEquals("User edit",local.records[CATEGORY_ID]!!.payload.string("name"))
        assertEquals(7L,local.queued.single().mutation.baseVersion)
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).pushed)
        assertEquals(1,remote.writeCalls)
    }
    @Test fun `favorite edit at same clock does not classify as untouched seed`()=runTest {
        val edited=row().let {it.copy(payload=JsonObject(it.payload+("is_favorite" to JsonPrimitive(true))))}
        val local=local(edited)
        val remote=FakeRemoteStore().apply {fetchedResults.add(row("Remote custom","2026-09-22T00:00:00Z",7));updatedResults.add(edited.copy(syncVersion=8,payload=JsonObject(edited.payload+("sync_version" to JsonPrimitive(8)))))}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).reconciled)
        assertEquals("Remote custom",local.records[CATEGORY_ID]!!.payload.string("name"))
        assertEquals(JsonPrimitive(true),local.records[CATEGORY_ID]!!.payload["is_favorite"])
        assertEquals(0,remote.writeCalls)
        val merged=local.records[CATEGORY_ID]!!
        remote.updatedResults.clear()
        remote.updatedResults.add(merged.copy(syncVersion=8,payload=JsonObject(merged.payload+("sync_version" to JsonPrimitive(8)))))
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).pushed)
        assertEquals(1,remote.writeCalls)
    }
    @Test fun `remote tombstone wins untouched bootstrap and is never resurrected`()=runTest {
        val local=local()
        val remoteRow=row("Deleted","2026-09-22T00:00:00Z",7).let {it.copy(deletedAt=NOW,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(NOW))))}
        val remote=FakeRemoteStore().apply {fetchedResults.add(remoteRow)}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).reconciled)
        assertEquals(0,remote.writeCalls);assertEquals(NOW,local.records[CATEGORY_ID]!!.deletedAt)
    }
    @Test fun `create race accepts remote customization instead of force updating it`()=runTest {
        val local=local()
        val remote=FakeRemoteStore().apply {fetchedResults.add(null);fetchedResults.add(row("Racer","2026-09-22T00:00:00Z",1));createFailures.add(SupabaseHttpException(409,"duplicate"))}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).reconciled)
        assertEquals(1,remote.writeCalls);assertTrue(remote.updatedPayloads.isEmpty())
    }
    @Test fun `late preference ACK cannot delete a replacement user mutation`()=runTest {
        val newer=pending(row("User edit",LATER))
        val local=local().apply {replacementOnAcknowledge=newer;replacementRecordOnAcknowledge=row("User edit",LATER)}
        val remote=FakeRemoteStore().apply {fetchedResults.add(row("Remote","2026-09-22T00:00:00Z",7));fetchedResults.add(row("Remote","2026-09-22T00:00:00Z",7));updatedResults.add(row("User edit",LATER,8))}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).staleResponses)
        assertEquals(newer,local.queued.single());assertEquals(0,remote.writeCalls)
        assertEquals("User edit",local.records[CATEGORY_ID]!!.payload.string("name"))
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).reconciled)
        assertEquals(7L,local.queued.single().mutation.baseVersion)
        assertEquals("User edit",local.records[CATEGORY_ID]!!.payload.string("name"))
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).pushed)
        assertEquals("User edit",local.records[CATEGORY_ID]!!.payload.string("name"));assertTrue(local.queued.isEmpty())
    }
    @Test fun `new untouched seed still creates normally when remote absent`()=runTest {
        val local=local()
        val remote=FakeRemoteStore().apply {createdResults.add(row(version=1))}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).pushed)
        assertEquals(1,remote.writeCalls)
    }
    @Test fun `disabled category gate remains silent even with bootstrap catalog`()=runTest {
        val local=local();val remote=FakeRemoteStore()
        assertEquals(CategoryPushSummary(),CategoryPushCoordinator(local,remote,false,catalog) {NOW_MILLIS}.pushPending(UserId(OWNER),TOKEN))
        assertEquals(0,remote.fetchCalls);assertEquals(0,remote.keyCalls);assertEquals(1,local.queued.size)
    }
    @Test fun `previously uploaded system category still follows normal winner semantics`()=runTest {
        val local=local(row(time=LATER,version=5))
        val remote=FakeRemoteStore().apply {fetchedResults.add(row("Remote",NOW,7));updatedResults.add(row(time=LATER,version=8))}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).pushed)
        assertEquals(1,remote.writeCalls)
    }
    @Test fun `existing different ID is found by owner key before create and refs migrate atomically`()=runTest {
        val local=local()
        val ledgerId="66666666-6666-6666-6666-666666666666"
        val ledger=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,ledgerId,OWNER,JsonObject(mapOf(
            "id" to JsonPrimitive(ledgerId),"user_id" to JsonPrimitive(OWNER),"category_id" to JsonPrimitive(CATEGORY_ID),
            "amount_minor" to JsonPrimitive(9007199254740993L),"sync_version" to JsonPrimitive(7),"updated_at" to JsonPrimitive(NOW),"deleted_at" to JsonNull,
        )),NOW,null,7)
        local.records[ledgerId]=ledger
        val legacy=row("Remote custom","2026-09-22T00:00:00Z",7).let {it.copy(id=CHILD_ID,payload=JsonObject(it.payload+("id" to JsonPrimitive(CHILD_ID))))}
        val remote=FakeRemoteStore().apply {systemPages.add(SystemCategoryPage(listOf(legacy),null))}
        coordinator(local,remote).pushPending(UserId(OWNER),TOKEN)
        assertEquals(0,remote.writeCalls)
        assertNull(local.records[CATEGORY_ID])
        assertEquals(legacy,local.records[CHILD_ID])
        assertEquals(CHILD_ID,local.records[ledgerId]!!.payload.string("category_id"))
        assertEquals(9007199254740993L,local.records[ledgerId]!!.payload.long("amount_minor"))
        assertEquals(1,remote.keyCalls)
    }
    @Test fun `different ID create409 race repeats complete key lookup before local migration`()=runTest {
        val local=local()
        val legacy=row("Racer",NOW,1).let {it.copy(id=CHILD_ID,payload=JsonObject(it.payload+("id" to JsonPrimitive(CHILD_ID))))}
        val remote=FakeRemoteStore().apply {
            systemPages.add(SystemCategoryPage(emptyList(),null));systemPages.add(SystemCategoryPage(listOf(legacy),null))
            createFailures.add(SupabaseHttpException(409,"duplicate system key"))
        }
        coordinator(local,remote).pushPending(UserId(OWNER),TOKEN)
        assertEquals(legacy,local.records[CHILD_ID])
        assertNull(local.records[CATEGORY_ID]);assertTrue(local.queued.isEmpty())
        assertEquals(2,remote.keyCalls);assertEquals(1,remote.writeCalls)
    }
    @Test fun `key lookup cancellation propagates without modifying pending seed`()=runTest {
        val local=local();val before=local.queued.toList()
        val remote=FakeRemoteStore().apply {keyFailure=CancellationException("cancelled")}
        val failure=runCatching {coordinator(local,remote).pushPending(UserId(OWNER),TOKEN)}.exceptionOrNull()
        assertTrue(failure is CancellationException)
        assertEquals(before,local.queued);assertEquals(0,remote.writeCalls)
    }
    @Test fun `complete key pagination retains remote duplicates as explicit conflict`()=runTest {
        val local=local()
        val first=row(version=7).let {it.copy(id=CHILD_ID,payload=JsonObject(it.payload+("id" to JsonPrimitive(CHILD_ID))))}
        val remote=FakeRemoteStore().apply {
            systemPages.add(SystemCategoryPage(listOf(first),1));systemPages.add(SystemCategoryPage(listOf(row(version=8)),null))
        }
        val result=coordinator(local,remote).pushPending(UserId(OWNER),TOKEN)
        assertEquals(1,result.conflicts)
        assertEquals(listOf(0,1),remote.keyOffsets)
        assertEquals(0,remote.writeCalls)
        assertEquals(row(),local.records[CATEGORY_ID])
        assertEquals(Long.MAX_VALUE,local.queued.single().nextAttemptAtEpochMillis)
    }
    @Test fun `key lookup failure retries exact seed without create or lost ownership`()=runTest {
        val local=local();val before=local.queued.single()
        val remote=FakeRemoteStore().apply {keyFailure=SupabaseHttpException(503,"unavailable")}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).retryableFailures)
        assertEquals(before.mutation,local.queued.single().mutation)
        assertEquals(1,local.queued.single().attemptCount)
        assertEquals(NOW_MILLIS+30000,local.queued.single().nextAttemptAtEpochMillis)
        assertEquals(0,remote.writeCalls)
    }
    @Test fun `same clock edit while key lookup is in flight rejects stale migration`()=runTest {
        val local=local();val edited=row("Same clock edit")
        val legacy=row(version=7).let {it.copy(id=CHILD_ID,payload=JsonObject(it.payload+("id" to JsonPrimitive(CHILD_ID))))}
        val remote=FakeRemoteStore().apply {
            systemPages.add(SystemCategoryPage(listOf(legacy),null))
            onKey={local.records[CATEGORY_ID]=edited;local.queued.clear();local.queued.add(pending(edited))}
        }
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).staleResponses)
        assertEquals(edited,local.records[CATEGORY_ID]);assertEquals(pending(edited),local.queued.single())
        assertNull(local.records[CHILD_ID]);assertEquals(0,remote.writeCalls)
    }
    @Test fun `foreign key response and non advancing pagination refuse mutation`()=runTest {
        val foreign=row(version=7).let {it.copy(payload=JsonObject(it.payload+("user_id" to JsonPrimitive(DEVICE))))}
        listOf(SystemCategoryPage(listOf(foreign),null),SystemCategoryPage(listOf(row(version=7)),0)).forEach {page ->
            val local=local();val remote=FakeRemoteStore().apply {systemPages.add(page)}
            assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).permanentFailures)
            assertEquals(0,remote.writeCalls);assertEquals(row(),local.records[CATEGORY_ID])
            assertEquals(1,local.queued.size)
        }
    }
    @Test fun `future failed parent defers both seed and uploaded child without any request`()=runTest {
        for(version in listOf(0L,5L)) {
            val child=row(version=version)
            val local=local(child).apply {queued.add(pending(parent.toCloudRecord()).copy(nextAttemptAtEpochMillis=Long.MAX_VALUE))}
            val remote=FakeRemoteStore()
            assertEquals(CategoryPushSummary(),coordinator(local,remote).pushPending(UserId(OWNER),TOKEN))
            assertEquals(0,remote.fetchCalls);assertEquals(0,remote.keyCalls);assertEquals(0,remote.writeCalls)
            assertEquals(pending(child),local.queued.first())
        }
    }
    @Test fun `missing cloud child of deleted parent is retained without being created`()=runTest {
        val local=local().apply {records[PARENT_ID]=parent.copy(deletedAt=NOW).toCloudRecord()}
        val remote=FakeRemoteStore()
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).conflicts)
        assertEquals(0,remote.writeCalls)
        assertEquals("conflict_system_category_parent_deleted",local.queued.single().lastError)
    }
    @Test fun `existing child tombstone can be adopted under deleted parent without resurrection`()=runTest {
        val local=local().apply {records[PARENT_ID]=parent.copy(deletedAt=NOW).toCloudRecord()}
        val deleted=TransactionCategoryRecord.fromCloudRecord(row(version=7)).copy(deletedAt=NOW).toCloudRecord()
        val remote=FakeRemoteStore().apply {systemPages.add(SystemCategoryPage(listOf(deleted),null))}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).reconciled)
        assertEquals(deleted,local.records[CATEGORY_ID]);assertTrue(local.queued.isEmpty())
        assertEquals(0,remote.writeCalls)
    }
    @Test fun `observed zero version identity pushes merged edit instead of reconciling forever`()=runTest {
        val local=local(row("User edit",LATER))
        val remote=FakeRemoteStore().apply {fetchedResults.add(row("Cloud custom","2026-09-22T00:00:00Z",0))}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).reconciled)
        val merged=local.records[CATEGORY_ID]!!
        remote.updatedResults.add(merged.copy(syncVersion=1,payload=JsonObject(merged.payload+("sync_version" to JsonPrimitive(1)))))
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).pushed)
        assertEquals(1,remote.writeCalls)
        assertTrue(local.queued.isEmpty())
        assertEquals(2,remote.keyCalls)
    }
    @Test fun `observed zero version edit returning to defaults cannot use untouched seed preference`()=runTest {
        val local=local().apply {queued[0]=queued[0].copy(remoteIdentityObserved=true)}
        val cloud=row(time="2026-09-22T00:00:00Z").let {it.copy(payload=JsonObject(it.payload+("is_favorite" to JsonPrimitive(true))))}
        val remote=FakeRemoteStore().apply {fetchedResults.add(cloud);updatedResults.add(row(version=1))}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).pushed)
        assertEquals(1,remote.keyCalls)
        assertEquals(JsonPrimitive(false),local.records[CATEGORY_ID]!!.payload["is_favorite"])
        assertTrue(local.queued.isEmpty())
    }
    @Test fun `fully paged active identity with deleted alias preserves metadata and retargets history`()=runTest {
        val local=local()
        val ledgerID="66666666-6666-6666-6666-666666666666"
        val ledger=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,ledgerID,OWNER,JsonObject(mapOf(
            "id" to JsonPrimitive(ledgerID),"user_id" to JsonPrimitive(OWNER),"category_id" to JsonPrimitive(CHILD_ID),
            "amount_minor" to JsonPrimitive(9007199254740993L),"sync_version" to JsonPrimitive(7),"updated_at" to JsonPrimitive(NOW),"deleted_at" to JsonNull,
        )),NOW,null,7)
        local.records[ledgerID]=ledger
        val active=row("Active cloud",NOW,9)
        val alias=TransactionCategoryRecord.fromCloudRecord(row("Old",NOW,7)).copy(id=CHILD_ID,deletedAt=NOW).toCloudRecord()
        val remote=FakeRemoteStore().apply {systemPages.add(SystemCategoryPage(listOf(alias),1));systemPages.add(SystemCategoryPage(listOf(active),null))}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).reconciled)
        assertEquals(active,local.records[CATEGORY_ID]);assertEquals(alias,local.records[CHILD_ID])
        assertEquals(CATEGORY_ID,local.records[ledgerID]!!.payload.string("category_id"))
        assertEquals(9007199254740993L,local.records[ledgerID]!!.payload.long("amount_minor"))
        assertEquals(0,remote.writeCalls);assertEquals(listOf(0,1),remote.keyOffsets)
        assertTrue(local.queued.none {it.mutation.entity==CloudEntity.TRANSACTION_CATEGORY})
    }
    @Test fun `future pending alias edit defers adoption without dropping edits or retry state`()=runTest {
        val local=local()
        val alias=TransactionCategoryRecord.fromCloudRecord(row("Local edit",NOW,7)).copy(id=CHILD_ID,deletedAt=NOW).toCloudRecord()
        val aliasQueue=pending(alias).copy(nextAttemptAtEpochMillis=Long.MAX_VALUE,remoteIdentityObserved=true)
        local.records[CHILD_ID]=alias;local.queued.add(aliasQueue)
        val before=local.queued.toList()
        val remoteAlias=TransactionCategoryRecord.fromCloudRecord(alias).copy(name="Cloud old").toCloudRecord()
        val remote=FakeRemoteStore().apply {systemPages.add(SystemCategoryPage(listOf(row(version=9),remoteAlias),null))}
        assertEquals(CategoryPushSummary(),coordinator(local,remote).pushPending(UserId(OWNER),TOKEN))
        assertEquals(before,local.queued);assertEquals(alias,local.records[CHILD_ID])
        assertEquals(0,remote.writeCalls)
    }
    @Test fun `deleted category parent repair pushes full tombstoned payload instead of unsupported delete`()=runTest {
        val deleted=TransactionCategoryRecord.fromCloudRecord(row(version=7)).copy(deletedAt=NOW).toCloudRecord()
        val repaired=rewriteOwnedCategoryReference(UserId(OWNER),deleted,null,PARENT_ID,CHILD_ID,DEVICE,LATER)!!
        val local=local(repaired.record).apply {
            records[CHILD_ID]=parent.copy(id=CHILD_ID,syncVersion=9).toCloudRecord()
            queued.clear();queued.add(QueuedMutation(repaired.mutation,0,0,null,true))
        }
        val result=repaired.record.copy(syncVersion=8,payload=JsonObject(repaired.record.payload+("sync_version" to JsonPrimitive(8))))
        val remote=FakeRemoteStore().apply {fetchedResults.add(deleted);updatedResults.add(result)}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).pushed)
        assertEquals(CHILD_ID,remote.updatedPayloads.single().string("parent_category_id"))
        assertEquals(NOW,remote.updatedPayloads.single().string("deleted_at"))
        assertEquals(NOW,local.records[CATEGORY_ID]!!.deletedAt)
    }
    @Test fun `live child waits when preferred cloud parent is deleted but legacy parent is live`()=runTest {
        val local=local()
        val cloudParent=catalog.definitions.single {it.parentKey==null}.seedRecord(UserId(OWNER),null,DEVICE,NOW).copy(syncVersion=9,deletedAt=NOW)
        local.records[cloudParent.id]=cloudParent.toCloudRecord()
        val before=local.queued.toList()
        val remote=FakeRemoteStore().apply {systemPages.add(SystemCategoryPage(listOf(row("Cloud child",NOW,7)),null))}
        assertEquals(CategoryPushSummary(),coordinator(local,remote).pushPending(UserId(OWNER),TOKEN))
        assertEquals(before,local.queued)
        assertEquals(row(),local.records[CATEGORY_ID])
        assertEquals(PARENT_ID,local.records[CATEGORY_ID]!!.payload.string("parent_category_id"))
        assertEquals(0,remote.writeCalls)
    }
    private fun duplicateRemote():FakeRemoteStore {
        val canonical=TransactionCategoryRecord.fromCloudRecord(row("Deleted canonical",NOW,42)).copy(deletedAt=NOW).toCloudRecord()
        val legacy=TransactionCategoryRecord.fromCloudRecord(row("Live legacy",NOW,9007199254740993L)).copy(id=CHILD_ID).toCloudRecord()
        return FakeRemoteStore().apply {serverRows=linkedMapOf(canonical.id to canonical,legacy.id to legacy)}
    }
    @Test fun `canonical resurrection follows legacy cleanup with exact server versions and uniqueness`()=runTest {
        val local=local();val remote=duplicateRemote()
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).reconciled)
        assertEquals(0,remote.writeCalls)
        assertEquals(setOf(CATEGORY_ID,CHILD_ID),local.queued.map {it.mutation.recordId}.toSet())
        assertEquals(2,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).pushed)
        assertEquals(listOf(CHILD_ID,CATEGORY_ID),remote.updatedPayloads.map {it.string("id")})
        assertEquals(listOf(9007199254740993L,42L),remote.updateExpectedVersions)
        assertEquals(CATEGORY_ID,remote.serverRows!!.values.single {it.deletedAt==null}.id)
        assertEquals("Live legacy",remote.serverRows!![CATEGORY_ID]!!.payload.string("name"))
        assertTrue(local.queued.isEmpty())
    }
    @Test fun `failed cleanup defers canonical activation including future retries`()=runTest {
        val local=local();val remote=duplicateRemote()
        coordinator(local,remote).pushPending(UserId(OWNER),TOKEN)
        remote.updateFailure=SupabaseHttpException(503,"offline")
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).retryableFailures)
        assertEquals(listOf(CHILD_ID),remote.updatedPayloads.map {it.string("id")})
        assertEquals(2,local.queued.size)
        assertEquals(CategoryPushSummary(),coordinator(local,remote).pushPending(UserId(OWNER),TOKEN))
        assertEquals(1,remote.writeCalls)
        assertEquals(CHILD_ID,remote.serverRows!!.values.single {it.deletedAt==null}.id)
        remote.updateFailure=null
        val retry=CategoryPushCoordinator(local,remote,true,catalog) {NOW_MILLIS+30000}
        assertEquals(2,retry.pushPending(UserId(OWNER),TOKEN).pushed)
        assertEquals(CATEGORY_ID,remote.serverRows!!.values.single {it.deletedAt==null}.id)
        assertTrue(local.queued.isEmpty())
    }
    @Test fun `remote winning live alias prevents canonical resurrection after cleanup ACK`()=runTest {
        val local=local();val remote=duplicateRemote()
        coordinator(local,remote).pushPending(UserId(OWNER),TOKEN)
        val live=TransactionCategoryRecord.fromCloudRecord(remote.serverRows!![CHILD_ID]!!).copy(updatedAt="2099-01-01T00:00:00Z",syncVersion=9007199254740994L).toCloudRecord()
        remote.serverRows!![CHILD_ID]=live
        val result=coordinator(local,remote).pushPending(UserId(OWNER),TOKEN)
        assertEquals(1,result.acknowledged);assertEquals(1,result.conflicts)
        assertEquals(0,remote.writeCalls)
        assertEquals(live,local.records[CHILD_ID])
        assertEquals(CATEGORY_ID,local.queued.single().mutation.recordId)
        assertEquals(CHILD_ID,remote.serverRows!!.values.single {it.deletedAt==null}.id)
    }
    @Test fun `observed zero version active edit checks complete key before resurrection`()=runTest {
        val local=local().apply {queued[0]=queued[0].copy(remoteIdentityObserved=true)}
        val remote=duplicateRemote()
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).conflicts)
        assertEquals(0,remote.writeCalls)
        assertEquals(1,remote.keyCalls)
        assertEquals(1,local.queued.size)
    }
    private fun maintenance(local:LocalStore)=CategoryMaintenanceCoordinator(local,catalog,{DEVICE}) {NOW_MILLIS}
    @Test fun `post pull maintenance uses actual raw cloud rows and queues clean group repair`()=runTest {
        val raw=duplicateRemote().serverRows!!.values.toList()
        val local=local().apply {queued.clear();records.putAll(raw.associateBy {it.id})}
        assertEquals(CategoryMaintenanceSummary(processedGroups=1),maintenance(local).reconcileObserved(UserId(OWNER),raw))
        assertEquals(setOf(CATEGORY_ID,CHILD_ID),local.queued.map {it.mutation.recordId}.toSet())
        assertEquals("Live legacy",local.records[CATEGORY_ID]!!.payload.string("name"))
        assertEquals(42L,local.queued.single {it.mutation.recordId==CATEGORY_ID}.mutation.baseVersion)
    }
    @Test fun `maintenance processes root group first and defers children queued by parent repair`()=runTest {
        val cloudParent=SystemCategoryIdentity.cloudId(parent.systemKey!!,UserId(OWNER))
        val root=parent.copy(id=cloudParent,deletedAt=NOW,syncVersion=42).toCloudRecord()
        val oldParent=parent.copy(syncVersion=7).toCloudRecord()
        val childRows=duplicateRemote().serverRows!!.values.toList()
        val raw=childRows+listOf(oldParent,root)
        val local=FakeLocalStore(raw.associateBy {it.id},mutableListOf())
        val summary=maintenance(local).reconcileObserved(UserId(OWNER),raw)
        assertEquals(CategoryMaintenanceSummary(processedGroups=1,deferredGroups=1),summary)
        assertEquals(cloudParent,local.records[CATEGORY_ID]!!.payload.string("parent_category_id"))
        assertEquals(cloudParent,local.records[CHILD_ID]!!.payload.string("parent_category_id"))
        assertTrue(local.queued.any {it.mutation.recordId==cloudParent})
        assertTrue(local.queued.any {it.mutation.recordId==PARENT_ID && it.mutation.payload!!["deleted_at"]!=JsonNull})
    }
    @Test fun `maintenance protects local future edits and leaves foreign viewer category untouched`()=runTest {
        val raw=duplicateRemote().serverRows!!.values.toList()
        val local=local(row("Pending name",LATER,42)).apply {queued[0]=queued[0].copy(nextAttemptAtEpochMillis=Long.MAX_VALUE)}
        val before=local.queued.toList()
        val viewer=TransactionCategoryRecord.fromCloudRecord(raw.last()).copy(ownerUserId=DEVICE).toCloudRecord().copy(ownerUserId=OWNER)
        assertEquals(CategoryMaintenanceSummary(deferredGroups=1),maintenance(local).reconcileObserved(UserId(OWNER),raw+viewer))
        assertEquals(before,local.queued)
        assertEquals("Pending name",local.records[CATEGORY_ID]!!.payload.string("name"))
        assertEquals(CategoryMaintenanceSummary(),maintenance(local).reconcileObserved(UserId(OWNER),listOf(viewer)))
    }
    @Test fun `maintenance stale snapshot and cancellation never erase newer local mutation`()=runTest {
        val raw=duplicateRemote().serverRows!!.values.toList()
        val local=local().apply {queued.clear();records.putAll(raw.associateBy {it.id})}
        val newer=pending(row("Concurrent edit",LATER,42))
        local.beforeObservedCommit={local.queued.add(newer);local.records[CATEGORY_ID]=row("Concurrent edit",LATER,42)}
        assertEquals(CategoryMaintenanceSummary(staleGroups=1),maintenance(local).reconcileObserved(UserId(OWNER),raw))
        assertEquals(newer,local.queued.single())
        local.beforeObservedCommit={throw CancellationException("cancel maintenance")}
        val failure=runCatching {maintenance(local).reconcileObserved(UserId(OWNER),raw)}.exceptionOrNull()
        assertTrue(failure is CancellationException)
        assertEquals(newer,local.queued.single())
    }
    @Test fun `invalid owned remote metadata fails closed before any maintenance write`()=runTest {
        val malformed=row(version=7).let {it.copy(payload=JsonObject(it.payload+("sync_version" to JsonPrimitive("7"))))}
        val local=local().apply {queued.clear()}
        assertTrue(runCatching {maintenance(local).reconcileObserved(UserId(OWNER),listOf(malformed))}.isFailure)
        assertTrue(local.queued.isEmpty())
        assertEquals(row(),local.records[CATEGORY_ID])
    }
    @Test fun `completed pull adopts an untouched offline seed tombstone without cloud writes`()=runTest {
        val local=local()
        val tombstone=TransactionCategoryRecord.fromCloudRecord(row("Deleted cloud",NOW,7)).copy(deletedAt=NOW).toCloudRecord()
        assertEquals(CategoryMaintenanceSummary(processedGroups=1),maintenance(local).reconcileObserved(UserId(OWNER),listOf(tombstone)))
        assertEquals(tombstone,local.records[CATEGORY_ID])
        assertTrue(local.queued.isEmpty())
    }
    @Test fun `completed pull merges edited offline seed and queues ordered legacy cleanup locally`()=runTest {
        val source=row().let {it.copy(payload=JsonObject(it.payload+("is_favorite" to JsonPrimitive(true))))}
        val local=local(source)
        val rows=duplicateRemote().serverRows!!.values.toList()
        assertEquals(CategoryMaintenanceSummary(processedGroups=1),maintenance(local).reconcileObserved(UserId(OWNER),rows))
        assertEquals(JsonPrimitive(true),local.records[CATEGORY_ID]!!.payload["is_favorite"])
        assertEquals("Live legacy",local.records[CATEGORY_ID]!!.payload.string("name"))
        assertEquals(42L,local.queued.single {it.mutation.recordId==CATEGORY_ID}.mutation.baseVersion)
        assertTrue(local.queued.single {it.mutation.recordId==CATEGORY_ID}.remoteIdentityObserved)
        assertNull(local.records[CATEGORY_ID]!!.deletedAt)
        assertTrue(local.records[CHILD_ID]!!.deletedAt!=null)
    }
    @Test fun `completed pull defers offline seed adoption when real alias has future user edit`()=runTest {
        val rows=duplicateRemote().serverRows!!.values.toList()
        val local=local().apply {
            records[CHILD_ID]=rows.last()
            queued.add(pending(rows.last()).copy(nextAttemptAtEpochMillis=Long.MAX_VALUE,remoteIdentityObserved=true))
        }
        val before=local.queued.toList()
        assertEquals(CategoryMaintenanceSummary(deferredGroups=1),maintenance(local).reconcileObserved(UserId(OWNER),rows))
        assertEquals(before,local.queued)
        assertEquals(row(),local.records[CATEGORY_ID])
    }
    private class FakeLocalStore(
        records: Map<String, CloudRecord>,
        val queued: MutableList<QueuedMutation>,
    ) : LocalStore {
        val records = records.toMutableMap()

        var beforeObservedCommit:(()->Unit)?=null
        override suspend fun commitObservedSystemCategoryMaintenance(expected:CategoryReferenceSnapshot,key:String,remote:List<CloudRecord>,catalog:SystemCategoryCatalog,deviceId:String,now:String):Boolean {
            beforeObservedCommit?.invoke()
            try {expected.requireUnchanged(categoryReferenceSnapshot(expected.owner))} catch (_:IllegalArgumentException) {return false}
            val plan=planObservedSystemCategoryMaintenance(expected,key,remote,catalog,deviceId,now) ?: return true
            plan.retainedCategories.forEach {records[it.id]=it}
            records[plan.adoption.target.id]=plan.adoption.target
            plan.adoption.mutation?.let {queued.add(QueuedMutation(it,0,0,null,true))}
            plan.references.mutations.forEach {change ->
                records[change.record.id]=change.record
                queued.removeAll {it.mutation.entity==change.mutation.entity && it.mutation.recordId==change.record.id}
                queued.add(QueuedMutation(change.mutation,0,0,null,true))
            }
            return true
        }
        override suspend fun categoryReferenceSnapshot(owner:UserId)=CategoryReferenceSnapshot(owner,
            categoryReferenceEntities.associateWith {entity -> records.values.filter {it.entity==entity.table && it.ownerUserId==owner.value}},
            queued.filter {it.mutation.subjectUserId==owner.value && it.mutation.entity in categoryReferenceEntities},emptyList())
        override suspend fun commitSystemCategoryIdentityMigration(expected:CategoryReferenceSnapshot,queued:QueuedMutation,remote:List<CloudRecord>,catalog:SystemCategoryCatalog,deviceId:String,now:String):Boolean {
            replacementOnAcknowledge?.let {newer ->
                this.queued.remove(queued);this.queued.add(newer)
                replacementRecordOnAcknowledge?.let {records[it.id]=it}
                replacementOnAcknowledge=null
                return false
            }
            try {expected.requireUnchanged(categoryReferenceSnapshot(expected.owner))} catch (_:IllegalArgumentException) {return false}
            val plan=planSystemCategoryIdentityMigration(expected,queued,remote,catalog,deviceId,now)
            this.queued.remove(queued)
            if(plan.removesSourceIdentity) records.remove(plan.adoption.source.id)
            plan.retainedCategories.forEach {records[it.id]=it}
            records[plan.adoption.target.id]=plan.adoption.target
            plan.adoption.mutation?.let {this.queued.add(QueuedMutation(it,0,0,null,remoteIdentityObserved=true))}
            plan.references.mutations.forEach {change ->
                records[change.record.id]=change.record
                this.queued.removeAll {it.mutation.entity==change.mutation.entity && it.mutation.recordId==change.record.id}
                this.queued.add(QueuedMutation(change.mutation,0,0,null))
            }
            return true
        }
        var replacementOnAcknowledge: QueuedMutation? = null
        var replacementRecordOnAcknowledge: CloudRecord? = null
        override fun observe(entity: String, ownerUserId: UserId): Flow<List<CloudRecord>> =
            MutableStateFlow(records.values.toList())
        override fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>> =
            MutableStateFlow(emptyList())
        override suspend fun record(ownerUserId: UserId, entity: String, recordId: String) = records[recordId]?.takeIf {it.entity==entity && it.ownerUserId==ownerUserId.value}
        override suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation) = Unit
        override suspend fun pendingMutations(
            ownerUserId: UserId,
            entity: CloudEntity,
            dueAtEpochMillis: Long,
            limit: Int,
        ) = queued.filter {
            it.mutation.subjectUserId == ownerUserId.value &&
                it.mutation.entity == entity &&
                it.nextAttemptAtEpochMillis <= dueAtEpochMillis
        }.take(limit)

        override suspend fun acknowledgeMutation(mutation: QueuedMutation, remoteRecord: CloudRecord): Boolean {
            replacementOnAcknowledge?.let { newer ->
                queued.remove(mutation)
                queued.add(newer)
                replacementRecordOnAcknowledge?.let { records[it.id]=it }
                replacementOnAcknowledge = null
                return false
            }
            if (!queued.remove(mutation)) return false
            records[remoteRecord.id] = remoteRecord
            return true
        }

        override suspend fun recordMutationFailure(
            mutation: QueuedMutation,
            nextAttemptAtEpochMillis: Long,
            errorCode: String,
        ): Boolean {
            val index = queued.indexOf(mutation)
            if (index < 0) return false
            queued[index] = mutation.copy(
                attemptCount = mutation.attemptCount + 1,
                nextAttemptAtEpochMillis = nextAttemptAtEpochMillis,
                lastError = errorCode,
            )
            return true
        }

        override suspend fun replacePullSnapshot(ownerUserId: UserId, entity: String, records: List<CloudRecord>) = Unit
        override suspend fun pendingMutationRecordIds(ownerUserId: UserId, entity: String) =
            queued.filter {it.mutation.entity.table==entity && it.mutation.subjectUserId==ownerUserId.value}.mapTo(mutableSetOf()) { it.mutation.recordId }
        override suspend fun clearAccount(ownerUserId: UserId) = Unit
    }

    private class FakeRemoteStore : RemoteMutationStore {
        var serverRows:MutableMap<String,CloudRecord>?=null
        var updateFailure:Throwable?=null
        val systemPages=ArrayDeque<SystemCategoryPage>()
        var keyFailure:Throwable?=null
        var keyCalls=0
        val keyOffsets=mutableListOf<Int>()
        var onKey:(()->Unit)?=null
        override suspend fun fetchSystemCategoryPage(systemKey:String,accessToken:String,ownerUserId:UserId,offset:Int,limit:Int):SystemCategoryPage {
            keyCalls++
            keyOffsets.add(offset)
            onKey?.invoke()
            keyFailure?.let {throw it}
            serverRows?.let {return SystemCategoryPage(it.values.filter {row -> (row.payload["system_key"] as? JsonPrimitive)?.content==systemKey},null)}
            if(systemPages.isNotEmpty()) return systemPages.removeFirst()
            return SystemCategoryPage(listOfNotNull(fetchedResults.firstOrNull()),null)
        }
        val fetchedResults = ArrayDeque<CloudRecord?>()
        val fetchFailures = ArrayDeque<Throwable>()
        val createdResults = ArrayDeque<CloudRecord>()
        val createFailures = ArrayDeque<Throwable>()
        val updatedResults = ArrayDeque<CloudRecord?>()
        val createdPayloads = mutableListOf<JsonObject>()
        val updatedPayloads = mutableListOf<JsonObject>()
        val updateExpectedVersions = mutableListOf<Long>()
        var fetchCalls = 0
        var writeCalls = 0

        override suspend fun fetchRecord(
            entity: CloudEntity,
            recordId: String,
            accessToken: String,
            ownerUserId: UserId,
        ): CloudRecord? {
            fetchCalls++
            serverRows?.let {return it[recordId]}
            if (fetchFailures.isNotEmpty()) throw fetchFailures.removeFirst()
            return if (fetchedResults.isNotEmpty()) fetchedResults.removeFirst() else null
        }

        override suspend fun createRecord(
            entity: CloudEntity,
            accessToken: String,
            ownerUserId: UserId,
            payload: JsonObject,
        ): CloudRecord {
            writeCalls++
            createdPayloads.add(payload)
            if (createFailures.isNotEmpty()) throw createFailures.removeFirst()
            return createdResults.removeFirst()
        }

        override suspend fun conditionalUpdate(
            entity: CloudEntity,
            recordId: String,
            accessToken: String,
            ownerUserId: UserId,
            expectedVersion: Long,
            payload: JsonObject,
        ): CloudRecord? {
            writeCalls++
            updateExpectedVersions.add(expectedVersion)
            updatedPayloads.add(payload)
            updateFailure?.let {throw it}
            serverRows?.let {rows ->
                val previous=rows[recordId] ?: return null
                if(previous.syncVersion!=expectedVersion) return null
                if(payload["deleted_at"]==JsonNull && rows.values.any {it.id!=recordId && it.deletedAt==null && it.payload["system_key"]==payload["system_key"]})
                    throw SupabaseHttpException(409,"active system key unique violation")
                val version=Math.addExact(expectedVersion,1)
                val result=previous.copy(payload=JsonObject(payload+("sync_version" to JsonPrimitive(version))),syncVersion=version,
                    updatedAt=(payload["updated_at"] as JsonPrimitive).content,deletedAt=(payload["deleted_at"] as? JsonPrimitive)?.takeUnless {it==JsonNull}?.content)
                rows[recordId]=result
                return result
            }
            return if (updatedResults.isNotEmpty()) updatedResults.removeFirst() else null
        }
    }

    private fun JsonObject.string(key: String) = (get(key) as JsonPrimitive).content
    private fun JsonObject.long(key: String) = (get(key) as JsonPrimitive).content.toLong()

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val CATEGORY_ID = "b37f0c1b-b967-5f0a-ba59-0e795d0a4d75"
        const val PARENT_ID = "44444444-4444-4444-4444-444444444444"
        const val CHILD_ID = "55555555-5555-5555-5555-555555555555"
        const val DEVICE = "33333333-3333-3333-3333-333333333333"
        const val TOKEN = "access-token"
        const val NOW = "2026-09-23T10:00:00.000Z"
        const val LATER = "2026-09-23T11:00:00.000Z"
        const val NOW_MILLIS = 1_795_000_000_000L
    }
}
