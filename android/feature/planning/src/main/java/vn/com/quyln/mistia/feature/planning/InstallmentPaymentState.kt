package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import java.time.Instant
import java.time.YearMonth
import java.util.UUID
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

internal fun eligibleInstallmentPaymentWallets(owner: String, currency: String, wallets: List<LedgerWalletRecord>): List<LedgerWalletRecord> =
    wallets.filter { it.ownerUserId == owner && !it.isArchived && it.deletedAt == null && it.kind != null &&
        it.kind != WalletKind.CREDIT_CARD && it.kind != WalletKind.INVESTMENT && installmentPaymentCurrenciesMatch(currency, it.currencyCode) }
        .sortedWith(compareBy(LedgerWalletRecord::sortOrder, LedgerWalletRecord::name, LedgerWalletRecord::id))

internal data class InstallmentPaymentState(val owner: String, val planId: String, val month: String, val currency: String,
    val amountText: String, val walletId: String?, val initialAmountText: String, val initialWalletId: String?) {
    val changed: Boolean get() = walletId != initialWalletId
    fun request(row: InstallmentDueRow, wallets: List<LedgerWalletRecord>): InstallmentPaymentRequest {
        require(paymentUuid(owner) && paymentUuid(planId) && row.plan.ownerUserId == owner && row.plan.id == planId && row.month.toString() == month)
        require(!row.plan.isArchived && row.plan.deletedAt == null && row.status == DueStatus.PENDING && row.linkedTransactionId == null)
        if (!installmentPaymentCurrenciesMatch(currency, row.plan.currencyCode)) throw BillPaymentException(BillPaymentError.WALLET_CURRENCY_MISMATCH)
        val selected = wallets.firstOrNull { it.id == walletId && it.ownerUserId == owner }
        if (selected != null && !installmentPaymentCurrenciesMatch(row.plan.currencyCode, selected.currencyCode))
            throw BillPaymentException(BillPaymentError.WALLET_CURRENCY_MISMATCH)
        val wallet = eligibleInstallmentPaymentWallets(owner, row.plan.currencyCode, wallets).firstOrNull { it.id == walletId }
            ?: throw BillPaymentException(BillPaymentError.INVALID_WALLET)
        val input = amountText.trim()
        val amount = input.takeIf { Regex("[0-9,]+").matches(it) }?.replace(",", "")?.toLongOrNull()?.takeIf { it > 0 }
            ?: throw BillPaymentException(BillPaymentError.MISSING_AMOUNT)
        if (amount != row.amountMinor) throw BillPaymentException(BillPaymentError.SOURCE_CHANGED)
        return InstallmentPaymentRequest(row.plan, YearMonth.parse(month), RecordId(wallet.id), amount)
    }
    companion object {
        fun initial(owner: String, row: InstallmentDueRow, wallets: List<LedgerWalletRecord>): InstallmentPaymentState {
            require(row.plan.ownerUserId == owner && paymentUuid(owner) && paymentUuid(row.plan.id))
            val amount = installmentAmountInput(row.amountMinor.toString())
            val wallet = eligibleInstallmentPaymentWallets(owner, row.plan.currencyCode, wallets).firstOrNull { it.id == row.plan.paymentWalletId }?.id
            return InstallmentPaymentState(owner, row.plan.id, row.month.toString(), row.plan.currencyCode, amount, wallet, amount, wallet)
        }
        fun saver(owner: String, planId: String, month: String): Saver<InstallmentPaymentState, Any> = listSaver(
            save = { listOf(it.owner, it.planId, it.month, it.currency, it.amountText, it.walletId.orEmpty(), it.initialAmountText, it.initialWalletId.orEmpty()) },
            restore = { values -> runCatching {
                require(values.size == 8 && values[0] == owner && values[1] == planId && values[2] == month && paymentUuid(owner) && paymentUuid(planId))
                require(YearMonth.parse(month).toString() == month)
                val wallet = (values[5] as String).ifEmpty { null }; val original = (values[7] as String).ifEmpty { null }
                require((wallet == null || paymentUuid(wallet)) && (original == null || paymentUuid(original)))
                InstallmentPaymentState(owner, planId, month, values[3] as String, values[4] as String, wallet, values[6] as String, original)
            }.getOrNull() })
    }
}

internal data class InstallmentPaymentNavigation(val owner: String, val month: String, val baselinePayload: String?,
    val amountMinor: Long = 0, val dueDate: String? = null, val status: String? = null, val linkedTransactionId: String? = null) {
    fun row(): InstallmentDueRow? = runCatching {
        val payload = baselinePayload?.let { Json.parseToJsonElement(it).jsonObject } ?: return null
        require(paymentUuid(owner) && YearMonth.parse(month).toString() == month)
        val id = payload.getValue("id").jsonPrimitive.content
        val plan = InstallmentPlanRecord.fromCloudRecord(CloudRecord(CloudEntity.INSTALLMENT_PLAN.table, id, owner, payload, null, null, 0))
        require(paymentUuid(id) && plan.id == id && plan.ownerUserId == owner && !plan.isArchived && plan.deletedAt == null)
        val state = DueStatus.entries.single { it.wireValue == status && it != DueStatus.SKIPPED }
        require(linkedTransactionId == null || paymentUuid(linkedTransactionId))
        require(state != DueStatus.PENDING || linkedTransactionId == null)
        InstallmentDueRow(plan, YearMonth.parse(month), Instant.parse(requireNotNull(dueDate)), amountMinor, state, linkedTransactionId)
    }.getOrNull()
    companion object {
        fun closed(owner: String, month: YearMonth) = InstallmentPaymentNavigation(owner, month.toString(), null)
        fun open(owner: String, row: InstallmentDueRow): InstallmentPaymentNavigation =
            InstallmentPaymentNavigation(owner, row.month.toString(), row.plan.toPayload().toString(), row.amountMinor, row.dueDate.toString(), row.status.wireValue, row.linkedTransactionId)
                .also { require(it.row() == row) }
        fun saver(owner: String, month: YearMonth): Saver<InstallmentPaymentNavigation, Any> = listSaver(
            save = { listOf(it.owner, it.month, it.baselinePayload.orEmpty(), it.amountMinor, it.dueDate.orEmpty(), it.status.orEmpty(), it.linkedTransactionId.orEmpty()) },
            restore = { values -> runCatching {
                require(values.size == 7 && values[0] == owner && values[1] == month.toString())
                val navigation = InstallmentPaymentNavigation(owner, month.toString(), (values[2] as String).ifEmpty { null }, values[3] as Long,
                    (values[4] as String).ifEmpty { null }, (values[5] as String).ifEmpty { null }, (values[6] as String).ifEmpty { null })
                require(navigation.baselinePayload == null || navigation.row() != null)
                navigation
            }.getOrNull() })
    }
}
private fun paymentUuid(value: String): Boolean = Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}").matches(value) && UUID.fromString(value).toString() == value

internal fun installmentPaymentTargetIsCurrent(frozen: InstallmentDueRow, current: InstallmentDueRow?): Boolean =
    current != null && current.plan.ownerUserId == frozen.plan.ownerUserId && current.plan.id == frozen.plan.id &&
        current.month == frozen.month && current.status == frozen.status && current.amountMinor == frozen.amountMinor &&
        current.dueDate == frozen.dueDate && current.linkedTransactionId == frozen.linkedTransactionId
