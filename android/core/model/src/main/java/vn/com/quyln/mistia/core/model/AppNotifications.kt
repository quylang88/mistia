package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

@Serializable
data class AppNotificationRecord(
    val ownerUserId:String,val key:String,val title:String,val body:String,val kind:String,
    val source:String="system",val resourceType:String?=null,val resourceId:String?=null,
    val createdAt:String,val updatedAt:String,val isRead:Boolean=false,val readAt:String?=null,
    val actionState:String="informational",val metadata:JsonObject?=null,
)
fun AppNotificationRecord.requireValidLocalNotification() {
    UUID.fromString(ownerUserId)
    require(key.isNotBlank() && title.isNotBlank() && kind.isNotBlank())
    require(source in setOf("system","localReminder"))
    resourceId?.let(UUID::fromString)
    Instant.parse(createdAt);Instant.parse(updatedAt);readAt?.let(Instant::parse)
    require(isRead || readAt==null)
}
fun upsertLocalNotification(existing:AppNotificationRecord?,incoming:AppNotificationRecord,forceUnread:Boolean=false):AppNotificationRecord {
    incoming.requireValidLocalNotification()
    if(existing==null) return incoming
    existing.requireValidLocalNotification()
    require(existing.ownerUserId==incoming.ownerUserId && existing.key==incoming.key)
    return incoming.copy(createdAt=if(forceUnread) incoming.updatedAt else existing.createdAt,
        isRead=if(forceUnread) false else existing.isRead,readAt=if(forceUnread) null else existing.readAt,
        actionState=existing.actionState)
}
fun markLocalNotificationRead(record:AppNotificationRecord,now:String):AppNotificationRecord {
    record.requireValidLocalNotification();Instant.parse(now)
    return record.copy(isRead=true,readAt=record.readAt ?: now,updatedAt=now)
}
fun resolveLocalBillNotifications(owner:UserId,rows:List<AppNotificationRecord>,billId:String,month:String?,now:String):List<AppNotificationRecord> {
    UUID.fromString(owner.value);UUID.fromString(billId);Instant.parse(now)
    month?.let(java.time.YearMonth::parse)
    val kinds=setOf("billPaymentRequired","billAutoPaymentFailed","billOverdue")
    return rows.map {row ->
        val cycle=(row.metadata?.get("dueMonthKey") as? kotlinx.serialization.json.JsonPrimitive)?.content
        if(row.ownerUserId==owner.value && row.resourceType=="bill" && row.resourceId==billId &&
            row.source in setOf("system","localReminder") && row.kind in kinds && (month==null || cycle==month))
            markLocalNotificationRead(row,now).copy(actionState="resolved") else row
    }
}
