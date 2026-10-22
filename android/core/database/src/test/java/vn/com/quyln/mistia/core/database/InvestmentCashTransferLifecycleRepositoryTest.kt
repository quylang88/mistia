package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InvestmentCashTransferLifecycleRepositoryTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    private val linked="22222222-2222-4222-8222-222222222222"
    private val selected="33333333-3333-4333-8333-333333333333"
    private val device="44444444-4444-4444-8444-444444444444"
    private val event="55555555-5555-4555-8555-555555555555"
    private val profitId="66666666-6666-4666-8666-666666666666"
    private val cashId="77777777-7777-4777-8777-777777777777"
    private val now="2026-10-22T00:00:00Z"
    private fun wallet(id:String)=WalletDraft(id=id,name="Wallet",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=10000).toMutation(owner,null,device,now).record
    private fun rows():List<CloudRecord> {
        val system=wallet(investmentSystemWalletId(owner)).let{it.copy(syncVersion=9007199254740993L,payload=JsonObject(it.payload+buildJsonObject {
            put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",linked);put("opening_balance_minor",0L);put("sync_version",9007199254740993L);put("future_field","preserve")
        }))}
        fun row(entity:CloudEntity,id:String,fields:JsonObject)=CloudRecord(entity.table,id,owner.value,JsonObject(fields+buildJsonObject {
            put("id",id);put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("sync_version",0L);put("deleted_at",JsonNull)
        }),now,null,0)
        return listOf(system,wallet(linked),wallet(selected),row(CloudEntity.INVESTMENT_TRADE,profitId,buildJsonObject{put("realized_profit_loss_minor",800L);put("accounting_currency_code","VND")}),
            row(CloudEntity.INVESTMENT_POSTING,cashId,buildJsonObject {
                put("wallet_id",linked);put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
                put("amount_minor",300L);put("currency_code","VND");put("accounting_amount_minor",300L);put("accounting_currency_code","VND")
            }))
    }
    private fun mutation(raw:CloudRecord)=raw to PendingMutation(CloudEntity.fromTable(raw.entity)!!,raw.id,raw.ownerUserId,MutationKind.UPSERT,raw.payload,now,raw.syncVersion,device)
    private fun request(withdraw:Boolean=false,otherWallet:Boolean=false):InvestmentCashTransferRequest {
        val records=rows();fun wallet(id:String)=investmentLinkedWalletRecord(records.single{it.id==id})
        val direction=if(withdraw)InvestmentCashTransferDirection.WITHDRAWAL else InvestmentCashTransferDirection.DEPOSIT
        val amount=if(withdraw)300L else 500L
        val target=if(otherWallet)selected else linked
        return InvestmentCashTransferRequest(wallet(investmentSystemWalletId(owner)),wallet(linked),wallet(target),
            InvestmentCashTransferDraft(event,direction,target,amount," Test note ","2026-10-20T12:34:00Z",now),
            InvestmentCashTransferPreview(direction,amount,amount,java.math.BigInteger.valueOf(800),java.math.BigInteger.valueOf(300),java.math.BigInteger.valueOf(300),java.math.BigInteger.valueOf(if(withdraw || !otherWallet)9700 else 10000)),"Transfer")
    }

    private class Store(val memory:BudgetMemoryStore=BudgetMemoryStore()):LocalStore by memory {
        var beforeCommit:(suspend ()->Unit)?=null
        var commits=0
        override suspend fun investmentCashSnapshot(owner:UserId)=InvestmentCashReadSnapshot(owner,InvestmentCashReadSnapshot.entities.flatMap{memory.recordsIncludingDeleted(owner,it.table)})
        override suspend fun commitInvestmentCashTransferLifecycle(expected:InvestmentCashReadSnapshot,request:InvestmentCashTransferLifecycleRequest,deviceId:String,now:String):Boolean {
            beforeCommit?.also{beforeCommit=null}?.invoke()
            if(expected.rows.toSet()!=investmentCashSnapshot(expected.owner).rows.toSet())return false
            memory.commitMutations(planInvestmentCashTransferLifecycle(expected,request,deviceId,now).mutations);commits++;return true
        }
    }
    private suspend fun prepared()=Store().also{
        val source=InvestmentCashReadSnapshot(owner,rows());val created=source.rows+planInvestmentCashTransfer(source,request(),device,now).mutations.map{it.first}
        it.memory.commitMutations(created.map(::mutation))
    }
    private fun reason(result:Result<*>)=(result.exceptionOrNull() as? InvestmentCashTransferException)?.reason

    private val later="2026-10-22T01:00:00Z"
    private suspend fun edit(store:Store):InvestmentCashTransferLifecycleRequest.Save {
        val read=readInvestmentCashTransferLifecycle(store.investmentCashSnapshot(owner),event);val view=read.baseline
        val draft=read.event.draft.copy(amountMinor=400,note="Edited")
        return InvestmentCashTransferLifecycleRequest.Save(read.event,InvestmentCashTransferRequest(view.system,view.linked,view.selected,draft,view.preview.copy(requestedMinor=400),"Edited transfer"))
    }
    @Test fun changedTransferUsesOneAtomicCommitAndKnownSuccessRetryPreservesEveryRowAndQueue()=runTest {
        val store=prepared();val request=edit(store);val repo=OfflineFirstInvestmentRepository(store)
        repo.changeCashTransfer(owner,request,device,later).getOrThrow();assertEquals(1,store.commits)
        val before=store.investmentCashSnapshot(owner);val pending=store.memory.outboxRows(owner.value)
        assertEquals(java.math.BigInteger.valueOf(700),investmentCashFinancialView(before,"VND").availableMinor)
        repo.changeCashTransfer(owner,request,device,later).getOrThrow();assertEquals(1,store.commits);assertEquals(before,store.investmentCashSnapshot(owner));assertEquals(pending,store.memory.outboxRows(owner.value))
        assertTrue(store.investmentCashSnapshot(other).rows.isEmpty());assertTrue(store.memory.outboxRows(other.value).isEmpty())
    }
    @Test fun sourceChangesAtCasCannotSilentlyReplaceFrozenLifecycleConsent()=runTest {
        val store=prepared();val request=edit(store);store.beforeCommit={
            val ledger=store.investmentCashSnapshot(owner).rows.single{it.id==event}.let{it.copy(payload=JsonObject(it.payload+("note" to JsonPrimitive("Changed elsewhere"))))}
            store.memory.commitMutations(listOf(mutation(ledger)))
        }
        assertEquals(InvestmentCashTransferError.STALE_RECORD,reason(OfflineFirstInvestmentRepository(store).changeCashTransfer(owner,request,device,later)));assertEquals(0,store.commits)
        assertEquals(500L,store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_TRANSACTION.table).single().payload.financeRawLong("amount_minor"))
    }
    @Test fun exhaustedLifecycleCasRetriesLeaveBothOldFinancialRowsAndEveryQueueUntouched()=runTest {
        val store=prepared();val request=edit(store);var attempts=0
        val racing=object:LocalStore by store{override suspend fun commitInvestmentCashTransferLifecycle(expected:InvestmentCashReadSnapshot,request:InvestmentCashTransferLifecycleRequest,deviceId:String,now:String):Boolean{attempts++;return false}}
        val before=store.investmentCashSnapshot(owner);val pending=store.memory.outboxRows(owner.value)
        assertEquals(InvestmentCashTransferError.STALE_RECORD,reason(OfflineFirstInvestmentRepository(racing).changeCashTransfer(owner,request,device,later)));assertEquals(3,attempts)
        assertEquals(before,store.investmentCashSnapshot(owner));assertEquals(pending,store.memory.outboxRows(owner.value))
    }
    @Test fun lifecycleDiskFailureReturnsFailureButOwnerCancellationPropagates()=runTest {
        for(cancel in listOf(false,true)) {
            val store=prepared();val request=edit(store);val before=store.investmentCashSnapshot(owner);val pending=store.memory.outboxRows(owner.value)
            store.beforeCommit={if(cancel)throw CancellationException("owner replaced") else throw IllegalStateException("disk failed")}
            val result=runCatching{OfflineFirstInvestmentRepository(store).changeCashTransfer(owner,request,device,later)}
            if(cancel)assertTrue(result.exceptionOrNull() is CancellationException) else assertTrue(result.getOrThrow().isFailure)
            assertEquals(before,store.investmentCashSnapshot(owner));assertEquals(pending,store.memory.outboxRows(owner.value))
        }
    }
    @Test fun wrongDeclaredSnapshotOwnerCannotBeReturnedAsAnOwnedLifecycleSuccess()=runTest {
        val store=prepared();val request=edit(store)
        val wrong=object:LocalStore by store{override suspend fun investmentCashSnapshot(owner:UserId)=InvestmentCashReadSnapshot(other,store.investmentCashSnapshot(owner).rows)}
        assertEquals(InvestmentCashTransferError.UNREADABLE_SOURCE,reason(OfflineFirstInvestmentRepository(wrong).changeCashTransfer(owner,request,device,later)));assertEquals(0,store.commits)
    }
}
