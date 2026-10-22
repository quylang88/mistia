package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentCashReadSnapshotTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private fun row(entity:CloudEntity)=CloudRecord(entity.table,id,owner.value,buildJsonObject{put("id",id);put("user_id",owner.value)},null,null,0)
    @Test fun walletSubsetIsOnlyProducedAfterTheEntireFourEntityScopeIsVerified() {
        val all=InvestmentCashReadSnapshot(owner,InvestmentCashReadSnapshot.entities.map(::row))
        assertEquals(InvestmentWalletSnapshot.entities.map{it.table}.toSet(),all.walletSnapshot().rows.map{it.entity}.toSet())
        val poison=row(CloudEntity.INVESTMENT_TRADE).let{it.copy(payload=JsonObject(it.payload+("user_id" to JsonPrimitive("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))))}
        val damaged=all.copy(rows=all.rows.filterNot{it.entity==CloudEntity.INVESTMENT_TRADE.table}+poison)
        val result=runCatching{damaged.walletSnapshot()}
        assertEquals(InvestmentCashReadError.UNREADABLE_SOURCE,(result.exceptionOrNull() as? InvestmentCashReadException)?.reason)
    }
}
