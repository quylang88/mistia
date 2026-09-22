package vn.com.quyln.mistia.core.sync

import java.io.IOException
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.network.SupabaseHttpException

class SyncRetryPolicyTest {
    @Test
    fun `postgrest client errors are not retryable even though exception is IO shaped`() {
        assertFalse(SupabaseHttpException(401, "unauthorized").isRetryableSyncFailure())
        assertFalse(SupabaseHttpException(409, "conflict").isRetryableSyncFailure())
    }

    @Test
    fun `postgrest transient and transport errors are retryable`() {
        assertTrue(SupabaseHttpException(429, "rate limited").isRetryableSyncFailure())
        assertTrue(SupabaseHttpException(503, "unavailable").isRetryableSyncFailure())
        assertTrue(IOException("offline").isRetryableSyncFailure())
    }
}
