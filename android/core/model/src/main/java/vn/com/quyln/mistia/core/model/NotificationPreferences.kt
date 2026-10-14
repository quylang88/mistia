package vn.com.quyln.mistia.core.model

import kotlinx.coroutines.flow.StateFlow

enum class ReminderKind { BUDGET,BILLS,CREDIT_CARDS,WALLETS }
data class NotificationPreferences(val enabled:Boolean=false,val hadAnyGroupOn:Boolean=false,val reminders:Boolean=false,val family:Boolean=false,
    val details:Map<ReminderKind,Boolean> = emptyMap()) {
    fun reminderEnabled(kind:ReminderKind):Boolean = enabled && reminders && (details[kind] ?: true)
    val familyEnabled:Boolean get()=enabled && family
    fun initializeDetails():NotificationPreferences =
        if(enabled && reminders && details.isEmpty()) copy(details=ReminderKind.entries.associateWith {true},hadAnyGroupOn=true) else this
    fun master(value:Boolean):NotificationPreferences {
        if(!value) return copy(enabled=false)
        if(!hadAnyGroupOn) return copy(enabled=true,hadAnyGroupOn=true,reminders=true,family=false,details=ReminderKind.entries.associateWith {true})
        return copy(enabled=true,details=if(details.isEmpty() && reminders) ReminderKind.entries.associateWith {true} else details)
    }
    fun detail(kind:ReminderKind,value:Boolean):NotificationPreferences {
        val updated=details+(kind to value)
        val group=updated.values.any {it}
        val any=group || family
        return copy(enabled=any,hadAnyGroupOn=any,reminders=group,details=updated)
    }
    fun family(value:Boolean):NotificationPreferences {
        val any=reminders || value
        return copy(enabled=any,hadAnyGroupOn=any,family=value)
    }
}
interface NotificationPreferencesStore {
    val state:StateFlow<NotificationPreferences>
    fun initializeDetails()
    fun setMaster(value:Boolean)
    fun setDetail(kind:ReminderKind,value:Boolean)
    fun setFamily(value:Boolean)
}

fun applyBillReminderPreference(existing:List<AppNotificationRecord>,planned:List<AppNotificationRecord>,enabled:Boolean):List<AppNotificationRecord> {
    if(enabled) return planned
    val proposals=planned.associateBy {it.key}
    return existing.map {row ->
        val incoming=proposals[row.key]
        if(incoming?.actionState=="resolved" && incoming.isRead) row.copy(isRead=true,readAt=row.readAt ?: incoming.readAt,
            actionState="resolved",updatedAt=incoming.updatedAt) else row
    }
}
