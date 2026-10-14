package vn.com.quyln.mistia.feature.settings

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class NotificationSettingsScreenTest {
    @get:Rule val compose=createComposeRule()
    private class Store:NotificationPreferencesStore {
        override val state=MutableStateFlow(NotificationPreferences())
        override fun initializeDetails() {state.value=state.value.initializeDetails()}
        override fun setMaster(value:Boolean) {state.value=state.value.master(value)}
        override fun setDetail(kind:ReminderKind,value:Boolean) {state.value=state.value.detail(kind,value)}
        override fun setFamily(value:Boolean) {state.value=state.value.family(value)}
    }
    @Test fun firstEnableRequestsPermissionOnlyFromExplicitMasterAction() {
        val store=Store();var requests=0
        compose.setContent {MaterialTheme {NotificationSettingsScreen(store,{}, {requests++})}}
        compose.onNodeWithTag("notifications-master").assertIsOff()
        compose.runOnIdle {assertEquals(0,requests)}
        compose.onNodeWithTag("notifications-master").performClick()
        compose.onNodeWithTag("notification-detail-BILLS").assertIsOn()
        compose.onNodeWithTag("notifications-master").performClick()
        compose.runOnIdle {assertEquals(1,requests)}
        compose.onNodeWithTag("notification-detail-BILLS").assertDoesNotExist()
    }
    @Test fun detailChoiceSurvivesMasterOffAndBackOn() {
        val store=Store()
        compose.setContent {MaterialTheme {NotificationSettingsScreen(store,{}, {})}}
        compose.onNodeWithTag("notifications-master").performClick()
        compose.onNodeWithTag("notification-detail-BILLS").performClick()
        compose.onNodeWithTag("notifications-master").performClick()
        compose.onNodeWithTag("notifications-master").performClick()
        compose.onNodeWithTag("notification-detail-BILLS").assertIsOff()
        compose.onNodeWithTag("notification-detail-BUDGET").assertIsOn()
    }
}
