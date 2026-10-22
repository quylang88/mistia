package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InvestmentFundTimelineRepositoryTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    private val device="44444444-4444-4444-8444-444444444444"
    private val wallet="22222222-2222-4222-8222-222222222222"
    private val event="33333333-3333-4333-8333-333333333333"
    private val now="2026-10-22T00:00:00Z"
    private fun proposal()=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,event,owner.value,buildJsonObject {
        put("id",event);put("user_id",owner.value);put("primary_kind_raw_value","expense");put("entry_status_raw_value","posted");put("amount_minor",20L)
        put("source_wallet_id",wallet);put("source_currency_code","VND");put("occurred_at",now);put("created_at",now);put("deleted_at",JsonNull)
    },now,null,0)
    private fun snapshot()=InvestmentCashReadSnapshot(owner,listOf(WalletDraft(id=wallet,name="Wallet",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=100).toMutation(owner,null,device,now).record))
    private suspend fun failure(block:suspend ()->Unit):Throwable=try{block();error("expected a failed read")}catch(error:IllegalStateException){if(error.message=="expected a failed read")throw error else error}catch(error:Exception){error}
    private fun store(read:suspend (UserId)->InvestmentCashReadSnapshot)=object:LocalStore by BudgetMemoryStore() {
        override suspend fun investmentCashSnapshot(owner:UserId)=read(owner)
    }
    @Test fun oneAtomicSnapshotFeedsBothTimelinesWithoutIndependentReadsOrWrites()=runTest {
        var reads=0;val source=snapshot();val repo=OfflineFirstInvestmentRepository(store{assertEquals(owner,it);reads++;source})
        val result=repo.previewFundUsageTimeline(owner,"VND",null,proposal())
        assertEquals(1,reads);assertEquals(java.math.BigInteger.valueOf(100),result.current.actualByWalletId[wallet]);assertEquals(java.math.BigInteger.valueOf(80),result.proposed.actualByWalletId[wallet])
        assertTrue(result.changes.isEmpty());assertEquals(source,snapshot())
    }
    @Test fun wrongDeclaredSnapshotOwnerIsRejectedBeforeEvenAnEmptyResultCanEscape()=runTest {
        val error=failure{OfflineFirstInvestmentRepository(store{snapshot().copy(owner=other,rows=emptyList())}).previewFundUsageTimeline(owner,"VND",null,proposal())}
        assertTrue(error is InvestmentFundTimelineException)
    }
    @Test fun contradictoryOwnedBodyIsRejectedRatherThanFilteredIntoAnotherAccountsPreview()=runTest {
        val source=snapshot();val wrong=source.rows.single().let{it.copy(payload=JsonObject(it.payload+("user_id" to JsonPrimitive(other.value))))}
        assertTrue(failure{OfflineFirstInvestmentRepository(store{source.copy(rows=listOf(wrong))}).previewFundUsageTimeline(owner,"VND",null,proposal())} is InvestmentFundTimelineException)
    }
    @Test fun diskFailureStaysAReadFailureAndCancellationPropagates()=runTest {
        val disk=java.io.IOException("disk");assertSame(disk,failure{OfflineFirstInvestmentRepository(store{throw disk}).previewFundUsageTimeline(owner,"VND",null,proposal())})
        val cancel=CancellationException("owner changed")
        assertSame(cancel,failure{OfflineFirstInvestmentRepository(store{throw cancel}).previewFundUsageTimeline(owner,"VND",null,proposal())})
    }
    @Test fun unsupportedStoreCannotFallBackToSeparateUnfencedEntityReads()=runTest {
        assertTrue(failure{OfflineFirstInvestmentRepository(BudgetMemoryStore()).previewFundUsageTimeline(owner,"VND",null,proposal())} is UnsupportedOperationException)
    }
}
