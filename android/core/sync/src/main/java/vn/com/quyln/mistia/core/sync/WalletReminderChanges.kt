package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*
import vn.com.quyln.mistia.core.model.*

/** Process-level observation; local inbox writes are excluded to avoid a feedback loop. */
suspend fun observeWalletReminderChanges(auth:StateFlow<AuthState>,preferences:StateFlow<NotificationPreferences>,store:LocalStore,
    refresh:suspend (UserId)->Unit,clear:suspend ()->Unit) {
    val owners=auth.map {state -> (state==AuthState.Restoring) to (state as? AuthState.SignedIn)?.session?.userId}.distinctUntilChanged()
    val enabled=preferences.map {it.reminderEnabled(ReminderKind.WALLETS)}.distinctUntilChanged()
    combine(owners,enabled) {owner,on -> owner to on}.collectLatest { (scope,on) ->
        val (restoring,owner)=scope
        if(restoring) return@collectLatest
        if(owner==null || !on) {
            try {clear()} catch(cancelled:CancellationException) {throw cancelled} catch(_:Exception) {}
        } else {
            combine(WalletReminderSnapshot.entities.map {store.observe(it.table,owner)}) {it.toList()}
                .distinctUntilChanged().conflate()
                .retryWhen {error,_ -> if(error is CancellationException) throw error;delay(5_000);true}
                .collectLatest {
                    try {refresh(owner)} catch(cancelled:CancellationException) {throw cancelled} catch(_:Exception) {}
                }
        }
    }
}
