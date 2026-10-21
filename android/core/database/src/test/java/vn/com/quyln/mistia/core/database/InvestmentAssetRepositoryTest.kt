package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InvestmentAssetRepositoryTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val id="22222222-2222-2222-2222-222222222222"
    private val channelId="33333333-3333-3333-3333-333333333333"
    private val device="44444444-4444-4444-4444-444444444444"
    private val now="2026-10-21T00:00:00Z"
    private val later="2026-10-22T00:00:00Z"
    private fun channel()=InvestmentChannelRecord(channelId,owner.value,"Cards","chart.line.uptrend.xyaxis","#9A67FF",0,false,null,now,now,null,0,device).toCloudRecord()
    private fun draft(expected:InvestmentAssetRecord?=null,name:String=" Product ")=InvestmentAssetDraft(id,channelId,name,"VND"," box ",expected)
    private class Store:LocalStore by BudgetMemoryStore() {
        val memory=BudgetMemoryStore()
        var commits=0
        var beforeCommit:(suspend ()->Unit)?=null
        override suspend fun investmentAssetSnapshot(owner:UserId)=InvestmentAssetSnapshot(owner,InvestmentAssetSnapshot.entities.flatMap{memory.recordsIncludingDeleted(owner,it.table)})
        override fun observeInvestmentAssetSnapshot(owner:UserId)=MutableStateFlow(InvestmentAssetSnapshot(owner,emptyList()))
        override suspend fun commitInvestmentAssetMutation(expected:InvestmentAssetSnapshot,request:InvestmentAssetRequest,deviceId:String,now:String):Boolean {
            beforeCommit?.also{beforeCommit=null}?.invoke()
            if(runCatching{expected.requireUnchanged(investmentAssetSnapshot(expected.owner))}.isFailure)return false
            val plan=planInvestmentAssetMutation(expected,request,deviceId,now)
            memory.commitMutations(plan.mutations);commits++;return true
        }
        suspend fun seed(raw:CloudRecord){memory.commitMutation(raw,PendingMutation(CloudEntity.fromTable(raw.entity)!!,raw.id,raw.ownerUserId,MutationKind.UPSERT,raw.payload,raw.updatedAt!!,raw.syncVersion,"44444444-4444-4444-4444-444444444444"))}
        fun queues(owner:UserId)=memory.outboxRows(owner.value)
    }
    private suspend fun prepared()=Store().also{it.seed(channel())}
    private fun reason(result:Result<*>)=(result.exceptionOrNull() as? InvestmentAssetException)?.reason

    @Test fun createStoresOneOwnedAssetAndQueueThenStableReplayDoesNotDuplicate()=runTest {
        val store=prepared();val repo=OfflineFirstInvestmentRepository(store)
        val saved=repo.saveAsset(owner,draft(),device,now).getOrThrow()
        assertEquals("Product",saved.name);assertEquals("box",saved.defaultUnitLabel);assertEquals(id,saved.id)
        assertEquals(1,store.commits);assertEquals(2,store.queues(owner).size)
        assertEquals(1,store.investmentAssetSnapshot(owner).records(CloudEntity.INVESTMENT_ASSET).size)
        assertTrue(store.queues(other).isEmpty());assertTrue(store.investmentAssetSnapshot(other).rows.isEmpty())
        val before=store.investmentAssetSnapshot(owner);val queue=store.queues(owner)
        assertEquals(saved,repo.saveAsset(owner,draft(),device,later).getOrThrow())
        assertEquals(before,store.investmentAssetSnapshot(owner));assertEquals(queue,store.queues(owner));assertEquals(1,store.commits)
    }
    @Test fun renameArchiveRestoreKeepTheSameIdentityAndNoWalletOrTradeMutations()=runTest {
        val store=prepared();val repo=OfflineFirstInvestmentRepository(store)
        val saved=repo.saveAsset(owner,draft(),device,now).getOrThrow()
        val renamed=repo.saveAsset(owner,draft(saved,"Updated"),device,later).getOrThrow()
        repo.archiveAsset(owner,renamed,device,later).getOrThrow()
        val archived=InvestmentAssetRecord.fromCloudRecord(store.investmentAssetSnapshot(owner).records(CloudEntity.INVESTMENT_ASSET).single())
        assertTrue(archived.isArchived)
        repo.restoreAsset(owner,archived,device,later).getOrThrow()
        val restored=InvestmentAssetRecord.fromCloudRecord(store.investmentAssetSnapshot(owner).records(CloudEntity.INVESTMENT_ASSET).single())
        assertEquals(id,restored.id);assertEquals(saved.createdAt,restored.createdAt);assertEquals("Updated",restored.name)
        assertFalse(restored.isArchived);assertNull(restored.archivedAt);assertEquals(2,store.queues(owner).size)
        assertTrue(store.investmentAssetSnapshot(owner).records(CloudEntity.LEDGER_WALLET).isEmpty())
        assertTrue(store.investmentAssetSnapshot(owner).records(CloudEntity.INVESTMENT_TRADE).isEmpty())
    }
    @Test fun newerVisibleEditAtCasIsNotOverwrittenByAnOlderForm()=runTest {
        val store=prepared();val repo=OfflineFirstInvestmentRepository(store);val visible=repo.saveAsset(owner,draft(),device,now).getOrThrow()
        store.beforeCommit={store.seed(visible.copy(name="Newer",updatedAt=later).toCloudRecord())}
        assertEquals(InvestmentAssetError.STALE_RECORD,reason(repo.saveAsset(owner,draft(visible,"Older"),device,later)))
        assertEquals("Newer",store.investmentAssetSnapshot(owner).records(CloudEntity.INVESTMENT_ASSET).single().payload.financeRawString("name"))
        assertEquals(1,store.commits)
    }
    @Test fun channelArchivedAtCasStopsCreateWithoutAnyPartialAssetQueue()=runTest {
        val store=prepared();val repo=OfflineFirstInvestmentRepository(store)
        store.beforeCommit={store.seed(channel().copy(payload=JsonObject(channel().payload+("is_archived" to JsonPrimitive(true)))))}
        assertEquals(InvestmentAssetError.MISSING_CHANNEL,reason(repo.saveAsset(owner,draft(),device,now)))
        assertTrue(store.investmentAssetSnapshot(owner).records(CloudEntity.INVESTMENT_ASSET).isEmpty())
        assertEquals(1,store.queues(owner).size);assertEquals(0,store.commits)
    }
    @Test fun accountCancellationPropagatesAndPersistenceFailureRetainsAllRowsAndQueues()=runTest {
        for(cancel in listOf(false,true)) {
            val store=prepared()
            val failing=object:LocalStore by store {
                override suspend fun commitInvestmentAssetMutation(expected:InvestmentAssetSnapshot,request:InvestmentAssetRequest,deviceId:String,now:String):Boolean {
                    if(cancel)throw CancellationException("changed owner") else throw IllegalStateException("disk failed")
                }
            }
            val before=store.investmentAssetSnapshot(owner);val queue=store.queues(owner)
            val result=runCatching{OfflineFirstInvestmentRepository(failing).saveAsset(owner,draft(),device,now)}
            if(cancel)assertTrue(result.exceptionOrNull() is CancellationException)else assertTrue(result.getOrThrow().isFailure)
            assertEquals(before,store.investmentAssetSnapshot(owner));assertEquals(queue,store.queues(owner))
        }
    }
    @Test fun observerKeepsScopedDamageButNeverReturnsForeignBodyOrAnotherOwnerSnapshot()=runTest {
        val store=Store();val good=channel()
        val damaged=good.copy(entity=CloudEntity.INVESTMENT_ASSET.table,payload=JsonObject(good.payload+("name" to buildJsonObject{put("broken",true)})))
        val foreign=damaged.copy(ownerUserId=other.value)
        val wrongBody=damaged.copy(payload=JsonObject(damaged.payload+("user_id" to JsonPrimitive(other.value))))
        val values=MutableStateFlow(InvestmentAssetSnapshot(owner,listOf(damaged,foreign,wrongBody)))
        val source=object:LocalStore by store {override fun observeInvestmentAssetSnapshot(owner:UserId)=values}
        assertEquals(listOf(damaged),OfflineFirstInvestmentRepository(source).observeAssetSnapshot(owner).first().rows)
        values.value=InvestmentAssetSnapshot(other,listOf(foreign))
        assertTrue(runCatching{OfflineFirstInvestmentRepository(source).observeAssetSnapshot(owner).first()}.isFailure)
        assertTrue(store.queues(owner).isEmpty())
    }
}
