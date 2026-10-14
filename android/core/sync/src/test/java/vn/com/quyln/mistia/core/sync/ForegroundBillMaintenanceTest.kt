package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ForegroundBillMaintenanceTest {
    @Test fun `resume sync completes before first local pass and later ticks do not repeat network sync`()=runTest {
        val events=mutableListOf<String>()
        val work=launch {runForegroundBillMaintenance({events+="sync";Result.success(0)},{events+="local"},100)}
        runCurrent();assertEquals(listOf("sync","local"),events)
        advanceTimeBy(100);runCurrent();assertEquals(listOf("sync","local","local"),events)
        work.cancelAndJoin();advanceTimeBy(1000);assertEquals(3,events.size)
    }
    @Test fun `offline sync result still allows local automatic payment maintenance`()=runTest {
        var calls=0
        val work=launch {runForegroundBillMaintenance({Result.failure(java.io.IOException("offline"))},{calls++},100)}
        runCurrent();assertEquals(1,calls);work.cancelAndJoin()
    }
    @Test fun `thrown non cancellation sync failure still allows cached local maintenance`()=runTest {
        var calls=0
        val work=launch {runForegroundBillMaintenance({throw java.io.IOException("offline")},{calls++},100)}
        runCurrent();assertEquals(1,calls);work.cancelAndJoin()
    }
    @Test fun `cancelled sync never starts money maintenance`()=runTest {
        var calls=0
        val work=launch {runForegroundBillMaintenance({throw CancellationException("backgrounded")},{calls++},100)}
        runCurrent();assertTrue(work.isCancelled);assertEquals(0,calls)
    }
    @Test fun `local storage failure retries on next foreground tick`()=runTest {
        var calls=0
        val work=launch {runForegroundBillMaintenance({Result.success(0)},{calls++;if(calls==1) throw IllegalStateException("storage")},100)}
        runCurrent();assertEquals(1,calls);advanceTimeBy(100);runCurrent();assertEquals(2,calls);work.cancelAndJoin()
    }
}
