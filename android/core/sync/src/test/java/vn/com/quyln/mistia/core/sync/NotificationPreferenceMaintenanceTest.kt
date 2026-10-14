package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalCoroutinesApi::class)
class NotificationPreferenceMaintenanceTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("22222222-2222-2222-2222-222222222222")
    private fun signedIn(id:UserId=owner,token:String="token")=AuthState.SignedIn(AuthSession(id,null,token,"refresh",Long.MAX_VALUE))
    private val auth=MutableStateFlow<AuthState>(signedIn())
    private val prefs=MutableStateFlow(NotificationPreferences())
    @Test fun `master enable and reminder detail changes run immediately while master disable does not`()=runTest {
        val calls=mutableListOf<UserId>();val job=launch {observeDueMaintenancePreferenceChanges(auth,prefs) {calls+=it}}
        runCurrent();assertTrue(calls.isEmpty())
        prefs.value=prefs.value.master(true);runCurrent();assertEquals(listOf(owner),calls)
        prefs.value=prefs.value.detail(ReminderKind.BILLS,false);runCurrent();assertEquals(2,calls.size)
        prefs.value=prefs.value.master(false);runCurrent();assertEquals(2,calls.size)
        prefs.value=prefs.value.master(true);runCurrent();assertEquals(3,calls.size);job.cancelAndJoin()
    }
    @Test fun `every reminder group choice triggers due work without gating money on bill detail`()=runTest {
        prefs.value=prefs.value.master(true);var calls=0;val job=launch {observeDueMaintenancePreferenceChanges(auth,prefs) {calls++}}
        runCurrent();assertEquals(0,calls)
        for(kind in ReminderKind.entries) {
            prefs.value=prefs.value.detail(kind,false);runCurrent()
        }
        assertEquals(3,calls) // Last choice also disables master, so it does not start a new due pass.
        job.cancelAndJoin()
    }
    @Test fun `new owner takes a fresh preference baseline instead of replaying prior owner gesture`()=runTest {
        val calls=mutableListOf<UserId>();val job=launch {observeDueMaintenancePreferenceChanges(auth,prefs) {calls+=it}}
        runCurrent();prefs.value=prefs.value.master(true);runCurrent();assertEquals(listOf(owner),calls)
        auth.value=AuthState.SignedOut;runCurrent();prefs.value=prefs.value.detail(ReminderKind.BUDGET,false);runCurrent()
        auth.value=signedIn(other);runCurrent();assertEquals(listOf(owner),calls)
        prefs.value=prefs.value.detail(ReminderKind.BUDGET,true);runCurrent();assertEquals(listOf(owner,other),calls);job.cancelAndJoin()
    }
    @Test fun `token refresh family and group history changes do not rerun reminder work`()=runTest {
        var calls=0;val job=launch {observeDueMaintenancePreferenceChanges(auth,prefs) {calls++}}
        runCurrent();prefs.value=prefs.value.master(true);runCurrent()
        auth.value=signedIn(token="new");prefs.value=prefs.value.family(true);runCurrent()
        prefs.value=prefs.value.copy(hadAnyGroupOn=false);runCurrent();assertEquals(1,calls);job.cancelAndJoin()
    }
    @Test fun `latest preference cancels suspended old pass and a storage failure does not end observation`()=runTest {
        var attempts=0;var cancelled=false
        val job=launch {observeDueMaintenancePreferenceChanges(auth,prefs) {
            attempts++
            if(attempts==1) try {awaitCancellation()} finally {cancelled=true}
            if(attempts==2) throw java.io.IOException("disk")
        }}
        runCurrent();prefs.value=prefs.value.master(true);runCurrent();assertEquals(1,attempts)
        prefs.value=prefs.value.detail(ReminderKind.BILLS,false);runCurrent();assertTrue(cancelled);assertEquals(2,attempts)
        prefs.value=prefs.value.detail(ReminderKind.BILLS,true);runCurrent();assertEquals(3,attempts);job.cancelAndJoin()
    }
    @Test fun `legacy detail initialization is a real settings change and triggers current owner due work`()=runTest {
        prefs.value=NotificationPreferences(enabled=true,reminders=true,family=true)
        var calls=0;val job=launch {observeDueMaintenancePreferenceChanges(auth,prefs) {calls++}}
        runCurrent();assertEquals(0,calls);prefs.value=prefs.value.initializeDetails();runCurrent();assertEquals(1,calls);job.cancelAndJoin()
    }
}
