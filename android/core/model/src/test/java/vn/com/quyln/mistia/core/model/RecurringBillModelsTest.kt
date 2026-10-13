package vn.com.quyln.mistia.core.model

import java.time.ZoneId
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class RecurringBillModelsTest {
    private val zone=ZoneId.of("Asia/Tokyo")
    private fun bill()=RecurringBillPlanRecord(
        id="11111111-1111-1111-1111-111111111111",ownerUserId="22222222-2222-2222-2222-222222222222",
        name="Rent",iconSymbolName="mistia.plan.bill",categoryId=null,amountMinor=Long.MAX_VALUE,dueDay=20,
        scheduleKindWireValue=null,paymentStartDay=null,paymentStartDate=null,firstScheduledMonth=null,hasExplicitDueDate=null,
        dueDate=null,autoPayEnabled=null,autoPayDay=null,autoPayDate=null,frequencyMonths=1,paymentWalletId=null,currencyCode="JPY",
        isArchived=false,isPaused=false,pausedAt=null,resumeStartMonth=null,createdAt="2026-10-13T00:00:00Z",updatedAt="2026-10-13T00:00:00Z",
        deletedAt=null,syncVersion=9007199254740993L,lastModifiedByDeviceId=null)
    private val nullable=setOf("category_id","amount_minor","schedule_kind_raw_value","payment_start_day","payment_start_date","first_scheduled_month",
        "has_explicit_due_date","due_date","auto_pay_enabled","auto_pay_day","auto_pay_date","payment_wallet_id","paused_at","resume_start_month","deleted_at","last_modified_by_device_id")

    @Test fun `full contract round trip retains null clears and exact signed minor version`() {
        val value=bill()
        assertEquals(28,value.toPayload().size)
        assertEquals(nullable+setOf("user_id","id","name","icon_symbol_name","due_day","frequency_months","currency_code","is_archived","is_paused","created_at","updated_at","sync_version"),value.toPayload().keys)
        assertEquals(value,RecurringBillPlanRecord.fromCloudRecord(value.toCloudRecord()))
        assertEquals(Long.MAX_VALUE.toString(),value.toPayload()["amount_minor"].toString())
        val empty=value.copy(amountMinor=null)
        nullable.forEach { assertSame(it,JsonNull,empty.toPayload()[it]) }
        val negative=value.copy(amountMinor=Long.MIN_VALUE,syncVersion=Long.MAX_VALUE)
        assertEquals(negative,RecurringBillPlanRecord.fromCloudRecord(negative.toCloudRecord()))
    }
    @Test fun `populated auto pay pause resume and schedule fields remain independent and lossless`() {
        val value=bill().copy(categoryId="33333333-3333-3333-3333-333333333333",scheduleKindWireValue="oneTime",paymentStartDay=10,
            paymentStartDate="2026-10-13T09:00:00+09:00",firstScheduledMonth="2026-09-30T15:00:00Z",hasExplicitDueDate=true,
            dueDate="2026-10-14T15:00:00Z",autoPayEnabled=true,autoPayDay=12,autoPayDate="2026-10-13T15:00:00Z",
            paymentWalletId="44444444-4444-4444-4444-444444444444",isPaused=true,pausedAt="2026-10-13T00:00:00Z",
            resumeStartMonth="2026-10-31T15:00:00Z",deletedAt="2026-10-15T00:00:00Z",lastModifiedByDeviceId="55555555-5555-5555-5555-555555555555")
        assertEquals(value,RecurringBillPlanRecord.fromCloudRecord(value.toCloudRecord()))
        assertEquals(JsonPrimitive(12),value.toPayload()["auto_pay_day"])
        assertEquals(JsonPrimitive(10),value.toPayload()["payment_start_day"])
    }
    @Test fun `required fields reject missing and only legacy pause flag defaults false`() {
        val cloud=bill().toCloudRecord()
        cloud.payload.keys.filterNot { it in nullable || it=="is_paused" }.forEach { key ->
            assertThrows(key,IllegalArgumentException::class.java) { RecurringBillPlanRecord.fromCloudRecord(cloud.copy(payload=JsonObject(cloud.payload-key))) }
        }
        assertFalse(RecurringBillPlanRecord.fromCloudRecord(cloud.copy(payload=JsonObject(cloud.payload-"is_paused"))).isPaused)
        assertFalse(RecurringBillPlanRecord.fromCloudRecord(cloud.copy(payload=JsonObject(cloud.payload+("is_paused" to JsonNull)))).isPaused)
        val absent=cloud.copy(payload=JsonObject(cloud.payload.filterKeys { it !in nullable }))
        assertNull(RecurringBillPlanRecord.fromCloudRecord(absent).amountMinor)
    }
    @Test fun `malformed nullable scalar uuid dates and int overflow fail instead of defaulting`() {
        val cloud=bill().toCloudRecord()
        mapOf("amount_minor" to JsonPrimitive("12"),"due_day" to JsonPrimitive(2147483648L),"auto_pay_day" to JsonPrimitive(1.5),
            "is_paused" to JsonPrimitive("false"),"auto_pay_enabled" to JsonPrimitive("true"),"category_id" to JsonPrimitive("bad"),
            "payment_start_date" to JsonPrimitive("2026-10-13"),"resume_start_month" to JsonPrimitive("bad"),"frequency_months" to JsonPrimitive("1")
        ).forEach { (key,value) -> assertThrows(key,IllegalArgumentException::class.java) { RecurringBillPlanRecord.fromCloudRecord(cloud.copy(payload=JsonObject(cloud.payload+(key to value)))) } }
    }
    @Test fun `unknown and legacy raw schedule stay lossless with recurring fallback`() {
        listOf(null,"futureKind","pausedRecurring","").forEach { raw ->
            val value=bill().copy(scheduleKindWireValue=raw)
            assertEquals(BillScheduleKind.RECURRING,value.scheduleKind)
            assertEquals(value,RecurringBillPlanRecord.fromCloudRecord(value.toCloudRecord()))
        }
        assertEquals(BillScheduleKind.ONE_TIME,bill().copy(scheduleKindWireValue="oneTime").scheduleKind)
        assertEquals(20,bill().resolvedPaymentStartDay)
    }
    @Test fun `resolved deadlines follow recurring day and one time local date rules`() {
        assertFalse(bill().resolvedHasExplicitDueDate(zone))
        assertFalse(bill().copy(hasExplicitDueDate=true,paymentStartDay=20).resolvedHasExplicitDueDate(zone))
        assertTrue(bill().copy(hasExplicitDueDate=true,paymentStartDay=25).resolvedHasExplicitDueDate(zone))
        val one=bill().copy(scheduleKindWireValue="oneTime",hasExplicitDueDate=true,paymentStartDate="2026-10-13T14:00:00Z",dueDate="2026-10-13T15:00:00Z")
        assertTrue(one.resolvedHasExplicitDueDate(zone))
        assertFalse(one.copy(dueDate="2026-10-13T14:59:00Z").resolvedHasExplicitDueDate(zone))
        assertFalse(one.copy(dueDate="2026-10-12T15:00:00Z").resolvedHasExplicitDueDate(zone))
        assertFalse(one.copy(paymentStartDate=null).resolvedHasExplicitDueDate(zone))
    }
}
