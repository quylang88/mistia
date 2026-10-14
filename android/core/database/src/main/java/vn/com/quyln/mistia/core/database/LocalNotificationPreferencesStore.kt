package vn.com.quyln.mistia.core.database

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import vn.com.quyln.mistia.core.model.*

/** Device-level settings, matching Swift UserDefaults rather than financial owner data. */
class LocalNotificationPreferencesStore(context:Context):NotificationPreferencesStore {
    private val preferences=context.getSharedPreferences("mistia-notification-preferences",Context.MODE_PRIVATE)
    private val mutable=MutableStateFlow(read())
    override val state:StateFlow<NotificationPreferences> = mutable.asStateFlow()
    private val listener=SharedPreferences.OnSharedPreferenceChangeListener {_,_ -> mutable.value=read()}
    init {preferences.registerOnSharedPreferenceChangeListener(listener)}
    override fun initializeDetails()=update {it.initializeDetails()}
    override fun setMaster(value:Boolean)=update {it.master(value)}
    override fun setDetail(kind:ReminderKind,value:Boolean)=update {it.detail(kind,value)}
    override fun setFamily(value:Boolean)=update {it.family(value)}
    @Synchronized private fun update(change:(NotificationPreferences)->NotificationPreferences) {
        val value=change(read())
        preferences.edit().putBoolean(MASTER,value.enabled).putBoolean(HAD_GROUP,value.hadAnyGroupOn)
            .putBoolean(REMINDERS,value.reminders).putBoolean(FAMILY,value.family).apply {
                ReminderKind.entries.forEach {kind -> value.details[kind]?.let {putBoolean(key(kind),it)} ?: remove(key(kind))}
            }.apply()
        mutable.value=value
    }
    private fun read()=NotificationPreferences(preferences.getBoolean(MASTER,false),preferences.getBoolean(HAD_GROUP,false),
        preferences.getBoolean(REMINDERS,false),preferences.getBoolean(FAMILY,false),ReminderKind.entries.mapNotNull {kind ->
            if(preferences.contains(key(kind))) kind to preferences.getBoolean(key(kind),false) else null
        }.toMap())
    companion object {
        private const val MASTER="mistia.notifications.enabled"
        private const val HAD_GROUP="mistia.notifications.hadAnyGroupOn"
        private const val REMINDERS="mistia.notifications.group.reminders.enabled"
        private const val FAMILY="mistia.notifications.group.family.enabled"
        private fun key(kind:ReminderKind)="mistia.notifications.reminder."+when(kind) {
            ReminderKind.BUDGET -> "budget";ReminderKind.BILLS -> "bills";ReminderKind.CREDIT_CARDS -> "creditCards";ReminderKind.WALLETS -> "wallets"
        }+".enabled"
    }
}
