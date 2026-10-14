package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InstallmentReadRepositoryTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = "99999999-9999-9999-9999-999999999999"
    private val now = "2026-01-15T00:00:00Z"
    private val plan = InstallmentPlanRecord("22222222-2222-2222-2222-222222222222", owner.value, "Loan", "mistia.plan.installment",
        9007199254740993L, 31, null, 1, null, "VND", false, now, now, null, 9007199254740995L, null)
    @Test fun `typed read preserves imported amount currency nullable metadata and Long version`() = runTest {
        val store = FinanceReadStore()
        store.rows.value = mapOf(CloudEntity.INSTALLMENT_PLAN to listOf(plan.toCloudRecord()))
        assertEquals(listOf(plan), OfflineFirstFinanceRepository(store).observeInstallments(owner).first())
    }
    @Test fun `typed read excludes archive tombstones malformed payload and envelope aliases`() = runTest {
        val store = FinanceReadStore(); val valid = plan.toCloudRecord()
        store.rows.value = mapOf(CloudEntity.INSTALLMENT_PLAN to listOf(valid, plan.copy(isArchived = true).toCloudRecord(),
            plan.copy(deletedAt = now).toCloudRecord(), plan.copy(ownerUserId = other).toCloudRecord(),
            valid.copy(payload = JsonObject(valid.payload + ("id" to JsonPrimitive(other)))),
            valid.copy(payload = JsonObject(valid.payload + ("user_id" to JsonPrimitive(other)))),
            valid.copy(payload = JsonObject(valid.payload + ("amount_per_cycle_minor" to JsonPrimitive("1"))))))
        assertEquals(listOf(plan), OfflineFirstFinanceRepository(store).observeInstallments(owner).first())
    }
    @Test fun `creation order compares actual instants for imported offset timestamps`() = runTest {
        val store = FinanceReadStore()
        val earlier = plan.copy(id = other, name = "Earlier instant", createdAt = "2026-01-15T01:00:00+09:00")
        store.rows.value = mapOf(CloudEntity.INSTALLMENT_PLAN to listOf(plan.toCloudRecord(), earlier.toCloudRecord()))
        assertEquals(listOf(earlier, plan), OfflineFirstFinanceRepository(store).observeInstallments(owner).first())
    }
    @Test fun `stable createdAt order updates after local plan changes`() = runTest {
        val store = FinanceReadStore(); val second = plan.copy(id = other, name = "Later", createdAt = "2026-02-01T00:00:00Z")
        store.rows.value = mapOf(CloudEntity.INSTALLMENT_PLAN to listOf(second.toCloudRecord(), plan.toCloudRecord()))
        val repository = OfflineFirstFinanceRepository(store)
        assertEquals(listOf(plan, second), repository.observeInstallments(owner).first())
        store.rows.value = mapOf(CloudEntity.INSTALLMENT_PLAN to listOf(second.toCloudRecord(), plan.copy(isArchived = true).toCloudRecord()))
        assertEquals(listOf(second), repository.observeInstallments(owner).first())
    }
}
