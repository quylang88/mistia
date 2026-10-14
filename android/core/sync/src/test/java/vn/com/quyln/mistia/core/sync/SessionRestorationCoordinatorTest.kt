package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalCoroutinesApi::class)
class SessionRestorationCoordinatorTest {
    @Test fun `UI and worker share one cold process restore and both wait for completion`()=runTest {
        val state=MutableStateFlow<AuthState>(AuthState.Restoring);var restores=0;var ready=0
        val gate=SessionRestorationCoordinator(state) {restores++;delay(100);state.value=AuthState.SignedOut}
        val ui=launch {gate.ensureRestored();ready++}
        val worker=launch {gate.ensureRestored();ready++}
        runCurrent();assertEquals(1,restores);assertEquals(0,ready)
        advanceTimeBy(100);runCurrent();ui.join();worker.join();assertEquals(2,ready);assertEquals(1,restores)
    }
    @Test fun `already signed out session is not restored again from old secure storage`()=runTest {
        val state=MutableStateFlow<AuthState>(AuthState.SignedOut)
        SessionRestorationCoordinator(state) {error("must not resurrect signed out session")}.ensureRestored()
    }
    @Test fun `already active session is not overwritten by stale secure snapshot`()=runTest {
        val session=AuthSession(UserId("11111111-1111-1111-1111-111111111111"),null,"token","refresh",Long.MAX_VALUE)
        val state=MutableStateFlow<AuthState>(AuthState.SignedIn(session))
        SessionRestorationCoordinator(state) {error("must not restore")}.ensureRestored()
        assertEquals(AuthState.SignedIn(session),state.value)
    }
    @Test fun `failed restoration can retry while state remains restoring`()=runTest {
        val state=MutableStateFlow<AuthState>(AuthState.Restoring);var attempts=0
        val gate=SessionRestorationCoordinator(state) {attempts++;if(attempts==1) throw java.io.IOException("keystore unavailable");state.value=AuthState.SignedOut}
        assertTrue(runCatching {gate.ensureRestored()}.exceptionOrNull() is java.io.IOException)
        gate.ensureRestored();assertEquals(2,attempts);assertEquals(AuthState.SignedOut,state.value)
    }
    @Test fun `cancelled restoration releases waiters and preserves cancellation`()=runTest {
        val state=MutableStateFlow<AuthState>(AuthState.Restoring);var calls=0
        val gate=SessionRestorationCoordinator(state) {calls++;if(calls==1) awaitCancellation();state.value=AuthState.SignedOut}
        val first=launch {gate.ensureRestored()};runCurrent()
        val second=launch {gate.ensureRestored()};runCurrent();assertEquals(1,calls)
        first.cancelAndJoin();second.join();assertEquals(2,calls);assertTrue(first.isCancelled)
    }
    @Test fun `restore returning without a resolved state cannot signal readiness`()=runTest {
        val state=MutableStateFlow<AuthState>(AuthState.Restoring)
        assertTrue(runCatching {SessionRestorationCoordinator(state) {}.ensureRestored()}.isFailure)
    }
}
