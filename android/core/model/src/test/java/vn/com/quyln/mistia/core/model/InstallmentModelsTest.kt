package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InstallmentModelsTest {
    private val now = "2026-01-15T00:00:00Z"
    private val record = InstallmentPlanRecord("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
        "Loan", "mistia.plan.installment", 9007199254740993L, 31, null, 1, null, "JPY", false, now, now, null,
        9007199254740995L, null)
    private val nullable = setOf("total_cycles", "payment_wallet_id", "deleted_at", "last_modified_by_device_id")
    @Test fun `wire round trip preserves Int64 and explicit nullable clears`() {
        assertEquals(record, InstallmentPlanRecord.fromCloudRecord(record.toCloudRecord()))
        assertEquals("9007199254740993", record.toPayload()["amount_per_cycle_minor"].toString())
        assertEquals("9007199254740995", record.toPayload()["sync_version"].toString())
        nullable.forEach { assertSame(it, JsonNull, record.toPayload()[it]) }
    }
    @Test fun `populated optional metadata archive and tombstone remain lossless`() {
        val full = record.copy(totalCycles = 24, paymentWalletId = "cccccccc-cccc-cccc-cccc-cccccccccccc", isArchived = true,
            deletedAt = "2026-02-01T00:00:00Z", lastModifiedByDeviceId = "dddddddd-dddd-dddd-dddd-dddddddddddd",
            amountPerCycleMinor = Long.MIN_VALUE, syncVersion = Long.MAX_VALUE)
        assertEquals(full, InstallmentPlanRecord.fromCloudRecord(full.toCloudRecord()))
    }
    @Test fun `all required fields are strict and legacy absent optional fields remain nil`() {
        val cloud = record.toCloudRecord()
        cloud.payload.keys.filterNot { it in nullable }.forEach { key ->
            assertThrows(key, IllegalArgumentException::class.java) { InstallmentPlanRecord.fromCloudRecord(cloud.copy(payload = JsonObject(cloud.payload - key))) }
        }
        assertEquals(record, InstallmentPlanRecord.fromCloudRecord(cloud.copy(payload = JsonObject(cloud.payload.filterKeys { it !in nullable }))))
    }
    @Test fun `wrong scalar types non integral counts malformed UUID and invalid timestamp are rejected`() {
        val cloud = record.toCloudRecord()
        mapOf("amount_per_cycle_minor" to JsonPrimitive("1"), "sync_version" to JsonPrimitive(1.5), "frequency_months" to JsonPrimitive("1"),
            "total_cycles" to JsonPrimitive(2147483648L), "due_day" to JsonPrimitive(1.5), "is_archived" to JsonPrimitive("false"),
            "payment_wallet_id" to JsonPrimitive("c-c-c-c-c"), "created_at" to JsonPrimitive("2026-01-15"), "name" to JsonPrimitive(1)
        ).forEach { (key, value) -> assertThrows(key, IllegalArgumentException::class.java) {
            InstallmentPlanRecord.fromCloudRecord(cloud.copy(payload = JsonObject(cloud.payload + (key to value))))
        } }
    }
    @Test fun `envelope owner id entity mismatches cannot decode as this installment`() {
        val cloud = record.toCloudRecord()
        listOf(cloud.copy(ownerUserId = "cccccccc-cccc-cccc-cccc-cccccccccccc"), cloud.copy(id = "cccccccc-cccc-cccc-cccc-cccccccccccc"),
            cloud.copy(entity = CloudEntity.RECURRING_BILL_PLAN.table)).forEach {
            assertThrows(IllegalArgumentException::class.java) { InstallmentPlanRecord.fromCloudRecord(it) }
        }
    }
}
