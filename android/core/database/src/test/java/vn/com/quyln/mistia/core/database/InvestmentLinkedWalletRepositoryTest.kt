package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InvestmentLinkedWalletRepositoryTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val device="44444444-4444-4444-4444-444444444444"
    private val previous="55555555-5555-5555-5555-555555555555"
    private val target="66666666-6666-6666-6666-666666666666"
    private val event="77777777-7777-7777-7777-777777777777"
    private val cashId="88888888-8888-8888-8888-888888888888"
    private val now="2026-10-22T00:00:00Z"
    private class Store(val memory:BudgetMemoryStore=BudgetMemoryStore()):LocalStore by memory {
        var beforeCommit:(suspend ()->Unit)?=null
        var commits=0
        override suspend fun investmentWalletSnapshot(owner:UserId)=InvestmentWalletSnapshot(owner,InvestmentWalletSnapshot.entities.flatMap{memory.recordsIncludingDeleted(owner,it.table)})
        override fun observeInvestmentWalletSnapshot(owner:UserId)=MutableStateFlow(InvestmentWalletSnapshot(owner,emptyList()))
        override suspend fun commitInvestmentWalletLink(expected:InvestmentWalletSnapshot,request:InvestmentWalletLinkRequest,deviceId:String,now:String):Boolean {
            beforeCommit?.also{beforeCommit=null}?.invoke()
            if(expected.rows.toSet()!=investmentWalletSnapshot(expected.owner).rows.toSet())return false
            memory.commitMutations(planInvestmentWalletLink(expected,request,deviceId,now).mutations);commits++;return true
        }
    }
    private fun wallet(id:String)=WalletDraft(id=id,name="Wallet",kind=WalletKind.CASH,currencyCode="VND").toMutation(owner,null,device,now).record
    private fun system(link:String?=previous)=wallet(investmentSystemWalletId(owner)).let{it.copy(payload=JsonObject(it.payload+buildJsonObject {
        put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",link?.let(::JsonPrimitive) ?: JsonNull)
    }))}
    private fun cash(amount:Long)=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,cashId,owner.value,buildJsonObject {
        put("id",cashId);put("user_id",owner.value);put("wallet_id",previous);put("role_raw_value","cashAccrual")
        put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived");put("amount_minor",amount);put("currency_code","VND")
        put("accounting_amount_minor",amount);put("accounting_currency_code","VND");put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull)
    },now,null,0)
    private suspend fun seed(store:Store,raw:CloudRecord){store.memory.commitMutation(raw,PendingMutation(CloudEntity.fromTable(raw.entity)!!,raw.id,raw.ownerUserId,MutationKind.UPSERT,raw.payload,now,raw.syncVersion,device))}
    private suspend fun prepared(first:Boolean=false)=Store().also {store ->
        listOf(system(if(first)null else previous),wallet(previous),wallet(target),cash(300)).forEach{seed(store,it)}
    }
    private fun request(first:Boolean=false,move:Boolean=false)=InvestmentWalletLinkRequest(LedgerWalletRecord.fromCloudRecord(system(if(first)null else previous)),
        LedgerWalletRecord.fromCloudRecord(wallet(target)),event,move,if(first)0 else 300,"Move investment cash")
    private fun reason(result:Result<*>)=(result.exceptionOrNull() as? InvestmentWalletLinkException)?.reason
    @Test fun chooseFirstLinkStoresOnlyOneOwnedWalletChangeAndStableReplayDoesNotQueueAgain()=runTest {
        val store=prepared(true);val repo=OfflineFirstInvestmentRepository(store)
        repo.changeLinkedWallet(owner,request(first=true),device,now).getOrThrow()
        assertEquals(target,store.record(owner,CloudEntity.LEDGER_WALLET.table,investmentSystemWalletId(owner))!!.payload.financeRawString("investment_linked_wallet_id"))
        val before=store.investmentWalletSnapshot(owner);val pending=store.memory.outboxRows(owner.value)
        repo.changeLinkedWallet(owner,request(first=true),device,now).getOrThrow()
        assertEquals(before,store.investmentWalletSnapshot(owner));assertEquals(pending,store.memory.outboxRows(owner.value));assertEquals(1,store.commits)
        assertTrue(store.investmentWalletSnapshot(other).rows.isEmpty());assertTrue(store.memory.outboxRows(other.value).isEmpty())
    }
    @Test fun moveAllPersistsTheCompleteTransferPostingBatchAndNoOrdinaryWalletRewrite()=runTest {
        val store=prepared();val before=store.record(owner,CloudEntity.LEDGER_WALLET.table,previous)
        OfflineFirstInvestmentRepository(store).changeLinkedWallet(owner,request(move=true),device,now).getOrThrow()
        val snapshot=store.investmentWalletSnapshot(owner)
        assertEquals(1,snapshot.rows.count{it.entity==CloudEntity.LEDGER_TRANSACTION.table})
        assertEquals(3,snapshot.rows.count{it.entity==CloudEntity.INVESTMENT_POSTING.table});assertEquals(before,store.record(owner,CloudEntity.LEDGER_WALLET.table,previous))
        assertEquals(7,store.memory.outboxRows(owner.value).size);assertEquals(1,store.commits)
    }
    @Test fun changedLinkAtCasCannotBeOverwrittenByTheOlderSelector()=runTest {
        val store=prepared()
        store.beforeCommit={seed(store,system("dddddddd-dddd-dddd-dddd-dddddddddddd"))}
        val result=OfflineFirstInvestmentRepository(store).changeLinkedWallet(owner,request(move=true),device,now)
        assertEquals(InvestmentWalletLinkError.STALE_RECORD,reason(result));assertEquals(0,store.commits)
        assertTrue(store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_TRANSACTION.table).isEmpty())
    }
    @Test fun cashArrivingAtCasRequiresANewAmountConfirmationAndDoesNotPartiallyMove()=runTest {
        val store=prepared();store.beforeCommit={seed(store,cash(301))}
        val result=OfflineFirstInvestmentRepository(store).changeLinkedWallet(owner,request(move=true),device,now)
        assertEquals(InvestmentWalletLinkError.STALE_RECORD,reason(result));assertEquals(0,store.commits)
        assertEquals(previous,store.record(owner,CloudEntity.LEDGER_WALLET.table,investmentSystemWalletId(owner))!!.payload.financeRawString("investment_linked_wallet_id"))
        assertTrue(store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_TRANSACTION.table).isEmpty())
    }
    @Test fun persistenceFailureReturnsFailureButAccountCancellationPropagatesWithoutWrites()=runTest {
        for(cancel in listOf(false,true)) {
            val store=prepared();val before=store.investmentWalletSnapshot(owner);val pending=store.memory.outboxRows(owner.value)
            store.beforeCommit={if(cancel)throw CancellationException("owner replaced") else throw IllegalStateException("disk failed")}
            val result=runCatching{OfflineFirstInvestmentRepository(store).changeLinkedWallet(owner,request(move=true),device,now)}
            if(cancel)assertTrue(result.exceptionOrNull() is CancellationException)else assertTrue(result.getOrThrow().isFailure)
            assertEquals(before,store.investmentWalletSnapshot(owner));assertEquals(pending,store.memory.outboxRows(owner.value))
        }
    }
    @Test fun observerRetainsScopedFinancialDamageButRejectsForeignRowsAndWrongOuterOwner()=runTest {
        val store=prepared();val damaged=cash(1).let{it.copy(payload=JsonObject(it.payload+("accounting_amount_minor" to JsonNull)))}
        val state=MutableStateFlow(InvestmentWalletSnapshot(owner,listOf(damaged)))
        val source=object:LocalStore by store {override fun observeInvestmentWalletSnapshot(owner:UserId)=state}
        val repo=OfflineFirstInvestmentRepository(source)
        assertEquals(listOf(damaged),repo.observeWalletSnapshot(owner).first().rows)
        state.value=InvestmentWalletSnapshot(owner,listOf(damaged.copy(ownerUserId=other.value)))
        assertTrue(runCatching{repo.observeWalletSnapshot(owner).first()}.isFailure)
        state.value=InvestmentWalletSnapshot(other,emptyList())
        assertTrue(runCatching{repo.observeWalletSnapshot(owner).first()}.isFailure)
    }
}
