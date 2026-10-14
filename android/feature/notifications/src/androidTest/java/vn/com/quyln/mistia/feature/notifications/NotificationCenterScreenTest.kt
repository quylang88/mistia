package vn.com.quyln.mistia.feature.notifications

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
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
class NotificationCenterScreenTest {
    @get:Rule val compose=createComposeRule()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("22222222-2222-2222-2222-222222222222")
    private val now=java.time.Instant.now().minusSeconds(3600).toString()
    private fun row(user:UserId=owner)=AppNotificationRecord(user.value,"bill-${user.value}","Payment reminder","Body","billOverdue",createdAt=now,updatedAt=now)
    private class Repository(initial:List<AppNotificationRecord>):AppNotificationRepository {
        val rows=MutableStateFlow(initial)
        val readKeys=mutableListOf<Set<String>?>()
        override fun observeAppNotifications(owner:UserId)=rows
        override suspend fun markNotificationsRead(owner:UserId,keys:Set<String>?,now:String):Result<Unit> {
            readKeys.add(keys)
            rows.value=rows.value.map {if(it.ownerUserId==owner.value && (keys==null || it.key in keys)) markLocalNotificationRead(it,now) else it}
            return Result.success(Unit)
        }
    }
    @Test fun openingGroupMarksOnlyPresentedKeysAndShowsDayDetail() {
        val repo=Repository(listOf(row(),row(other)))
        compose.setContent {MaterialTheme {NotificationCenterScreen(owner,repo,{}, {Result.success(0)})}}
        compose.onNodeWithTag("notification-group-BILLS").performClick()
        compose.onNodeWithTag("notification-${row().key}").assertIsDisplayed()
        compose.runOnIdle {
            assertEquals(listOf(setOf(row().key)),repo.readKeys)
            assertFalse(repo.rows.value.single {it.ownerUserId==other.value}.isRead)
        }
    }
    @Test fun ownerChangeClearsSelectedGroupAndDoesNotExposePriorOwnerRows() {
        val active=mutableStateOf(owner)
        val repo=Repository(listOf(row(),row(other).copy(kind="budgetWarning",title="Budget warning")))
        compose.setContent {MaterialTheme {NotificationCenterScreen(active.value,repo,{}, {Result.success(0)})}}
        compose.onNodeWithTag("notification-group-BILLS").performClick()
        compose.runOnIdle {active.value=other}
        compose.onNodeWithTag("notification-group-BUDGETS").assertIsDisplayed()
        compose.onNodeWithTag("notification-${row().key}").assertDoesNotExist()
    }    @Test fun detailTapForwardsOriginalNotificationAfterReadAction() {
        val repo=Repository(listOf(row()))
        var opened:String?=null
        compose.setContent {MaterialTheme {NotificationCenterScreen(owner,repo,{}, {Result.success(0)},onOpenNotification={opened=it.key})}}
        compose.onNodeWithTag("notification-group-BILLS").performClick()
        compose.onNodeWithTag("notification-${row().key}").performClick()
        compose.runOnIdle {assertEquals(row().key,opened)}
    }

}
