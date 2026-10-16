package vn.com.quyln.mistia.core.designsystem

import android.content.Context
import android.content.res.Configuration
import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import java.util.Locale
import vn.com.quyln.mistia.core.model.GeneratedTransactionTitle
import vn.com.quyln.mistia.core.model.LedgerTransactionRecord
import vn.com.quyln.mistia.core.model.TransactionCategoryRecord
import vn.com.quyln.mistia.core.model.generatedTransactionTitle

@Composable
fun localizedTransactionTitle(transaction: LedgerTransactionRecord, category: TransactionCategoryRecord? = null): String {
    val kind = generatedTransactionTitle(transaction.title, transaction.primaryKind, transaction.transferSubtype, transaction.debtIntent,
        transaction.categoryId, category?.takeIf { it.ownerUserId == transaction.ownerUserId && it.id == transaction.categoryId }?.systemKey,
        GeneratedTitleResources.knownTitles(LocalContext.current))
    return kind?.let { stringResource(it.resourceId()) } ?: transaction.title
}

/** All supported-language generated titles for semantic classification of legacy stored records. */
fun knownTransactionTitles(context:Context):Map<GeneratedTransactionTitle,Collection<String>> = GeneratedTitleResources.knownTitles(context)

/** Cache only immutable strings, never an Activity/context or an account's records. */
private object GeneratedTitleResources {
    private var cached: Map<GeneratedTransactionTitle, Collection<String>>? = null
    @Synchronized fun knownTitles(context: Context): Map<GeneratedTransactionTitle, Collection<String>> {
        cached?.let { return it }
        val localizedResources = listOf("vi", "en", "ja").map { language ->
            val configuration = Configuration(context.resources.configuration).apply { setLocale(Locale.forLanguageTag(language)) }
            context.applicationContext.createConfigurationContext(configuration).resources
        }
        return GeneratedTransactionTitle.entries.associateWith { kind -> localizedResources.map { it.getString(kind.resourceId()) } }
            .also { cached = it }
    }
}

@StringRes
private fun GeneratedTransactionTitle.resourceId(): Int = when (this) {
    GeneratedTransactionTitle.INTERNAL_TRANSFER -> R.string.transactions_transactioneditor_internal_transfer
    GeneratedTransactionTitle.FAMILY_TRANSFER_SENT -> R.string.transactions_generated_title_family_transfer_sent
    GeneratedTransactionTitle.FAMILY_TRANSFER_RECEIVED -> R.string.transactions_generated_title_family_transfer_received
    GeneratedTransactionTitle.BALANCE_ADJUSTMENT -> R.string.transactions_generated_title_balance_adjustment
    GeneratedTransactionTitle.LEND -> R.string.shared_corelogic_financeenums_lend
    GeneratedTransactionTitle.COLLECT -> R.string.shared_corelogic_financeenums_collect_debt
    GeneratedTransactionTitle.BORROW -> R.string.shared_corelogic_financeenums_borrow
    GeneratedTransactionTitle.REPAY -> R.string.shared_corelogic_financeenums_repay
}
