package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class NotificationPreferencesStoreTest {
    @Test fun recreatedStoreKeepsMasterAndIndividualChoices() {
        val context=ApplicationProvider.getApplicationContext<Context>()
        context.deleteSharedPreferences("mistia-notification-preferences")
        try {
            val first=LocalNotificationPreferencesStore(context)
            assertFalse(first.state.value.enabled)
            first.setMaster(true);first.setDetail(ReminderKind.BILLS,false);first.setMaster(false)
            val next=LocalNotificationPreferencesStore(context)
            assertEquals(first.state.value,next.state.value)
            next.setMaster(true)
            assertFalse(next.state.value.reminderEnabled(ReminderKind.BILLS))
            assertTrue(next.state.value.reminderEnabled(ReminderKind.BUDGET))
        } finally {context.deleteSharedPreferences("mistia-notification-preferences")}
    }
    @Test fun legacyReminderGroupInitializesDetailsWithoutEnablingFamily() {
        val context=ApplicationProvider.getApplicationContext<Context>()
        context.deleteSharedPreferences("mistia-notification-preferences")
        try {
            context.getSharedPreferences("mistia-notification-preferences",Context.MODE_PRIVATE).edit()
                .putBoolean("mistia.notifications.enabled",true).putBoolean("mistia.notifications.hadAnyGroupOn",true)
                .putBoolean("mistia.notifications.group.reminders.enabled",true).commit()
            val store=LocalNotificationPreferencesStore(context)
            assertTrue(store.state.value.reminderEnabled(ReminderKind.BILLS))
            store.setMaster(true)
            assertTrue(ReminderKind.entries.all {store.state.value.details[it]==true})
            assertFalse(store.state.value.familyEnabled)
        } finally {context.deleteSharedPreferences("mistia-notification-preferences")}
    }
}
