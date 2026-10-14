package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.ZoneId
import java.time.LocalTime
import java.util.UUID
import kotlinx.serialization.Serializable

@Serializable
data class NativeWalletReminder(val ownerUserId:String,val key:String,val walletId:String,val fireAt:String,val zoneId:String) {
    val tag:String get()="mistia.reminder.wallet.$ownerUserId.$walletId"
}
@Serializable
data class NativeWalletReminderState(val pending:List<NativeWalletReminder> = emptyList(),val delivered:Map<String,String> = emptyMap(),val handled:Map<String,String> = emptyMap())
private fun NativeWalletReminder.valid():Boolean = runCatching {
    UUID.fromString(ownerUserId);UUID.fromString(walletId)
    require(key=="mistia.reminder.wallet.${walletId.lowercase()}")
    require(Instant.parse(fireAt).atZone(ZoneId.of(zoneId)).toLocalTime()==LocalTime.of(9,0))
}.isSuccess
private fun AppNotificationRecord.walletTarget(owner:UserId):Boolean = runCatching {
    requireValidLocalNotification()
    require(ownerUserId==owner.value && kind=="lowWallet" && source=="localReminder" && resourceType=="wallet" && resourceId!=null)
    require(key=="mistia.reminder.wallet.${resourceId.lowercase()}")
}.isSuccess
fun nativeWalletReminderTargets(owner:UserId,plan:WalletReminderPlan,zone:ZoneId,enabled:Boolean,permission:Boolean):List<NativeWalletReminder> {
    if(!enabled || !permission) return emptyList()
    return plan.scheduled.filter {it.walletTarget(owner)}.map {row ->
        NativeWalletReminder(owner.value,row.key,requireNotNull(row.resourceId),row.createdAt,zone.id)
    }.filter {it.valid()}.distinctBy {it.tag}
}
fun nativeWalletReminderIsDue(ticket:NativeWalletReminder,owner:UserId?,reference:Instant,zone:ZoneId):Boolean {
    if(!ticket.valid() || owner?.value!=ticket.ownerUserId || ticket.zoneId!=zone.id) return false
    val fire=Instant.parse(ticket.fireAt)
    return reference>=fire && reference.atZone(zone).toLocalDate()==fire.atZone(zone).toLocalDate()
}
fun nativeWalletReminderDelivery(ticket:NativeWalletReminder,owner:UserId?,plan:WalletReminderPlan,reference:Instant,zone:ZoneId,
    enabled:Boolean,permission:Boolean,lastDelivered:String?):AppNotificationRecord? {
    if(!nativeWalletReminderIsDue(ticket,owner,reference,zone) || !enabled || !permission) return null
    val fire=Instant.parse(ticket.fireAt)
    if(lastDelivered?.let {runCatching {Instant.parse(it)}.getOrNull()}?.let {it>=fire}==true) return null
    return plan.scheduled.firstOrNull {it.walletTarget(requireNotNull(owner)) && it.key==ticket.key && it.resourceId==ticket.walletId}
}
