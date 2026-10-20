package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

/** Native read-view checks; compile-only until a connected Android device is available. */
@RunWith(AndroidJUnit4::class)
class InstallmentDuePaneTest {
    @get:Rule val compose = createComposeRule()
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val now = "2026-01-15T00:00:00Z"
    private val plan = InstallmentPlanRecord("22222222-2222-2222-2222-222222222222", owner.value, "Loan", "mistia.plan.installment",
        9007199254740993L, 28, null, 1, null, "VND", false, now, now, null, 0, null)
    private val month = YearMonth.of(2026, 2)
    @Test fun paidRowKeepsExactAmountAndReadOnlyStatusThenRendersEmptyMonth() {
        val zone = ZoneId.of("Asia/Tokyo")
        val paid = installmentDueRows(owner, listOf(plan), emptyList(), month, zone).single().copy(status = DueStatus.PAID)
        var rows by mutableStateOf(listOf(paid))
        compose.setContent { MistiaTheme(darkTheme = false) { InstallmentDueContent(rows, Instant.parse(now), zone) } }
        compose.onNodeWithTag("installment.amount.${plan.id}").assertTextEquals(formatMinorUnits(plan.amountPerCycleMinor, "VND"))
        compose.onNodeWithTag("installment.status.${plan.id}").assertExists()
        compose.onNodeWithTag("installment.row.${plan.id}").assertHasNoClickAction()
        compose.onNodeWithTag("installment.due.${plan.id}").assertDoesNotExist()
        compose.runOnIdle { rows = emptyList() }
        compose.onNodeWithTag("installment.empty").assertExists()
        compose.onNodeWithTag("installment.row.${plan.id}").assertDoesNotExist()
    }
    @Test fun sameReferenceInstantUsesLocalJapanAndVietnamDueDayLabels() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var zone by mutableStateOf(ZoneId.of("Asia/Tokyo"))
        val reference = Instant.parse("2026-02-27T16:00:00Z")
        compose.setContent { MistiaTheme(darkTheme = true) {
            InstallmentDueContent(installmentDueRows(owner, listOf(plan), emptyList(), month, zone), reference, zone)
        } }
        compose.onNodeWithTag("installment.timing.${plan.id}").assertTextEquals(context.getString(R.string.planning_planning_due_today))
        compose.runOnIdle { zone = ZoneId.of("Asia/Ho_Chi_Minh") }
        compose.onNodeWithTag("installment.timing.${plan.id}").assertTextEquals(context.getString(R.string.planning_planning_value_days_left, "1"))
    }
}
