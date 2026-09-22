package vn.com.quyln.mistia.core.auth

import android.content.Context

/** The platform picker supplies a token; only AuthRepository exchanges it with Supabase. */
interface GoogleSignInProvider {
    val configured: Boolean
    suspend fun acquire(activityContext: Context): GoogleIdentity
}
