package vn.com.quyln.mistia.feature.settings

/** Device-local by contract: this value is never serialized to Supabase or a Mistia backup. */
interface AppLockContract {
    suspend fun isEnabled(): Boolean
    suspend fun enableWithDeviceCredential(): Result<Unit>
    suspend fun disable(): Result<Unit>
}
