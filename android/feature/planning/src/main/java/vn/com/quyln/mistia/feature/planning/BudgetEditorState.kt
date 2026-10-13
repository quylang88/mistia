package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.util.Currency
import vn.com.quyln.mistia.core.model.*

data class BudgetEditorState(
    val id: String?,
    val sourceMonth: String?,
    val selectedMonth: String,
    val categoryId: String?,
    val amountText: String,
    val currencyCode: String,
    val rolloverEnabled: Boolean,
) {
    fun selectCategory(category: String, branchCurrency: String?): BudgetEditorState = copy(
        categoryId = category,
        currencyCode = if (id == null) branchCurrency ?: currencyCode else currencyCode,
        amountText = if (id == null && branchCurrency != null && branchCurrency != currencyCode) "" else amountText,
    )
    fun isReadOnly(now: Instant, zone: ZoneId): Boolean = id != null && YearMonth.parse(selectedMonth) < YearMonth.from(now.atZone(zone))
    fun canArchive(now: Instant, zone: ZoneId): Boolean = id != null && sourceMonth == selectedMonth && isReadOnly(now, zone)
    fun canDelete(now: Instant, zone: ZoneId): Boolean = id != null && sourceMonth == selectedMonth && !isReadOnly(now, zone)
    fun toDraft(zone: ZoneId): BudgetDraft {
        if (categoryId == null) throw BudgetValidationException(BudgetValidationError.CATEGORY_REQUIRED)
        val amount = runCatching {
            val digits = Currency.getInstance(currencyCode).defaultFractionDigits.coerceAtLeast(0)
            BigDecimal(amountText.trim().replace(",", "")).movePointRight(digits)
                .setScale(0, RoundingMode.UNNECESSARY).longValueExact()
        }.getOrNull()?.takeIf { it > 0 } ?: throw BudgetValidationException(BudgetValidationError.INVALID_AMOUNT)
        return BudgetDraft(categoryId = categoryId, monthAnchor = YearMonth.parse(selectedMonth).atDay(1).atStartOfDay(zone).toInstant().toString(),
            limitMinor = amount, currencyCode = currencyCode, id = id, editingExisting = id != null,
            rolloverEnabled = rolloverEnabled, zoneId = zone)
    }
    companion object {
        fun fresh(month: YearMonth, currency: String) = BudgetEditorState(null, null, month.toString(), null, "", currency, false)
        fun from(plan: BudgetPlanRecord?, month: YearMonth, zone: ZoneId, currency: String = "JPY"): BudgetEditorState {
            if (plan == null) return fresh(month, currency)
            val digits = runCatching { Currency.getInstance(plan.currencyCode).defaultFractionDigits.coerceAtLeast(0) }.getOrDefault(0)
            return BudgetEditorState(plan.id, budgetMonth(plan.monthAnchor, zone).toString(), month.toString(), plan.categoryId,
                BigDecimal.valueOf(plan.limitMinor, digits).stripTrailingZeros().toPlainString(), plan.currencyCode, plan.rolloverEnabled)
        }
        fun scopedSaver(ownerId: String): Saver<BudgetEditorState, Any> = Saver(
            save = { state -> with(Saver) { save(state) }?.let { listOf(ownerId, it) } },
            restore = { value ->
                val items = value as? List<*>
                if (items?.size != 2 || items[0] != ownerId) null else items[1]?.let { Saver.restore(it) }
            },
        )
        val Saver: Saver<BudgetEditorState, Any> = listSaver(
            save = { listOf(it.id.orEmpty(), it.sourceMonth.orEmpty(), it.selectedMonth, it.categoryId.orEmpty(), it.amountText, it.currencyCode, it.rolloverEnabled) },
            restore = { BudgetEditorState((it[0] as String).ifEmpty { null }, (it[1] as String).ifEmpty { null }, it[2] as String,
                (it[3] as String).ifEmpty { null }, it[4] as String, it[5] as String, it[6] as Boolean) },
        )
    }
}
