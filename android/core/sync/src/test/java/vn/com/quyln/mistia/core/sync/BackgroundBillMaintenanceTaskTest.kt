package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalCoroutinesApi::class)
class BackgroundBillMaintenanceTaskTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val signedIn=AuthState.SignedIn(AuthSession(owner,null,"token","refresh",Long.MAX_VALUE))
    private val report=BillMaintenanceReport(emptyList(),emptyList())
    private fun task(state:MutableStateFlow<AuthState>,restore:suspend ()->Unit,run:suspend (UserId)->Result<BillMaintenanceReport>)=
        BackgroundBillMaintenanceTask(SessionRestorationCoordinator(state,restore),BillMaintenanceCoordinator(state,
            object:BillMaintenanceRepository {
                override suspend fun maintainRecurringBills(owner:UserId,deviceId:String,now:String)=run(owner)
            },{"22222222-2222-2222-2222-222222222222"},{"2026-10-14T00:00:00Z"}))
    @Test fun `cold process waits for session restoration before local financial maintenance`()=runTest {
        val state=MutableStateFlow<AuthState>(AuthState.Restoring);val events=mutableListOf<String>()
        val work=async {task(state,{events+="restore";delay(100);state.value=signedIn}) {id ->
            assertEquals(owner,id);events+="money";Result.success(report)
        }.run()}
        runCurrent();assertEquals(listOf("restore"),events)
        assertEquals(report,work.await().getOrThrow());assertEquals(listOf("restore","money"),events)
    }
    @Test fun `signed out periodic work finishes without reading cached session or paying`()=runTest {
        val state=MutableStateFlow<AuthState>(AuthState.SignedOut)
        assertNull(task(state,{error("must not restore")}) {error("must not pay")}.run().getOrThrow())
    }
    @Test fun `storage restoration failure is retryable result and never reaches money`()=runTest {
        val state=MutableStateFlow<AuthState>(AuthState.Restoring);val error=java.io.IOException("storage")
        assertSame(error,task(state,{throw error}) {error("must not pay")}.run().exceptionOrNull())
    }
    @Test fun `local repository failure is returned to scheduler`()=runTest {
        val state=MutableStateFlow<AuthState>(signedIn);val error=IllegalStateException("database")
        assertSame(error,task(state,{error("already restored")}) {Result.failure(error)}.run().exceptionOrNull())
    }
    @Test fun `account switch cancels background task without a late financial effect`()=runTest {
        val state=MutableStateFlow<AuthState>(signedIn);val entered=CompletableDeferred<Unit>();var late=false
        val work=async {task(state,{error("already restored")}) {entered.complete(Unit);delay(100);late=true;Result.success(report)}.run()}
        runCurrent();assertTrue(entered.isCompleted);state.value=AuthState.SignedOut
        advanceUntilIdle();assertTrue(work.isCancelled);assertFalse(late)
    }
    @Test fun `worker cancellation during restore is propagated rather than retried`()=runTest {
        val state=MutableStateFlow<AuthState>(AuthState.Restoring)
        assertTrue(runCatching {task(state,{throw CancellationException("work stopped")}) {error("must not pay")}.run()}.exceptionOrNull() is CancellationException)
    }
}
