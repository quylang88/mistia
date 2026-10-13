package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class DueOccurrenceModelsTest {
    private fun occurrence()=DueOccurrenceRecord("11111111-1111-1111-1111-111111111111","22222222-2222-2222-2222-222222222222",
        "recurringBill","33333333-3333-3333-3333-333333333333","2026-10","2026-10-13T00:00:00Z",Long.MAX_VALUE,"pending",
        null,null,"2026-10-13T00:00:00Z","2026-10-13T00:00:00Z",null,9007199254740993L,null)
    private val nullable=setOf("amount_minor_snapshot","paid_at","linked_transaction_id","deleted_at","last_modified_by_device_id")
    @Test fun `complete occurrence wire round trip keeps signed precision and explicit nullable clears`() {
        val value=occurrence()
        assertEquals(nullable+setOf("user_id","id","source_kind_raw_value","source_id","selected_month_key","scheduled_date","status_raw_value","created_at","updated_at","sync_version"),value.toPayload().keys)
        assertEquals(value,DueOccurrenceRecord.fromCloudRecord(value.toCloudRecord()))
        val empty=value.copy(amountMinorSnapshot=null)
        nullable.forEach { assertSame(JsonNull,empty.toPayload()[it]) }
        val populated=value.copy(amountMinorSnapshot=Long.MIN_VALUE,statusWireValue="paid",paidAt=value.updatedAt,
            linkedTransactionId=value.sourceId,deletedAt=value.updatedAt,lastModifiedByDeviceId=value.sourceId,syncVersion=Long.MAX_VALUE)
        assertEquals(populated,DueOccurrenceRecord.fromCloudRecord(populated.toCloudRecord()))
    }
    @Test fun `required and malformed optional values reject rather than silently defaulting`() {
        val row=occurrence().toCloudRecord()
        row.payload.keys.filterNot { it in nullable }.forEach { key ->
            assertThrows(key,IllegalArgumentException::class.java) { DueOccurrenceRecord.fromCloudRecord(row.copy(payload=JsonObject(row.payload-key))) }
        }
        mapOf("source_id" to JsonPrimitive("bad"),"scheduled_date" to JsonPrimitive("2026-10-13"),"amount_minor_snapshot" to JsonPrimitive("5"),
            "linked_transaction_id" to JsonPrimitive(false),"paid_at" to JsonPrimitive("bad"),"sync_version" to JsonPrimitive(1.5)
        ).forEach { (key,value) -> assertThrows(key,IllegalArgumentException::class.java) { DueOccurrenceRecord.fromCloudRecord(row.copy(payload=JsonObject(row.payload+(key to value)))) } }
    }
    @Test fun `unknown raw enums stay lossless with Swift credit card pending fallback`() {
        val value=occurrence().copy(sourceKindWireValue="futureSource",statusWireValue="futureStatus",selectedMonthKey="legacy-key")
        assertEquals(value,DueOccurrenceRecord.fromCloudRecord(value.toCloudRecord()))
        assertEquals(DueSourceKind.CREDIT_CARD,value.sourceKind)
        assertEquals(DueStatus.PENDING,value.status)
        assertEquals(DueSourceKind.INSTALLMENT,value.copy(sourceKindWireValue="installment").sourceKind)
        assertEquals(DueStatus.SKIPPED,value.copy(statusWireValue="skipped").status)
    }
}
