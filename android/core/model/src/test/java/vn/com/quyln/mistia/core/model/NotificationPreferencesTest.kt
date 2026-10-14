package vn.com.quyln.mistia.core.model

import org.junit.Assert.*
import org.junit.Test

class NotificationPreferencesTest {
    @Test fun `default is off while first master enable selects all reminders and no family`() {
        val initial=NotificationPreferences()
        assertFalse(initial.enabled);assertFalse(initial.reminderEnabled(ReminderKind.BILLS));assertFalse(initial.familyEnabled)
        val enabled=initial.master(true)
        assertTrue(enabled.enabled);assertTrue(enabled.hadAnyGroupOn);assertTrue(enabled.reminders)
        assertFalse(enabled.familyEnabled)
        assertTrue(ReminderKind.entries.all {enabled.reminderEnabled(it)})
    }
    @Test fun `master disable preserves detail choices and later enable restores them`() {
        val initial=NotificationPreferences().master(true).detail(ReminderKind.BILLS,false)
        val off=initial.master(false)
        assertFalse(off.enabled);assertEquals(initial.details,off.details);assertTrue(off.hadAnyGroupOn)
        val restored=off.master(true)
        assertFalse(restored.reminderEnabled(ReminderKind.BILLS));assertTrue(restored.reminderEnabled(ReminderKind.BUDGET))
    }
    @Test fun `last group disabled resets master and first enable behavior`() {
        var value=NotificationPreferences().master(true)
        ReminderKind.entries.forEach {value=value.detail(it,false)}
        assertFalse(value.enabled);assertFalse(value.reminders);assertFalse(value.hadAnyGroupOn)
        assertTrue(ReminderKind.entries.all {value.master(true).reminderEnabled(it)})
    }
    @Test fun `family group can keep master enabled independently of reminders`() {
        var value=NotificationPreferences().family(true)
        assertTrue(value.enabled);assertTrue(value.familyEnabled);assertFalse(value.reminderEnabled(ReminderKind.BILLS))
        assertFalse(value.family(false).enabled)
        value=value.master(false)
        assertFalse(value.familyEnabled);assertTrue(value.family)
    }
    @Test fun `legacy missing detail defaults on only under enabled reminder group`() {
        val legacy=NotificationPreferences(enabled=true,hadAnyGroupOn=true,reminders=true)
        assertTrue(legacy.reminderEnabled(ReminderKind.BILLS))
        assertFalse(legacy.copy(enabled=false).reminderEnabled(ReminderKind.BILLS))
        assertFalse(legacy.copy(reminders=false).reminderEnabled(ReminderKind.BILLS))
        assertEquals(ReminderKind.entries.associateWith {true},legacy.master(true).details)
    }    @Test fun `disabled bill reminders keep history and read resolution without new or edited reminder copy`() {
        val old=AppNotificationRecord("11111111-1111-1111-1111-111111111111","old","Original","Body","billPaymentRequired",
            createdAt="2026-10-14T00:00:00Z",updatedAt="2026-10-14T00:00:00Z")
        val incoming=old.copy(title="Updated")
        val fresh=old.copy(key="new")
        assertEquals(listOf(old),applyBillReminderPreference(listOf(old),listOf(incoming,fresh),false))
        val resolved=markLocalNotificationRead(incoming,"2026-10-15T00:00:00Z").copy(actionState="resolved")
        val result=applyBillReminderPreference(listOf(old),listOf(resolved,fresh),false).single()
        assertTrue(result.isRead);assertEquals("resolved",result.actionState);assertEquals("Original",result.title)
        assertEquals(listOf(incoming,fresh),applyBillReminderPreference(listOf(old),listOf(incoming,fresh),true))
    }
    @Test fun `legacy initialization preserves family and normalizes active group history`() {
        val legacy=NotificationPreferences(enabled=true,hadAnyGroupOn=false,reminders=true,family=true)
        val initialized=legacy.initializeDetails()
        assertEquals(ReminderKind.entries.associateWith {true},initialized.details)
        assertTrue(initialized.familyEnabled);assertTrue(initialized.hadAnyGroupOn)
        assertEquals(legacy.copy(details=initialized.details,hadAnyGroupOn=true),initialized)
    }

}
