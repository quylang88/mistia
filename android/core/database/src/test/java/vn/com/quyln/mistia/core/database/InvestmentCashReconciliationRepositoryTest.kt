package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InvestmentCashReconciliationRepositoryTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    private val device="44444444-4444-4444-8444-444444444444"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val now="2026-10-22T00:00:00Z"
    private fun rows():List<CloudRecord> {
        fun wallet(key:Int,opening:Long)=WalletDraft(id=id(key),name="Wallet$key",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=opening).toMutation(owner,null,device,now).record
        val system=wallet(99,0).let{it.copy(id=investmentSystemWalletId(owner),payload=JsonObject(it.payload+buildJsonObject{put("id",investmentSystemWalletId(owner));put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",id(2))}))}
        val cash=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",0L)
            put("event_id",id(11));put("wallet_id",id(1));put("ledger_transaction_id",id(11));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",50L);put("currency_code","JPY");put("accounting_amount_minor",50L);put("accounting_currency_code","JPY");put("occurred_at",now)
        },now,null,0)
        return listOf(system,wallet(1,150),wallet(2,0),cash)
    }
    private class Store(var source:InvestmentCashReadSnapshot):LocalStore by BudgetMemoryStore() {
        var commits=0;var reads=0;var accept=true;var beforeCommit:(()->Unit)?=null
        override suspend fun investmentCashSnapshot(owner:UserId):InvestmentCashReadSnapshot{reads++;return source}
        override suspend fun commitInvestmentCashReconciliation(expected:InvestmentCashReadSnapshot,request:InvestmentCashReconciliationRequest,deviceId:String,now:String):Boolean {
            commits++;beforeCommit?.also{beforeCommit=null}?.invoke()
            if(!accept || expected!=source)return false
            source=source.copy(rows=source.rows+planInvestmentCashReconciliation(source,request,deviceId,now).mutations.map{it.first});return true
        }
    }
    private fun prepared()=Store(InvestmentCashReadSnapshot(owner,rows()))
    private fun request(store:Store)=InvestmentCashReconciliationRequest(readInvestmentCashReconciliation(store.source),listOf(InvestmentCashReconciliationTransfer(id(20),id(1),80)),now,now,"Reconciliation",true)
    private fun reason(result:Result<*>)=(result.exceptionOrNull() as? InvestmentCashReconciliationException)?.reason
    @Test fun atomicBatchCommitsOnceAndCompletedLossReceiptRetryDoesNotWriteAgain()=runTest {
        val store=prepared();val request=request(store);val repo=OfflineFirstInvestmentRepository(store)
        repo.reconcileCash(owner,request,device,now).getOrThrow();assertEquals(1,store.commits);assertEquals(7,store.source.rows.size)
        val after=store.source;repo.reconcileCash(owner,request,device,now).getOrThrow();assertEquals(1,store.commits);assertEquals(after,store.source)
    }
    @Test fun exhaustedCasRetriesExactlyThreeTimesAndLeavesEveryOriginalRowUntouched()=runTest {
        val store=prepared();val before=store.source;val request=request(store);store.accept=false
        assertEquals(InvestmentCashReconciliationError.STALE_RECORD,reason(OfflineFirstInvestmentRepository(store).reconcileCash(owner,request,device,now)))
        assertEquals(3,store.commits);assertEquals(before,store.source)
    }
    @Test fun changedFinancialConsentAfterFirstCasLossDoesNotBecomeAFreshSilentAuthorization()=runTest {
        val store=prepared();val request=request(store);store.beforeCommit={store.source=store.source.copy(rows=store.source.rows.map{if(it.id==id(1))it.copy(payload=JsonObject(it.payload+("opening_balance_minor" to JsonPrimitive(149L)))) else it})}
        assertEquals(InvestmentCashReconciliationError.STALE_RECORD,reason(OfflineFirstInvestmentRepository(store).reconcileCash(owner,request,device,now)));assertEquals(1,store.commits)
        assertTrue(store.source.rows.none{it.entity==CloudEntity.LEDGER_TRANSACTION.table})
    }
    @Test fun wrongDeclaredSnapshotOwnerAndBodyContradictionCannotReachCommit()=runTest {
        val store=prepared();val request=request(store);store.source=store.source.copy(owner=other)
        assertEquals(InvestmentCashReconciliationError.UNREADABLE_SOURCE,reason(OfflineFirstInvestmentRepository(store).reconcileCash(owner,request,device,now)));assertEquals(0,store.commits)
    }
    @Test fun diskFailureReturnsFailureAndCancellationPropagates()=runTest {
        val store=prepared();val request=request(store);val disk=java.io.IOException("disk")
        val broken=object:LocalStore by store{override suspend fun investmentCashSnapshot(owner:UserId):InvestmentCashReadSnapshot=throw disk}
        assertSame(disk,OfflineFirstInvestmentRepository(broken).reconcileCash(owner,request,device,now).exceptionOrNull())
        val cancel=CancellationException("owner changed")
        val cancelled=object:LocalStore by store{override suspend fun investmentCashSnapshot(owner:UserId):InvestmentCashReadSnapshot=throw cancel}
        try{OfflineFirstInvestmentRepository(cancelled).reconcileCash(owner,request,device,now);fail("cancellation swallowed")}catch(actual:CancellationException){assertSame(cancel,actual)}
    }
}
