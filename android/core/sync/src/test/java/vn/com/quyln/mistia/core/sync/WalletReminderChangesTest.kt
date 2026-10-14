package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.*
import kotlinx.serialization.json.buildJsonObject
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalCoroutinesApi::class)
class WalletReminderChangesTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("22222222-2222-2222-2222-222222222222")
    private fun signedIn(id:UserId=owner,token:String="token")=AuthState.SignedIn(AuthSession(id,null,token,"refresh",Long.MAX_VALUE))
    private val auth=MutableStateFlow<AuthState>(signedIn())
    private val prefs=MutableStateFlow(NotificationPreferences().master(true))
    private val finance=mutableMapOf<Pair<UserId,CloudEntity>,MutableSharedFlow<List<CloudRecord>>>()
    private fun store():LocalStore {
        val store=Mockito.mock(LocalStore::class.java)
        for(user in listOf(owner,other)) {
            WalletReminderSnapshot.entities.forEach {entity ->
                val flow=MutableSharedFlow<List<CloudRecord>>(replay=1).apply {tryEmit(emptyList())};finance[user to entity]=flow
                Mockito.`when`(store.observe(entity.table,user)).thenReturn(flow)
            }
        }
        return store
    }
    private fun change(user:UserId) {finance.getValue(user to CloudEntity.LEDGER_WALLET).tryEmit(listOf(CloudRecord("wallets","id",user.value,buildJsonObject {},null,null,0)))}
    @Test fun `master or wallet detail disable clears immediately without another financial update`()=runTest {
        var cleared=0;var refreshed=0
        val data=store();val job=launch {observeWalletReminderChanges(auth,prefs,data,{refreshed++},{cleared++})}
        runCurrent();assertEquals(1,refreshed)
        prefs.value=prefs.value.detail(ReminderKind.WALLETS,false);runCurrent();assertEquals(1,cleared)
        change(owner);runCurrent();assertEquals(1,refreshed)
        prefs.value=prefs.value.detail(ReminderKind.WALLETS,true);runCurrent();assertEquals(2,refreshed)
        prefs.value=prefs.value.master(false);runCurrent();assertEquals(2,cleared);job.cancelAndJoin()
    }
    @Test fun `owner switch unsubscribes prior financial data and sign out clears native state`()=runTest {
        val refreshed=mutableListOf<UserId>();var cleared=0;val data=store()
        val job=launch {observeWalletReminderChanges(auth,prefs,data,{refreshed+=it},{cleared++})}
        runCurrent();auth.value=signedIn(other);runCurrent();assertEquals(listOf(owner,other),refreshed)
        change(owner);runCurrent();assertEquals(2,refreshed.size)
        change(other);runCurrent();assertEquals(listOf(owner,other,other),refreshed)
        auth.value=AuthState.SignedOut;runCurrent();assertEquals(1,cleared);job.cancelAndJoin()
    }
    @Test fun `token refresh and unrelated preference changes do not restart wallet work`()=runTest {
        var refreshed=0;val data=store();val job=launch {observeWalletReminderChanges(auth,prefs,data,{refreshed++},{})}
        runCurrent();auth.value=signedIn(token="new-token");prefs.value=prefs.value.family(true);runCurrent();assertEquals(1,refreshed)
        change(owner);runCurrent();assertEquals(2,refreshed);job.cancelAndJoin()
    }
    @Test fun `temporary refresh failure does not stop observing later balance changes`()=runTest {
        var refreshed=0;val data=store();val job=launch {observeWalletReminderChanges(auth,prefs,data,{refreshed++;if(refreshed==1) throw java.io.IOException("disk")},{})}
        runCurrent();assertEquals(1,refreshed);change(owner);runCurrent();assertEquals(2,refreshed);job.cancelAndJoin()
    }
    @Test fun `unchanged financial emissions from unrelated table invalidation do not reschedule`()=runTest {
        var refreshed=0;val data=store();val job=launch {observeWalletReminderChanges(auth,prefs,data,{refreshed++},{})}
        runCurrent();assertEquals(1,refreshed)
        finance.getValue(owner to CloudEntity.LEDGER_WALLET).emit(emptyList());runCurrent()
        assertEquals(1,refreshed);job.cancelAndJoin()
    }
    @Test fun `cold restoring state retains alarm recovery until session resolves`()=runTest {
        auth.value=AuthState.Restoring;var cleared=0;var refreshed=0;val data=store()
        val job=launch {observeWalletReminderChanges(auth,prefs,data,{refreshed++},{cleared++})}
        runCurrent();assertEquals(0,cleared);assertEquals(0,refreshed)
        auth.value=signedIn();runCurrent();assertEquals(1,refreshed);job.cancelAndJoin()
    }
}
