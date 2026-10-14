package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.*
import vn.com.quyln.mistia.core.model.*

/** User preference changes trigger local due work; sign-in/startup already has its own pass. */
suspend fun observeDueMaintenancePreferenceChanges(auth:StateFlow<AuthState>,preferences:StateFlow<NotificationPreferences>,
    maintain:suspend (UserId)->Unit) {
    auth.map {(it as? AuthState.SignedIn)?.session?.userId}.distinctUntilChanged().collectLatest {owner ->
        if(owner==null) return@collectLatest
        preferences.map {Triple(it.enabled,it.reminders,it.details.toMap())}.distinctUntilChanged().drop(1).collectLatest {choice ->
            if(choice.first) {
                try {maintain(owner)} catch(cancelled:CancellationException) {throw cancelled} catch(_:Exception) {}
            }
        }
    }
}
