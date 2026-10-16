package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

internal fun eligibleInstallmentWallets(owner: String, preferredId: String?, wallets: List<LedgerWalletRecord>, currencyCode: String): List<LedgerWalletRecord> =
    wallets.filter { it.ownerUserId == owner && it.deletedAt == null && it.kind != null && it.kind != WalletKind.CREDIT_CARD &&
        (!it.isArchived || it.id == preferredId) && installmentPaymentCurrenciesMatch(currencyCode, it.currencyCode) }.sortedWith(compareBy(LedgerWalletRecord::sortOrder, LedgerWalletRecord::name, LedgerWalletRecord::id))

internal data class InstallmentEditorState(
    val owner: String, val id: String, val baselinePayload: String?, val name: String, val amountText: String,
    val dueDay: Int, val frequencyMonths: Int, val totalCyclesText: String, val paymentWalletId: String?,
    val currencyCode: String, val iconSymbolName: String,
) {
    fun baseline(): InstallmentPlanRecord? = decodeInstallmentBaseline(owner, id, baselinePayload)
    fun amountMinor(): Long? {
        val input = amountText.trim()
        if (!Regex("-?[0-9,]+").matches(input)) return null
        return input.replace(",", "").toLongOrNull()
    }
    fun toDraft(wallets: List<LedgerWalletRecord>): InstallmentDraft {
        if (!editorUuid(owner) || !editorUuid(id)) inputFailure(InstallmentValidationError.INVALID_IDENTITY)
        val original = baseline()
        val currency = currencyCode.trim().uppercase(Locale.ROOT)
        if (!Regex("[A-Z]{3}").matches(currency) || (original != null && currency != original.currencyCode)) inputFailure(InstallmentValidationError.INVALID_CURRENCY)
        val title = name.trim().takeIf(String::isNotEmpty) ?: inputFailure(InstallmentValidationError.NAME_REQUIRED)
        val amount = amountMinor()?.takeIf { it > 0 } ?: inputFailure(InstallmentValidationError.INVALID_AMOUNT)
        if (dueDay !in 1..31 && original?.dueDay != dueDay) inputFailure(InstallmentValidationError.INVALID_DAYS)
        if (frequencyMonths !in 1..12 && original?.frequencyMonths != frequencyMonths) inputFailure(InstallmentValidationError.INVALID_FREQUENCY)
        val countText = totalCyclesText.trim()
        val count = if (countText.isEmpty()) null else countText.toIntOrNull() ?: inputFailure(InstallmentValidationError.INVALID_TOTAL_CYCLES)
        wallets.firstOrNull { it.id == paymentWalletId && it.ownerUserId == owner }?.let { selected ->
            if (!installmentPaymentCurrenciesMatch(currency, selected.currencyCode)) inputFailure(InstallmentValidationError.WALLET_CURRENCY_MISMATCH)
        }
        val wallet = eligibleInstallmentWallets(owner, original?.paymentWalletId, wallets, currency).firstOrNull { it.id == paymentWalletId }
            ?: inputFailure(InstallmentValidationError.INVALID_WALLET)
        return InstallmentDraft(id, title, amount, dueDay, frequencyMonths, count, wallet.id, currency, iconSymbolName, original)
    }
    companion object {
        fun scopedSaver(owner:String,id:String,currency:String,editingExisting:Boolean):Saver<InstallmentEditorState,Any> = Saver(
            save={state ->
                if(state.owner!=owner || state.id!=id || state.currencyCode!=currency || (state.baselinePayload!=null)!=editingExisting) null
                else with(saver(owner,id)) {save(state)}?.let {listOf(owner,id,currency,editingExisting,it)}
            },
            restore={value ->
                val items=value as? List<*>
                if(items?.size!=5 || items[0]!=owner || items[1]!=id || items[2]!=currency || items[3]!=editingExisting) null
                else items[4]?.let {raw -> runCatching {saver(owner,id).restore(raw)}.getOrNull()}
                    ?.takeIf {it.currencyCode==currency && (it.baselinePayload!=null)==editingExisting}
            },
        )
        fun fresh(owner: String, id: String, currency: String) = InstallmentEditorState(owner, id, null, "", "", 15, 1, "", null,
            currency.trim().uppercase(Locale.ROOT), "mistia.plan.installment")
        fun from(owner: String, plan: InstallmentPlanRecord): InstallmentEditorState {
            require(plan.ownerUserId == owner && !plan.isArchived && plan.deletedAt == null)
            return InstallmentEditorState(owner, plan.id, plan.toPayload().toString(), plan.name, installmentAmountInput(plan.amountPerCycleMinor.toString()),
                plan.dueDay, plan.frequencyMonths.coerceAtLeast(1), plan.totalCycles?.toString().orEmpty(), plan.paymentWalletId, plan.currencyCode, plan.iconSymbolName)
        }
        fun saver(owner: String, id: String) = listSaver<InstallmentEditorState, Any>(
            save = { listOf(it.owner, it.id, it.baselinePayload.orEmpty(), it.name, it.amountText, it.dueDay, it.frequencyMonths,
                it.totalCyclesText, it.paymentWalletId.orEmpty(), it.currencyCode, it.iconSymbolName) },
            restore = { values -> runCatching {
                if (values.size != 11 || values[0] != owner || values[1] != id || !editorUuid(owner) || !editorUuid(id)) return@runCatching null
                val state = InstallmentEditorState(owner, id, (values[2] as String).ifEmpty { null }, values[3] as String, values[4] as String,
                    values[5] as Int, values[6] as Int, values[7] as String, (values[8] as String).ifEmpty { null }, values[9] as String, values[10] as String)
                val baseline = state.baseline()
                if (baseline != null && state.currencyCode != baseline.currencyCode) null else state
            }.getOrNull() },
        )
    }
}

internal data class InstallmentEditorNavigation(val owner: String, val editorId: String?, val baselinePayload: String?, val currency: String) {
    fun baseline(): InstallmentPlanRecord? = editorId?.let { decodeInstallmentBaseline(owner, it, baselinePayload) }
    fun valid(): Boolean = runCatching {
        if (!editorUuid(owner)) false
        else if (editorId == null) baselinePayload == null
        else if (!editorUuid(editorId)) false
        else if (baselinePayload == null) Regex("[A-Z]{3}").matches(currency)
        else baseline()?.currencyCode == currency
    }.getOrDefault(false)
    fun closed() = copy(editorId = null, baselinePayload = null)
    companion object {
        fun closed(owner: String) = InstallmentEditorNavigation(owner, null, null, "JPY")
        fun create(owner: String, currency: String, id: String) = InstallmentEditorNavigation(owner, id, null, currency.trim().uppercase(Locale.ROOT))
        fun edit(owner: String, plan: InstallmentPlanRecord) = InstallmentEditorNavigation(owner, plan.id, plan.toPayload().toString(), plan.currencyCode)
        fun saver(owner: String) = listSaver<InstallmentEditorNavigation, Any>(
            save = { listOf(it.owner, it.editorId.orEmpty(), it.baselinePayload.orEmpty(), it.currency) },
            restore = { values -> runCatching {
                if (values.size != 4 || values[0] != owner) return@runCatching null
                InstallmentEditorNavigation(owner, (values[1] as String).ifEmpty { null }, (values[2] as String).ifEmpty { null }, values[3] as String).takeIf { it.valid() }
            }.getOrNull() },
        )
    }
}

/** Swift uses grouped minor integers. Keep invalid punctuation visible for explicit validation. */
internal fun installmentAmountInput(text: String): String = groupedMinorAmountInput(text)

internal suspend fun <T> guardedInstallmentMutation(block: suspend () -> Result<T>): Result<T> {
    currentCoroutineContext().ensureActive()
    return try {
        val result = block()
        currentCoroutineContext().ensureActive()
        (result.exceptionOrNull() as? CancellationException)?.let { throw it }
        result
    } catch (cancelled: CancellationException) { throw cancelled }
    catch (error: Exception) { currentCoroutineContext().ensureActive(); Result.failure(error) }
}

private val editorUuidPattern = Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
private fun editorUuid(value: String): Boolean = editorUuidPattern.matches(value) && UUID.fromString(value).toString() == value
private fun decodeInstallmentBaseline(owner: String, id: String, payload: String?): InstallmentPlanRecord? {
    if (payload == null) return null
    return runCatching {
        val fields = Json.parseToJsonElement(payload).jsonObject
        val record = InstallmentPlanRecord.fromCloudRecord(CloudRecord(CloudEntity.INSTALLMENT_PLAN.table, id, owner, fields, null, null, 0))
        require(record.ownerUserId == owner && record.id == id && !record.isArchived && record.deletedAt == null)
        record
    }.getOrElse { inputFailure(InstallmentValidationError.INVALID_IDENTITY) }
}
private fun inputFailure(reason: InstallmentValidationError): Nothing = throw InstallmentValidationException(reason)
