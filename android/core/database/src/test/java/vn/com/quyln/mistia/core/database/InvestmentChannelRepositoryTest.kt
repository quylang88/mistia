package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InvestmentChannelRepositoryTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="44444444-4444-4444-4444-444444444444"
    private val now="2026-10-21T00:00:00Z"
    private val earlier="2026-10-20T00:00:00Z"
    private fun channel()=InvestmentChannelRecord(id,owner.value,"Cards","chart.line.uptrend.xyaxis","#9A67FF",7,false,null,earlier,earlier,null,9007199254740993L,device)
    private fun CloudRecord.with(vararg fields:Pair<String,JsonElement>)=copy(payload=JsonObject(payload+fields.toMap()))
    private class Store:LocalStore by BudgetMemoryStore() {
        val memory=BudgetMemoryStore()
        var beforeCommit:(suspend ()->Unit)?=null
        var commits=0
        override suspend fun investmentChannelSnapshot(owner:UserId)=InvestmentChannelSnapshot(owner,InvestmentChannelSnapshot.entities.flatMap {memory.recordsIncludingDeleted(owner,it.table)})
        override fun observeInvestmentChannelSnapshot(owner:UserId)=MutableStateFlow(InvestmentChannelSnapshot(owner,emptyList()))
        override suspend fun commitInvestmentChannels(expected:InvestmentChannelSnapshot,mutations:List<Pair<CloudRecord,PendingMutation>>):Boolean {
            beforeCommit?.also{beforeCommit=null}?.invoke()
            val current=investmentChannelSnapshot(expected.owner)
            if(current.rows.sortedWith(compareBy(CloudRecord::entity,CloudRecord::id))!=expected.rows.sortedWith(compareBy(CloudRecord::entity,CloudRecord::id))) return false
            memory.commitMutations(mutations);commits++;return true
        }
        override suspend fun recordsIncludingDeleted(ownerUserId:UserId,entity:String)=memory.recordsIncludingDeleted(ownerUserId,entity)
        override suspend fun record(ownerUserId:UserId,entity:String,recordId:String)=memory.record(ownerUserId,entity,recordId)
        suspend fun seed(row:CloudRecord){memory.commitMutation(row,PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,row.ownerUserId,MutationKind.UPSERT,row.payload,row.updatedAt!!,row.syncVersion,"44444444-4444-4444-4444-444444444444"))}
        fun queues(owner:UserId)=memory.outboxRows(owner.value)
    }
    private fun repo(store:Store)=OfflineFirstInvestmentRepository(store)
    private fun reason(result:Result<*>)=(result.exceptionOrNull() as? InvestmentChannelException)?.reason
    private fun wallet(code:String="USD")=WalletDraft(id=investmentSystemWalletId(owner),name="Old name",kind=WalletKind.CASH,currencyCode=code,openingBalanceMinor=123)
        .toMutation(owner,null,device,earlier).record
    @Test fun `create stores stable channel and canonical wallet atomically with complete nulls and replay safety`()=runTest {
        val store=Store();val repo=repo(store)
        val saved=repo.saveChannel(owner,InvestmentChannelDraft(id,"  Collectibles  "),"VND",device,now).getOrThrow()
        assertEquals("Collectibles",saved.name);assertEquals(id,saved.id);assertEquals(0,saved.sortOrder);assertEquals(0L,saved.syncVersion)
        val wallet=LedgerWalletRecord.fromCloudRecord(store.record(owner,CloudEntity.LEDGER_WALLET.table,investmentSystemWalletId(owner))!!)
        assertEquals(WalletKind.INVESTMENT,wallet.kind);assertEquals("VND",wallet.currencyCode);assertEquals(0L,wallet.openingBalanceMinor);assertEquals(Int.MAX_VALUE-100,wallet.sortOrder)
        assertEquals(1,store.commits);assertEquals(2,store.queues(owner).size)
        val pending=store.queues(owner).single{it.entity==CloudEntity.INVESTMENT_CHANNEL}
        assertEquals(0L,pending.baseVersion);assertSame(JsonNull,pending.payload!!["archived_at"]);assertSame(JsonNull,pending.payload!!["deleted_at"])
        val before=store.investmentChannelSnapshot(owner);val queue=store.queues(owner)
        assertEquals(saved,repo.saveChannel(owner,InvestmentChannelDraft(id,"Collectibles"),"JPY",device,"2026-10-22T00:00:00Z").getOrThrow())
        assertEquals(before,store.investmentChannelSnapshot(owner));assertEquals(queue,store.queues(owner));assertEquals(1,store.commits)
    }
    @Test fun `existing canonical wallet retains accounting currency version created and unknown fields`()=runTest {
        val store=Store();val raw=wallet().copy(syncVersion=9007199254740995L).with("sync_version" to JsonPrimitive(9007199254740995L),"future_flag" to JsonPrimitive("preserve"),"is_archived" to JsonPrimitive(true),"archived_at" to JsonPrimitive(earlier))
        store.seed(raw);repo(store).saveChannel(owner,InvestmentChannelDraft(id,"Cards"),"VND",device,now).getOrThrow()
        val actual=store.record(owner,raw.entity,raw.id)!!
        for(key in listOf("currency_code","created_at","sync_version","future_flag")) assertEquals(key,raw.payload[key],actual.payload[key])
        assertEquals(9007199254740995L,actual.syncVersion);assertEquals(JsonPrimitive(0),actual.payload["opening_balance_minor"]);assertEquals(JsonPrimitive(false),actual.payload["is_archived"])
        assertSame(JsonNull,actual.payload["archived_at"]);assertEquals(9007199254740995L,store.queues(owner).single{it.entity==CloudEntity.LEDGER_WALLET}.baseVersion)
    }
    @Test fun `rename retains all frozen raw metadata and exact version using visible source proof`()=runTest {
        val store=Store();val original=channel();val raw=original.toCloudRecord().with("future_flag" to JsonPrimitive(true))
        store.seed(raw);val saved=repo(store).saveChannel(owner,InvestmentChannelDraft(id," Renamed ",original),"JPY",device,now).getOrThrow()
        assertEquals("Renamed",saved.name);assertEquals(original.syncVersion,saved.syncVersion)
        val actual=store.record(owner,raw.entity,id)!!
        for((key,value) in raw.payload) if(key !in setOf("name","updated_at","last_modified_by_device_id")) assertEquals(key,value,actual.payload[key])
        assertEquals(1,store.queues(owner).size);assertEquals(original.syncVersion,store.queues(owner).single().baseVersion)
    }
    @Test fun `source changing at CAS is not overwritten by an older rename`()=runTest {
        val store=Store();val original=channel();store.seed(original.toCloudRecord())
        store.beforeCommit={store.seed(original.copy(name="Newer name",updatedAt=now).toCloudRecord())}
        assertEquals(InvestmentChannelError.STALE_RECORD,reason(repo(store).saveChannel(owner,InvestmentChannelDraft(id,"Older edit",original),"JPY",device,now)))
        assertEquals(JsonPrimitive("Newer name"),store.record(owner,CloudEntity.INVESTMENT_CHANNEL.table,id)!!.payload["name"]);assertEquals(0,store.commits)
    }
    private suspend fun withPosition(store:Store,quantity:JsonElement):CloudRecord {
        val assetId="33333333-3333-3333-3333-333333333333";val tradeId="55555555-5555-5555-5555-555555555555"
        val asset=channel().toCloudRecord().copy(entity=CloudEntity.INVESTMENT_ASSET.table,id=assetId).with("id" to JsonPrimitive(assetId),"channel_id" to JsonPrimitive(id))
        val trade=channel().toCloudRecord().copy(entity=CloudEntity.INVESTMENT_TRADE.table,id=tradeId).with("id" to JsonPrimitive(tradeId),"asset_id" to JsonPrimitive(assetId),"occurred_at" to JsonPrimitive(now),"position_quantity_after_decimal_string" to quantity)
        store.seed(asset);store.seed(trade);return trade
    }
    @Test fun `archive blocks positive and unreadable current quantity before any write`()=runTest {
        for((quantity,error) in listOf(JsonPrimitive("0.01") to InvestmentChannelError.OPEN_POSITION,JsonPrimitive("broken") to InvestmentChannelError.UNREADABLE_POSITION,JsonPrimitive(1) to InvestmentChannelError.UNREADABLE_POSITION)) {
            val store=Store();val original=channel();store.seed(original.toCloudRecord());withPosition(store,quantity)
            val before=store.investmentChannelSnapshot(owner);val queue=store.queues(owner)
            assertEquals(error,reason(repo(store).archiveChannel(owner,original,device,now)));assertEquals(before,store.investmentChannelSnapshot(owner));assertEquals(queue,store.queues(owner));assertEquals(0,store.commits)
        }
    }
    @Test fun `closed positions archive and restore preserve identity without changing trades or wallet`()=runTest {
        val store=Store();val original=channel();store.seed(original.toCloudRecord());val trade=withPosition(store,JsonPrimitive("0"))
        repo(store).archiveChannel(owner,original,device,now).getOrThrow()
        val archived=original.copy(isArchived=true,archivedAt=now,updatedAt=now)
        assertEquals(JsonPrimitive(true),store.record(owner,CloudEntity.INVESTMENT_CHANNEL.table,id)!!.payload["is_archived"])
        repo(store).restoreChannel(owner,archived,device,"2026-10-22T00:00:00Z").getOrThrow()
        val actual=store.record(owner,CloudEntity.INVESTMENT_CHANNEL.table,id)!!;assertEquals(JsonPrimitive(false),actual.payload["is_archived"]);assertSame(JsonNull,actual.payload["archived_at"])
        assertEquals(trade,store.record(owner,trade.entity,trade.id));assertTrue(store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_WALLET.table).isEmpty());assertEquals(2,store.commits)
    }
    @Test fun `invalid identity blank names foreign visible source and bad existing currency never write`()=runTest {
        for((draft,error) in listOf(InvestmentChannelDraft("not-uuid","Cards") to InvestmentChannelError.INVALID_IDENTITY,InvestmentChannelDraft(id,"  ") to InvestmentChannelError.NAME_REQUIRED,InvestmentChannelDraft(id,"Edit",channel().copy(ownerUserId=other.value)) to InvestmentChannelError.INVALID_IDENTITY)) {
            val store=Store();assertEquals(error,reason(repo(store).saveChannel(owner,draft,"JPY",device,now)));assertEquals(0,store.commits);assertTrue(store.queues(owner).isEmpty())
        }
        val store=Store();store.seed(wallet().with("currency_code" to JsonPrimitive("???")));val before=store.investmentChannelSnapshot(owner)
        assertEquals(InvestmentChannelError.INVALID_CURRENCY,reason(repo(store).saveChannel(owner,InvestmentChannelDraft(id,"Cards"),"JPY",device,now)));assertEquals(before,store.investmentChannelSnapshot(owner));assertEquals(0,store.commits)
    }
    @Test fun `failed atomic persistence and cancellation leave no partial channel wallet or queues`()=runTest {
        for(cancel in listOf(false,true)) {
            val base=Store();val failing=object:LocalStore by base {override suspend fun commitInvestmentChannels(expected:InvestmentChannelSnapshot,mutations:List<Pair<CloudRecord,PendingMutation>>):Boolean {if(cancel) throw CancellationException("account changed") else throw IllegalStateException("disk failed")}}
            val result=runCatching {OfflineFirstInvestmentRepository(failing).saveChannel(owner,InvestmentChannelDraft(id,"Cards"),"JPY",device,now)}
            if(cancel) assertTrue(result.exceptionOrNull() is CancellationException) else assertTrue(result.getOrThrow().isFailure)
            assertTrue(base.investmentChannelSnapshot(owner).rows.isEmpty());assertTrue(base.queues(owner).isEmpty())
        }
    }
    @Test fun `damaged explicit channel version cannot masquerade as valid envelope metadata`()=runTest {
        val store=Store();val original=channel();store.seed(original.toCloudRecord().with("sync_version" to JsonPrimitive("broken")))
        val before=store.investmentChannelSnapshot(owner);val queues=store.queues(owner)
        assertEquals(InvestmentChannelError.UNREADABLE_SOURCE,reason(repo(store).saveChannel(owner,InvestmentChannelDraft(id,"Rename",original),"JPY",device,now)))
        assertEquals(before,store.investmentChannelSnapshot(owner));assertEquals(queues,store.queues(owner));assertEquals(0,store.commits)
    }

    @Test fun `semantic acknowledgement metadata does not invalidate visible source or lose latest Long version`()=runTest {
        val store=Store();val visible=channel();val latest=visible.copy(syncVersion=9007199254740999L,updatedAt=now,lastModifiedByDeviceId=id)
        val raw=latest.toCloudRecord().with("created_at" to JsonPrimitive("2026-10-20T09:00:00+09:00"),"future_flag" to JsonPrimitive(true))
        store.seed(raw);val saved=repo(store).saveChannel(owner,InvestmentChannelDraft(id,"Acknowledged edit",visible),"JPY",device,now).getOrThrow()
        assertEquals(latest.syncVersion,saved.syncVersion);assertEquals(9007199254740999L,store.queues(owner).single().baseVersion)
        val actual=store.record(owner,raw.entity,id)!!;assertEquals(raw.payload["created_at"],actual.payload["created_at"]);assertEquals(JsonPrimitive(true),actual.payload["future_flag"])
    }
    @Test fun `position becoming open during CAS is revalidated before archive can write`()=runTest {
        val store=Store();val original=channel();store.seed(original.toCloudRecord());val trade=withPosition(store,JsonPrimitive("0"))
        store.beforeCommit={store.seed(trade.with("position_quantity_after_decimal_string" to JsonPrimitive("1")))}
        assertEquals(InvestmentChannelError.OPEN_POSITION,reason(repo(store).archiveChannel(owner,original,device,now)))
        assertEquals(original.toCloudRecord(),store.record(owner,CloudEntity.INVESTMENT_CHANNEL.table,id));assertEquals(0,store.commits)
    }
    @Test fun `read source retains scoped damage and tombstones but never relabels another owner snapshot`()=runTest {
        val base=Store();val good=channel().toCloudRecord();val damaged=good.copy(id=device).with("id" to JsonPrimitive(device),"name" to buildJsonObject{put("bad",true)})
        val deleted=good.copy(id="33333333-3333-3333-3333-333333333333",deletedAt=now).with("id" to JsonPrimitive("33333333-3333-3333-3333-333333333333"))
        val foreign=good.copy(ownerUserId=other.value);val bodyWrong=good.with("user_id" to JsonPrimitive(other.value))
        val values=MutableStateFlow(InvestmentChannelSnapshot(owner,listOf(good,damaged,deleted,foreign,bodyWrong,good.copy(entity=CloudEntity.LEDGER_TRANSACTION.table))))
        val source=object:LocalStore by base {override fun observeInvestmentChannelSnapshot(owner:UserId)=values}
        val result=OfflineFirstInvestmentRepository(source).observeChannelSnapshot(owner).first()
        assertEquals(listOf(good,damaged,deleted),result.rows);assertTrue(base.queues(owner).isEmpty())
        values.value=InvestmentChannelSnapshot(other,listOf(foreign))
        assertTrue(runCatching{OfflineFirstInvestmentRepository(source).observeChannelSnapshot(owner).first()}.exceptionOrNull() is IllegalArgumentException)
    }

    @Test fun `damaged explicit accounting wallet version is not repaired by inventing a valid base`()=runTest {
        for(value in listOf(JsonPrimitive("broken"),JsonPrimitive("9007199254740995"),JsonNull,JsonPrimitive(1.5))) {
            val store=Store();val raw=wallet().copy(syncVersion=9007199254740995L).with("sync_version" to value);store.seed(raw)
            val before=store.investmentChannelSnapshot(owner);val queues=store.queues(owner)
            assertEquals(InvestmentChannelError.UNREADABLE_SOURCE,reason(repo(store).saveChannel(owner,InvestmentChannelDraft(id,"Cards"),"VND",device,now)))
            assertEquals(before,store.investmentChannelSnapshot(owner));assertEquals(queues,store.queues(owner));assertEquals(0,store.commits)
        }
    }

    @Test fun `existing wallet using envelope version preserves absent body version`()=runTest {
        val store=Store();val base=wallet().copy(syncVersion=9007199254740995L)
        val raw=base.copy(payload=JsonObject(base.payload-"sync_version"));store.seed(raw)
        repo(store).saveChannel(owner,InvestmentChannelDraft(id,"Cards"),"VND",device,now).getOrThrow()
        val actual=store.record(owner,raw.entity,raw.id)!!
        assertFalse(actual.payload.containsKey("sync_version"));assertEquals(raw.syncVersion,actual.syncVersion)
        assertEquals(raw.syncVersion,store.queues(owner).single{it.entity==CloudEntity.LEDGER_WALLET}.baseVersion)
        assertEquals(JsonPrimitive("USD"),actual.payload["currency_code"])
    }

    @Test fun `channel names follow Swift whitespace and newline trimming including NEL`()=runTest {
        val store=Store();val repo=repo(store)
        assertEquals(InvestmentChannelError.NAME_REQUIRED,reason(repo.saveChannel(owner,InvestmentChannelDraft(id,"\u0085 \n\u00a0"),"VND",device,now)))
        assertTrue(store.queues(owner).isEmpty())
        val saved=repo.saveChannel(owner,InvestmentChannelDraft(id,"\u0085 Cards \u0085"),"VND",device,now).getOrThrow()
        assertEquals("Cards",saved.name);assertEquals(2,store.queues(owner).size)
    }

    @Test fun `channel name trimming matches the complete Foundation whitespace scalar set`()=runTest {
        // Captured from Foundation CharacterSet.whitespacesAndNewlines, not Java's broader control set.
        val whitespace=(0x9..0xd).toSet()+setOf(0x20,0x85,0xa0,0x1680,0x2028,0x2029,0x202f,0x205f,0x3000)+(0x2000..0x200b).toSet()
        for(code in 0..0xffff){
            val text=code.toChar().toString()
            assertEquals("scalar ${code.toString(16)}",code in whitespace,normalizedInvestmentChannelName(text).isEmpty())
        }
        val store=Store();val saved=repo(store).saveChannel(owner,InvestmentChannelDraft(id,"\u200b Cards \u200b"),"VND",device,now).getOrThrow()
        assertEquals("Cards",saved.name)
        val control=repo(store).saveChannel(owner,InvestmentChannelDraft(device,"\u001c"),"VND",device,now).getOrThrow()
        assertEquals("\u001c",control.name)
    }

}
