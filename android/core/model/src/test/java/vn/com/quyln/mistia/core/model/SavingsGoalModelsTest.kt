package vn.com.quyln.mistia.core.model

import java.time.YearMonth
import java.time.ZoneId
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class SavingsGoalModelsTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val zone=ZoneId.of("Asia/Tokyo")
    private fun goal(id:String="22222222-2222-2222-2222-222222222222")=SavingsGoalRecord(
        id,owner.value,"Travel","mistia.goal.savings",Long.MAX_VALUE,9007199254740993L,
        "2026-12-31T15:00:00Z",null,"JPY",0,false,"2026-10-13T00:00:00Z","2026-10-13T00:00:00Z",null,Long.MAX_VALUE,null)

    @Test fun `typed round trip preserves long money and versions with explicit nulls`() {
        val value=goal()
        assertEquals(value,SavingsGoalRecord.fromCloudRecord(value.toCloudRecord()))
        listOf("linked_wallet_id","deleted_at","last_modified_by_device_id").forEach { assertSame(JsonNull,value.toPayload()[it]) }
        assertEquals(Long.MAX_VALUE.toString(),value.toPayload()["target_minor"].toString())
        assertEquals(value.copy(currentSavedMinor=Long.MIN_VALUE),SavingsGoalRecord.fromCloudRecord(value.copy(currentSavedMinor=Long.MIN_VALUE).toCloudRecord()))
    }
    @Test fun `required fields and malformed scalar uuid utc fields reject`() {
        val cloud=goal().toCloudRecord()
        val optional=setOf("linked_wallet_id","deleted_at","last_modified_by_device_id")
        cloud.payload.keys.filterNot { it in optional }.forEach { key ->
            assertThrows("missing $key",IllegalArgumentException::class.java) { SavingsGoalRecord.fromCloudRecord(cloud.copy(payload=JsonObject(cloud.payload-key))) }
        }
        mapOf("target_minor" to JsonPrimitive("100"),"current_saved_minor" to JsonPrimitive(1.5),"sync_version" to JsonPrimitive("bad"),
            "is_archived" to JsonPrimitive("false"),"sort_order" to JsonPrimitive(2147483648L),"id" to JsonPrimitive("bad"),
            "linked_wallet_id" to JsonPrimitive("bad"),"target_date" to JsonPrimitive("2026-10-13"),"updated_at" to JsonPrimitive("not-a-date")
        ).forEach { (key,value) -> assertThrows(key,IllegalArgumentException::class.java) { SavingsGoalRecord.fromCloudRecord(cloud.copy(payload=JsonObject(cloud.payload+(key to value)))) } }
    }
    @Test fun `valid offset timestamps remain lossless like Swift ISO8601 decoding`() {
        val value=goal().copy(updatedAt="2026-10-13T09:00:00+09:00")
        assertEquals(value,SavingsGoalRecord.fromCloudRecord(value.toCloudRecord()))
    }
    @Test fun `projection uses inclusive local months and exact ceiling above double precision`() {
        val row=savingsGoalRows(owner,listOf(goal().copy(targetMinor=9007199254740993L,currentSavedMinor=0)),YearMonth.of(2026,10),zone).single()
        // Tokyo target is January: October through January inclusive = four months.
        assertEquals(2251799813685249L,row.monthlyRequiredMinor)
        assertEquals(0,savingsGoalRows(owner,listOf(goal().copy(targetMinor=10,currentSavedMinor=20)),YearMonth.of(2026,10),zone).single().monthlyRequiredMinor)
        assertEquals(Long.MAX_VALUE,savingsGoalRows(owner,listOf(goal().copy(targetMinor=Long.MAX_VALUE,currentSavedMinor=Long.MIN_VALUE)),YearMonth.of(2027,10),zone).single().monthlyRequiredMinor)
    }
    @Test fun `projection filters owner archived deleted and sorts exact progress then target then name`() {
        val a=goal().copy(name="Alpha",targetMinor=9007199254740993L,currentSavedMinor=9007199254740992L)
        val b=goal("33333333-3333-3333-3333-333333333333").copy(name="Beta",targetMinor=9007199254740992L,currentSavedMinor=9007199254740992L)
        val ignored=listOf(a.copy(ownerUserId="44444444-4444-4444-4444-444444444444"),a.copy(isArchived=true),a.copy(deletedAt=a.updatedAt))
        assertEquals(listOf("Beta","Alpha"),savingsGoalRows(owner,listOf(a,b)+ignored,YearMonth.of(2026,10),zone).map { it.goal.name })
        val c=a.copy(id="55555555-5555-5555-5555-555555555555",name="aardvark")
        assertEquals(listOf("aardvark","Alpha"),savingsGoalRows(owner,listOf(a,c),YearMonth.of(2026,10),zone).map { it.goal.name })
    }
    @Test fun `summary converts currencies once and takes highest progress as nearest`() {
        val yen=goal().copy(name="Near",targetMinor=20000,currentSavedMinor=12000)
        val dong=goal("33333333-3333-3333-3333-333333333333").copy(currencyCode="VND",targetMinor=1000000,currentSavedMinor=200000)
        val rows=savingsGoalRows(owner,listOf(dong,yen),YearMonth.of(2026,10),zone)
        val rates=listOf(ExchangeRateSnapshot("JPY","VND","200","fixture",0,null))
        val summary=savingsGoalSummary(rows,"JPY",rates)
        assertEquals(2,summary.activeCount);assertEquals(13000,summary.totalSavedMinor);assertEquals("Near",summary.nearestGoalName)
        assertEquals(12000,savingsGoalSummary(rows,"JPY",emptyList()).totalSavedMinor)
        assertNull(savingsGoalSummary(emptyList(),"JPY",rates).nearestGoalName)
    }
    @Test fun `summary does not drop conversion overflow and cancels exact signed values before display clamping`() {
        val positive=goal().copy(currentSavedMinor=Long.MAX_VALUE)
        val negative=goal("33333333-3333-3333-3333-333333333333").copy(currentSavedMinor=-Long.MAX_VALUE)
        val rates=listOf(ExchangeRateSnapshot("JPY","VND","200","fixture",0,null))
        fun rows(values:List<SavingsGoalRecord>)=savingsGoalRows(owner,values,YearMonth.of(2026,10),zone)
        assertEquals(Long.MAX_VALUE,savingsGoalSummary(rows(listOf(positive)),"VND",rates).totalSavedMinor)
        assertEquals(0,savingsGoalSummary(rows(listOf(positive,negative)),"VND",rates).totalSavedMinor)
    }
}
