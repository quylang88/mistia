package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import vn.com.quyln.mistia.core.model.AuthState

/** Shared by Activity and workers so cold-process restoration has one owner. */
class SessionRestorationCoordinator(private val state:StateFlow<AuthState>,private val restore:suspend ()->Unit) {
    private val mutex=Mutex()
    suspend fun ensureRestored() = mutex.withLock {
        currentCoroutineContext().ensureActive()
        if(state.value==AuthState.Restoring) {
            restore()
            currentCoroutineContext().ensureActive()
            check(state.value!=AuthState.Restoring) {"Session restoration is incomplete"}
        }
    }
}
