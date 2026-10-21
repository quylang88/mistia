package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class BudgetReadSnapshotTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val id="22222222-2222-2222-2222-222222222222"
    private val time="2026-10-21T00:00:00Z"
    private fun row(entity:CloudEntity)=CloudRecord(entity.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("amount_minor","broken");put("deleted_at",buildJsonObject {put("bad",true)})
    },time,null,0)
    @Test fun `snapshot retains required raw damage and historical tombstones while excluding untrusted scope`()=runTest {
        val raw=BudgetReadSnapshot.entities.map(::row)
        val tombstone=row(CloudEntity.TRANSACTION_CATEGORY).copy(id="33333333-3333-3333-3333-333333333333",deletedAt=time).let {it.copy(payload=JsonObject(it.payload+("id" to JsonPrimitive(it.id))))}
        val foreign=row(CloudEntity.LEDGER_TRANSACTION).copy(ownerUserId=other.value)
        val wrongBody=row(CloudEntity.LEDGER_WALLET).copy(payload=JsonObject(row(CloudEntity.LEDGER_WALLET).payload+("user_id" to JsonPrimitive(other.value))))
        val base=BudgetMemoryStore()
        val source=MutableStateFlow(BudgetReadSnapshot(owner,raw+listOf(tombstone,foreign,wrongBody,row(CloudEntity.RECURRING_BILL_PLAN))))
        val store=object:LocalStore by base {override fun observeBudgetReadSnapshot(owner:UserId)=source}
        val repo=OfflineFirstFinanceRepository(store)
        val before=base.outboxRows(owner.value)
        val result=repo.observeBudgetReadSnapshot(owner).first()
        assertEquals(owner,result.owner);assertEquals((raw+tombstone).toSet(),result.rows.toSet())
        assertEquals(setOf(tombstone),result.records(CloudEntity.TRANSACTION_CATEGORY).filter {it.deletedAt!=null}.toSet())
        assertEquals(before,base.outboxRows(owner.value))
    }
    @Test fun `snapshot from another owner fails instead of being relabelled or emitted as loaded empty`()=runTest {
        val base=BudgetMemoryStore()
        val store=object:LocalStore by base {override fun observeBudgetReadSnapshot(owner:UserId)=MutableStateFlow(BudgetReadSnapshot(other,listOf(row(CloudEntity.BUDGET_PLAN))))}
        assertTrue(runCatching {OfflineFirstFinanceRepository(store).observeBudgetReadSnapshot(owner).first()}.exceptionOrNull() is IllegalArgumentException)
    }
}
