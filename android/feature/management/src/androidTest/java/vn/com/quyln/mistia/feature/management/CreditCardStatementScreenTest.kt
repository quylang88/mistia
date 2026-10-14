package vn.com.quyln.mistia.feature.management

import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

/** Synthetic UI fixtures, compiled locally; execution requires an Android device. */
@RunWith(AndroidJUnit4::class)
class CreditCardStatementScreenTest {
    @get:Rule val compose = createComposeRule()
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "33333333-3333-3333-3333-333333333333"
    private val now = "2026-01-01T00:00:00Z"
    private val account = CreditCardDraft(name = "Card", creditLimitMinor = 100000).toMutation(owner, null, null, null, device, now)
    private val card = account.wallet.record
    private val month = YearMonth.of(2026, 2)
    private val zone = ZoneId.of("Asia/Tokyo")
    @Test fun paidHistoryDisplaysExactAmountAndLockedNonClickableCharge() {
        val amount = 9007199254740993L
        val charge = TransactionDraft(primaryKind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.DEBT, debtIntent = TransactionDebtIntent.LEND,
            title = "Loan", amountMinor = amount, occurredAt = "2026-02-12T00:00:00Z", sourceWalletId = card.id,
            counterpartyName = "A").toMutation(owner, null, card, null, null, device, now).record
        val statement = creditCardStatementItems(owner, listOf(CreditCardAccount(card, account.profile.record)), listOf(charge),
            emptyList(), listOf(month), Instant.parse("2026-03-26T00:00:00Z"), zone).single().copy(state = CreditCardStatementState.PAID)
        compose.setContent { MistiaTheme(darkTheme = false) { CreditCardStatementContent(
            CreditCardStatementViewData(card, statement, listOf(charge), null), emptyList(), month,
            StatementMonthBounds(month, month), zone, onMonth = {}) } }
        compose.onNodeWithTag("statement.total").assertTextEquals(formatMinorUnits(amount, card.currencyCode))
        compose.onNodeWithTag("statement.status.paid").assertExists()
        compose.onNodeWithTag("statement.charge.${charge.id}").performScrollTo().assertHasNoClickAction()
        compose.onNodeWithTag("statement.chargeLock.${charge.id}", useUnmergedTree = true).assertExists()
    }
    @Test fun monthPickerCancelsWithoutApplyingAndRespectsCurrentMonthBound() {
        val maximum = YearMonth.of(2026, 10)
        var selected by mutableStateOf(maximum)
        compose.setContent { MistiaTheme(darkTheme = true) {
            StatementMonthNavigation(selected, StatementMonthBounds(YearMonth.of(2016, 1), maximum), onMonth = { selected = it })
        } }
        compose.onNodeWithTag("statement.nextMonth").assertIsNotEnabled()
        compose.onNodeWithTag("statement.chooseMonth").performClick()
        compose.onNodeWithTag("statement.monthMenu").performClick()
        compose.onNodeWithTag("statement.month.11").assertDoesNotExist()
        compose.onNodeWithTag("statement.month.2").performScrollTo().performClick()
        compose.onNodeWithTag("statement.cancelMonth").performClick()
        compose.runOnIdle { assertEquals(maximum, selected) }
        compose.onNodeWithTag("statement.previousMonth").performClick()
        compose.runOnIdle { assertEquals(maximum.minusMonths(1), selected) }
    }
    @Test fun cardRowOpensStatementAndSeparateEditDoesNotAlsoNavigate() {
        var opened = 0
        var edited = 0
        compose.setContent { MistiaTheme(darkTheme = false) {
            WalletRow(card, account.profile.record, onClick = { opened++ }, onEditCreditCard = { edited++ })
        } }
        compose.onNodeWithTag("management.card.${card.id}").performClick()
        compose.runOnIdle { assertEquals(1, opened); assertEquals(0, edited) }
        compose.onNodeWithTag("management.editCard.${card.id}").performClick()
        compose.runOnIdle { assertEquals(1, opened); assertEquals(1, edited) }
    }
}
