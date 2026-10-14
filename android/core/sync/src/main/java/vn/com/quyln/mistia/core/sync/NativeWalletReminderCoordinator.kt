package vn.com.quyln.mistia.core.sync

import java.time.Instant
import java.time.ZoneId
import vn.com.quyln.mistia.core.model.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

interface NativeWalletReminderPlatform {
    val permissionGranted:Boolean
    fun readState():NativeWalletReminderState
    fun writeState(state:NativeWalletReminderState)
    fun schedule(ticket:NativeWalletReminder)
    fun cancel(ticket:NativeWalletReminder)
    fun post(ticket:NativeWalletReminder,record:AppNotificationRecord)
    fun dismiss(tag:String)
    fun retainDisplayed(tags:Set<String>)
}
class NativeWalletReminderCoordinator(private val store:LocalStore,private val platform:NativeWalletReminderPlatform,
    private val owner:()->UserId?,private val enabled:()->Boolean,private val now:()->Instant,private val zone:()->ZoneId,
    private val text:(LedgerWalletRecord,Long)->WalletReminderText) {
    private val mutex=Mutex()
    private fun ensureOwner(account:UserId) {
        if(owner()!=account) throw CancellationException("Native wallet reminder account changed")
    }
    suspend fun reconcile(account:UserId,plan:WalletReminderPlan) = mutex.withLock {
        ensureOwner(account)
        var state=platform.readState()
        // Recover a due alarm after reboot/process death before advancing to tomorrow.
        for(ticket in state.pending) {
            if(runCatching {Instant.parse(ticket.fireAt)<=now()}.getOrDefault(false)) state=deliverLocked(ticket,state)
        }
        currentCoroutineContext().ensureActive();ensureOwner(account)
        val desired=nativeWalletReminderTargets(account,plan,zone(),enabled(),platform.permissionGranted)
        platform.retainDisplayed(desired.map {it.tag}.toSet())
        // Persist intent first: cancellation/crash cannot leave an untracked native alarm.
        platform.writeState(state.copy(pending=(state.pending+desired).associateBy {it.tag}.values.toList()))
        state.pending.filter {it.tag !in desired.map {target -> target.tag}.toSet()}.forEach(platform::cancel)
        desired.forEach(platform::schedule)
        platform.writeState(state.copy(pending=desired))
        if(owner()!=account) {clearLocked();ensureOwner(account)}
    }
    suspend fun deliver(ticket:NativeWalletReminder) = mutex.withLock {
        deliverLocked(ticket,platform.readState())
        Unit
    }
    private suspend fun deliverLocked(ticket:NativeWalletReminder,state:NativeWalletReminderState):NativeWalletReminderState {
        currentCoroutineContext().ensureActive()
        val account=owner() ?: return state
        val reference=now();val calendar=zone()
        if(!nativeWalletReminderIsDue(ticket,account,reference,calendar)) return state
        if(!enabled() || !platform.permissionGranted) return complete(ticket,state)
        val snapshot=store.walletReminderSnapshot(account)
        currentCoroutineContext().ensureActive();ensureOwner(account)
        val fresh=snapshot.plan(reference,calendar,true,text)
        val record=nativeWalletReminderDelivery(ticket,owner(),fresh,reference,calendar,enabled(),platform.permissionGranted,lastHandled(state,ticket.tag)) ?: return complete(ticket,state)
        platform.post(ticket,record)
        if(owner()!=account) {platform.dismiss(ticket.tag);ensureOwner(account)}
        if(!enabled() || !platform.permissionGranted) {platform.dismiss(ticket.tag);return complete(ticket,state)}
        val after=store.walletReminderSnapshot(account)
        if(owner()!=account) {platform.dismiss(ticket.tag);ensureOwner(account)}
        val confirmationTime=now();val confirmationZone=zone()
        val confirmed=nativeWalletReminderDelivery(ticket,owner(),after.plan(confirmationTime,confirmationZone,true,text),
            confirmationTime,confirmationZone,enabled(),platform.permissionGranted,lastHandled(state,ticket.tag))
        if(confirmed==null || confirmed.title!=record.title || confirmed.body!=record.body) {platform.dismiss(ticket.tag);return complete(ticket,state)}
        return complete(ticket,state.copy(delivered=state.delivered+(ticket.tag to ticket.fireAt)))
    }
    private fun lastHandled(state:NativeWalletReminderState,tag:String):String? =
        listOfNotNull(state.delivered[tag],state.handled[tag]).mapNotNull {runCatching {Instant.parse(it)}.getOrNull()}.maxOrNull()?.toString()
    private fun complete(ticket:NativeWalletReminder,state:NativeWalletReminderState):NativeWalletReminderState {
        val marked=state.copy(handled=state.handled+(ticket.tag to
            (lastHandled(state,ticket.tag)?.takeIf {Instant.parse(it)>Instant.parse(ticket.fireAt)} ?: ticket.fireAt)))
        // Persist the handled/delivered nonce before cancellation; keep tracking until OS cleanup succeeds.
        platform.writeState(marked)
        if(marked.pending.any {it.tag==ticket.tag && it.fireAt==ticket.fireAt}) platform.cancel(ticket)
        val updated=marked.copy(pending=marked.pending.filterNot {it.tag==ticket.tag && it.fireAt==ticket.fireAt})
        platform.writeState(updated)
        return updated
    }
    suspend fun clear() = mutex.withLock {clearLocked()}
    private fun clearLocked() {
        val state=platform.readState()
        state.pending.forEach(platform::cancel)
        platform.retainDisplayed(emptySet())
        platform.writeState(state.copy(pending=emptyList()))
    }
}
