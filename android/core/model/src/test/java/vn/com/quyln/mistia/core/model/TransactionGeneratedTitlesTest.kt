package vn.com.quyln.mistia.core.model

import java.util.Locale
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
class TransactionGeneratedTitlesTest(private val kind: GeneratedTransactionTitle, private val language: String) {
    companion object {
        private val catalog = Json.parseToJsonElement(requireNotNull(TransactionGeneratedTitlesTest::class.java.getResourceAsStream("/Localizable.xcstrings"))
            .bufferedReader().use { it.readText() }).jsonObject.getValue("strings").jsonObject
        private val titles = GeneratedTransactionTitle.entries.associateWith { kind ->
            listOf("en", "ja", "vi").map { language -> catalog.getValue(kind.localizationKey).jsonObject.getValue("localizations")
                .jsonObject.getValue(language).jsonObject.getValue("stringUnit").jsonObject.getValue("value").jsonPrimitive.content }
        }
        @JvmStatic @Parameterized.Parameters(name = "{0}-{1}") fun cases(): List<Array<Any>> =
            GeneratedTransactionTitle.entries.flatMap { kind -> listOf("en", "ja", "vi").map { arrayOf(kind, it) } }
    }
    private val raw get() = catalog.getValue(kind.localizationKey).jsonObject.getValue("localizations").jsonObject.getValue(language)
        .jsonObject.getValue("stringUnit").jsonObject.getValue("value").jsonPrimitive.content
    private val intent get() = when(kind) {
        GeneratedTransactionTitle.LEND -> TransactionDebtIntent.LEND
        GeneratedTransactionTitle.COLLECT -> TransactionDebtIntent.COLLECT
        GeneratedTransactionTitle.BORROW -> TransactionDebtIntent.BORROW
        GeneratedTransactionTitle.REPAY -> TransactionDebtIntent.REPAY
        else -> null
    }
    private val subtype get() = when(kind) {
        GeneratedTransactionTitle.INTERNAL_TRANSFER -> TransactionTransferSubtype.INTERNAL_TRANSFER
        GeneratedTransactionTitle.FAMILY_TRANSFER_SENT, GeneratedTransactionTitle.FAMILY_TRANSFER_RECEIVED -> TransactionTransferSubtype.FAMILY_TRANSFER
        else -> TransactionTransferSubtype.DEBT
    }
    private fun resolve(title: String = raw, primary: TransactionPrimaryKind = if(kind == GeneratedTransactionTitle.BALANCE_ADJUSTMENT) TransactionPrimaryKind.EXPENSE else TransactionPrimaryKind.TRANSFER,
        transfer: TransactionTransferSubtype? = subtype, debt: TransactionDebtIntent? = intent,
        categoryId: String? = TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID, systemKey: String? = null) =
        generatedTransactionTitle(title, primary, transfer, debt, categoryId, systemKey, titles)
    @Test fun `recognizes stored title in every shared language with Swift semantic restrictions`() {
        assertEquals(kind, resolve())
        assertEquals(kind, resolve(" \t\u00a0" + raw.uppercase(Locale.ROOT) + "\n"))
        assertNull(resolve(raw + " A")); assertNull(resolve("  \n")); assertNull(resolve("My title"))
        if(kind == GeneratedTransactionTitle.BALANCE_ADJUSTMENT) {
            assertNull(resolve(categoryId = null)); assertNull(resolve(primary = TransactionPrimaryKind.INCOME, categoryId = "other", systemKey = "loan_repayment"))
        } else {
            assertNull(resolve(transfer = null))
            assertNull(resolve(primary = TransactionPrimaryKind.EXPENSE, categoryId = null))
        }
        if(intent != null) assertNull(resolve(debt = TransactionDebtIntent.entries.first { it != intent }))
        if(intent != null) assertEquals(kind, resolve(debt = null))
        if(kind == GeneratedTransactionTitle.BALANCE_ADJUSTMENT) {
            assertEquals(kind, resolve(primary = TransactionPrimaryKind.INCOME, categoryId = TransactionCategoryRecord.BALANCE_ADJUSTMENT_INCOME_ID))
            assertEquals(kind, resolve(categoryId = "legacy", systemKey = TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_KEY))
            assertEquals(kind, resolve(primary = TransactionPrimaryKind.INCOME, categoryId = "legacy", systemKey = TransactionCategoryRecord.BALANCE_ADJUSTMENT_INCOME_KEY))
        }
    }
}
