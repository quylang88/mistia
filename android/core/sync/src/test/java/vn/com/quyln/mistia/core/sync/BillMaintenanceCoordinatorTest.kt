package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalCoroutinesApi::class)
class BillMaintenanceCoordinatorTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("33333333-3333-3333-3333-333333333333")
    private val device="22222222-2222-2222-2222-222222222222"
    private val time="2026-10-14T00:00:00Z"
    private val report=BillMaintenanceReport(emptyList(),emptyList())
    private fun signedIn(id:UserId=owner,token:String="token")=AuthState.SignedIn(AuthSession(id,null,token,"refresh",Long.MAX_VALUE))
    private fun coordinator(auth:MutableStateFlow<AuthState>,run:suspend (UserId,String,String)->Result<BillMaintenanceReport>)=
        BillMaintenanceCoordinator(auth,object:BillMaintenanceRepository {
            override suspend fun maintainRecurringBills(owner:UserId,deviceId:String,now:String)=run(owner,deviceId,now)
        },{device},{time})

    @Test fun `signed out restoring and failure do not perform maintenance`()=runTest {
        val auth=MutableStateFlow<AuthState>(AuthState.SignedOut)
        val runner=coordinator(auth) {_,_,_ -> error("must not run")}
        for(state in listOf(AuthState.SignedOut,AuthState.Restoring,AuthState.Failure("expired"))) {
            auth.value=state;assertNull(runner.run().getOrThrow())
        }
    }
    @Test fun `signed in local run uses captured owner device and actual time without requiring network`()=runTest {
        val auth=MutableStateFlow<AuthState>(signedIn())
        var calls=0
        val runner=coordinator(auth) {id,d,t ->
            calls++;assertEquals(owner,id);assertEquals(device,d);assertEquals(time,t);Result.success(report)
        }
        assertEquals(report,runner.run().getOrThrow());assertEquals(1,calls)
    }
    @Test fun `switching owner cancels suspended maintenance before later effects`()=runTest {
        val auth=MutableStateFlow<AuthState>(signedIn());val entered=CompletableDeferred<Unit>();var effect=false
        val runner=coordinator(auth) {_,_,_ -> entered.complete(Unit);delay(100);effect=true;Result.success(report)}
        val work=async {runner.run()};entered.await();auth.value=signedIn(other)
        advanceUntilIdle();assertTrue(work.isCancelled);assertFalse(effect)
    }
    @Test fun `sign out cancels suspended maintenance`()=runTest {
        val auth=MutableStateFlow<AuthState>(signedIn());val entered=CompletableDeferred<Unit>()
        val runner=coordinator(auth) {_,_,_ -> entered.complete(Unit);awaitCancellation()}
        val work=async {runner.run()};entered.await();auth.value=AuthState.SignedOut
        advanceUntilIdle();assertTrue(work.isCancelled)
    }
    @Test fun `same owner token refresh does not cancel maintenance`()=runTest {
        val auth=MutableStateFlow<AuthState>(signedIn());val entered=CompletableDeferred<Unit>()
        val runner=coordinator(auth) {_,_,_ -> entered.complete(Unit);delay(100);Result.success(report)}
        val work=async {runner.run()};entered.await();auth.value=signedIn(token="renewed")
        assertEquals(report,work.await().getOrThrow())
    }
    @Test fun `non suspending owner change cannot return a stale successful report`()=runTest {
        val auth=MutableStateFlow<AuthState>(signedIn())
        val runner=coordinator(auth) {_,_,_ -> auth.value=signedIn(other);Result.success(report)}
        assertTrue(runCatching {runner.run()}.exceptionOrNull() is CancellationException)
    }
    @Test fun `repository failure is preserved and cancellation is never converted to failure`()=runTest {
        val auth=MutableStateFlow<AuthState>(signedIn());val error=IllegalStateException("storage")
        assertSame(error,coordinator(auth) {_,_,_ -> Result.failure(error)}.run().exceptionOrNull())
        assertTrue(runCatching {coordinator(auth) {_,_,_ -> throw CancellationException("stopped")}.run()}.exceptionOrNull() is CancellationException)
    }
    @Test fun `queued caller rechecks owner after previous run completes`()=runTest {
        val auth=MutableStateFlow<AuthState>(signedIn());val entered=CompletableDeferred<Unit>();var calls=0
        val runner=coordinator(auth) {_,_,_ -> calls++;entered.complete(Unit);delay(100);Result.success(report)}
        val first=async {runner.run()};entered.await();val second=async {runner.run()};runCurrent()
        auth.value=AuthState.SignedOut;advanceUntilIdle()
        assertTrue(first.isCancelled);assertNull(second.await().getOrThrow());assertEquals(1,calls)
    }
}
