package vn.com.quyln.mistia.feature.management

import android.content.Context
import android.content.res.Configuration
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.localizedTransactionTitle
import vn.com.quyln.mistia.core.model.*

/** Resource/context bridge checks. Compile-only until an Android device is available. */
@RunWith(AndroidJUnit4::class)
class TransactionTitleLocalizationTest {
    @get:Rule val compose = createComposeRule()
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "33333333-3333-3333-3333-333333333333"
    private val now = "2026-01-01T00:00:00Z"
    private fun context(language: String): Context {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        return base.createConfigurationContext(Configuration(base.resources.configuration).apply { setLocale(Locale.forLanguageTag(language)) })
    }
    private fun lending(title: String): LedgerTransactionRecord {
        val card = CreditCardDraft(name = "Card", creditLimitMinor = 10000).toMutation(owner, null, null, null, device, now).wallet.record
        return TransactionDraft(primaryKind = TransactionPrimaryKind.TRANSFER, transferSubtype = TransactionTransferSubtype.DEBT,
            debtIntent = TransactionDebtIntent.LEND, title = title, amountMinor = 5000, occurredAt = now,
            sourceWalletId = card.id, counterpartyName = "A").toMutation(owner, null, card, null, null, device, now).record
    }
    @Test fun languageChangeUpdatesStoredGeneratedTitleWithoutMutatingCustomOrStoredText() {
        val raw = context("vi").getString(R.string.shared_corelogic_financeenums_lend)
        val tx = lending(raw)
        var language by mutableStateOf("en")
        compose.setContent {
            val localized = remember(language) { context(language) }
            CompositionLocalProvider(LocalContext provides localized, LocalConfiguration provides localized.resources.configuration) {
                Text(localizedTransactionTitle(tx))
                Text(localizedTransactionTitle(tx.copy(title = raw + " A")))
            }
        }
        listOf("en", "ja", "vi").forEach { value ->
            compose.runOnIdle { language = value }
            compose.onNodeWithText(context(value).getString(R.string.shared_corelogic_financeenums_lend)).assertExists()
            compose.onNodeWithText(raw + " A").assertExists()
        }
        assertEquals(raw, tx.title)
    }
    @Test fun foreignCategorySystemKeyCannotTranslateOwnedCustomExpense() {
        val category = CategoryDraft(name = "Legacy", kind = TransactionCategoryKind.EXPENSE,
            hierarchyRole = CategoryHierarchyRole.PARENT).toMutation(owner, null, null, device, now).record
            .copy(systemKey = TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_KEY, ownerUserId = "99999999-9999-9999-9999-999999999999")
        val raw = context("vi").getString(R.string.transactions_generated_title_balance_adjustment)
        val tx = lending(raw).copy(primaryKindWireValue = "expense", transferSubtypeWireValue = null, debtIntentWireValue = null, categoryId = category.id)
        compose.setContent {
            val english = remember { context("en") }
            CompositionLocalProvider(LocalContext provides english, LocalConfiguration provides english.resources.configuration) {
                Text(localizedTransactionTitle(tx, category))
            }
        }
        compose.onNodeWithText(raw).assertExists()
        compose.onNodeWithText(context("en").getString(R.string.transactions_generated_title_balance_adjustment)).assertDoesNotExist()
    }
}
