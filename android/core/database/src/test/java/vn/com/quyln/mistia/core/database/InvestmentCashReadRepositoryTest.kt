package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InvestmentCashReadRepositoryTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val id="22222222-2222-2222-2222-222222222222"
    private fun row(entity:CloudEntity)=CloudRecord(entity.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("realized_profit_loss_minor",JsonNull)
    },null,null,0)
    @Test fun observerRetainsOwnedTradeAndCashDamageForIndependentAvailabilityInsteadOfDroppingRows()=runTest {
        val state=MutableStateFlow(InvestmentCashReadSnapshot(owner,InvestmentCashReadSnapshot.entities.map(::row)))
        val source=object:LocalStore by BudgetMemoryStore(){override fun observeInvestmentCashSnapshot(owner:UserId)=state}
        val actual=OfflineFirstInvestmentRepository(source).observeCashSnapshot(owner).first()
        assertEquals(state.value,actual);assertEquals(4,actual.rows.size)
    }
    @Test fun wrongOuterOwnerOrForeignTradeBodyCannotRelabelAnotherAccountsFinancialSnapshot()=runTest {
        val initial=InvestmentCashReadSnapshot(owner,InvestmentCashReadSnapshot.entities.map(::row));val state=MutableStateFlow(initial)
        val source=object:LocalStore by BudgetMemoryStore(){override fun observeInvestmentCashSnapshot(owner:UserId)=state}
        val repo=OfflineFirstInvestmentRepository(source)
        assertEquals(initial,repo.observeCashSnapshot(owner).first())
        state.value=initial.copy(owner=other)
        assertTrue(runCatching{repo.observeCashSnapshot(owner).first()}.isFailure)
        state.value=initial.copy(rows=initial.rows.map{if(it.entity==CloudEntity.INVESTMENT_TRADE.table)it.copy(payload=JsonObject(it.payload+("user_id" to JsonPrimitive(other.value)))) else it})
        assertTrue(runCatching{repo.observeCashSnapshot(owner).first()}.isFailure)
    }
}
