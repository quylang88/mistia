package vn.com.quyln.mistia.core.model

import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode
import java.text.Collator
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.util.Locale

enum class BudgetHealth { STABLE, CAUTION, EXCEEDED }
data class BudgetPace(
    val health: BudgetHealth,
    val projectedSpentMinor: Long,
    val dailyAllowanceMinor: Long,
    val daysRemaining: Int,
    val isPastMonth: Boolean,
    val isFutureMonth: Boolean,
)
data class BudgetRow(
    val plan: BudgetPlanRecord,
    val name: String,
    val icon: String,
    val colorHex: String,
    val spentMinor: Long,
    val pace: BudgetPace,
)
data class BudgetBranchRow(
    val id: String,
    val name: String,
    val icon: String,
    val colorHex: String,
    val currencyCode: String,
    val limitMinor: Long,
    val spentMinor: Long,
    val allocatedMinor: Long,
    val unallocatedMinor: Long,
    val primaryBudgetId: String?,
    val parentBudgetId: String?,
    val children: List<BudgetRow>,
    val pace: BudgetPace,
)
data class BudgetProjection(
    val branches: List<BudgetBranchRow>,
    val totalLimitMinor: Long,
    val totalSpentMinor: Long,
    val remainingMinor: Long,
)

fun activeBudgetPlans(owner: UserId, plans: List<BudgetPlanRecord>, month: YearMonth, zone: ZoneId,
    categories: List<TransactionCategoryRecord> = emptyList(),
): List<BudgetPlanRecord> {
    val index = CategoryIdentityIndex(owner, categories)
    return plans.filter { it.ownerUserId == owner.value && !it.isArchived && it.deletedAt == null && budgetMonth(it.monthAnchor, zone) <= month }
        .groupBy { plan ->
            val category = index.logical(plan.categoryIdSnapshot ?: plan.categoryId)
            listOf(category ?: groupingKey(plan.categoryNameSnapshot.orEmpty()),
                if (category == null) groupingKey(plan.categoryParentNameSnapshot.orEmpty()) else "",
                if (category == null) plan.categoryIsParentSnapshot.toString() else "", currency(plan.currencyCode))
        }.values.map { group ->
            group.maxWith(compareBy<BudgetPlanRecord>({ budgetMonth(it.monthAnchor, zone) }, { it.id }))
        }.sortedBy { it.id }
}

/** Current continuity and future anchors can coexist with a newly saved monthly plan. */
fun budgetCurrencyConstraints(owner: UserId, plans: List<BudgetPlanRecord>, month: YearMonth, zone: ZoneId,
    categories: List<TransactionCategoryRecord> = emptyList(),
): List<BudgetPlanRecord> =
    (activeBudgetPlans(owner, plans, month, zone, categories) + plans.filter {
        it.ownerUserId == owner.value && !it.isArchived && it.deletedAt == null && budgetMonth(it.monthAnchor, zone) > month
    }).distinctBy { it.id }

fun budgetPace(spent: Long, limit: Long, month: YearMonth, reference: Instant, zone: ZoneId): BudgetPace {
    val date = reference.atZone(zone).toLocalDate()
    val past = month < YearMonth.from(date)
    val future = month > YearMonth.from(date)
    val days = month.lengthOfMonth()
    val elapsed = if (past) days else if (future) 0 else date.dayOfMonth.coerceIn(1, days)
    val remainingDays = if (past) 0 else if (future) days else days - elapsed
    val projected = if (past || future || elapsed == 0 || spent <= 0) maxOf(spent, 0) else {
        BigDecimal.valueOf(spent).multiply(BigDecimal.valueOf(days.toLong()))
            .divide(BigDecimal.valueOf(elapsed.toLong()), 0, RoundingMode.HALF_UP).toBigInteger().clamped()
    }
    // Swift's 15% pace buffer and 1e-9 comparison tolerance, without binary accounting.
    val numerator = maxOf(spent, 0).big().multiply(days.big()).multiply(100.big())
        .subtract(limit.big().multiply(elapsed.big()).multiply(115.big()))
    val aboveBuffer = numerator.multiply(1_000_000_000.big()) > limit.big().multiply(days.big()).multiply(100.big())
    val health = when {
        future -> BudgetHealth.STABLE
        limit > 0 && spent >= limit -> BudgetHealth.EXCEEDED
        past || limit <= 0 || elapsed <= 0 -> BudgetHealth.STABLE
        aboveBuffer -> BudgetHealth.CAUTION
        else -> BudgetHealth.STABLE
    }
    val allowance = if (remainingDays == 0) 0 else limit.big().subtract(spent.big()).max(BigInteger.ZERO)
        .divide(remainingDays.big()).clamped()
    return BudgetPace(health, projected, allowance, remainingDays, past, future)
}

fun projectBudgets(
    owner: UserId,
    plans: List<BudgetPlanRecord>,
    categories: List<TransactionCategoryRecord>,
    transactions: List<LedgerTransactionRecord>,
    wallets: List<LedgerWalletRecord>,
    selectedMonth: YearMonth,
    referenceDate: Instant,
    zone: ZoneId,
    rates: List<ExchangeRateSnapshot>,
    language: CategoryNameLanguage,
    adjustmentTitles: Set<String>,
    reportingCurrency: String,
    deletedCategoryName: String = "",
): BudgetProjection {
    val index = CategoryIdentityIndex(owner, categories)
    val walletById = wallets.filter { it.ownerUserId == owner.value }.associateBy { it.id }
    val active = activeBudgetPlans(owner, plans, selectedMonth, zone, categories)
    val monthStart = selectedMonth.atDay(1).atStartOfDay(zone).toInstant()
    val monthEnd = selectedMonth.plusMonths(1).atDay(1).atStartOfDay(zone).toInstant()
    fun name(plan: BudgetPlanRecord, parent: Boolean = false): String {
        val live = if (parent) index.category(plan.categoryParentIdSnapshot ?: index.category(plan.categoryId)?.parentCategoryId)
            else index.category(plan.categoryId)
        val vi = if (parent) plan.categoryParentNameSnapshot else plan.categoryNameSnapshot
        val localized = when (language) {
            CategoryNameLanguage.VIETNAMESE -> vi
            CategoryNameLanguage.ENGLISH -> if (parent) plan.categoryParentNameEnglishSnapshot else plan.categoryNameEnglishSnapshot
            CategoryNameLanguage.JAPANESE -> if (parent) plan.categoryParentNameJapaneseSnapshot else plan.categoryNameJapaneseSnapshot
        }
        return localized.nonblank() ?: vi.nonblank() ?: live?.localizedBudgetName(language) ?: deletedCategoryName
    }
    fun allocation(plan: BudgetPlanRecord) = plan.logicalAllocation(index)
    fun spent(plan: BudgetPlanRecord, branch: Boolean): Long {
        val snapshot = allocation(plan)
        val targetId = if (branch) snapshot.branchCategoryId else snapshot.categoryId
        val targetName = groupingKey(name(plan, parent = branch && !snapshot.categoryIsParent))
        val start = if (plan.rolloverEnabled) minOf(budgetMonth(plan.monthAnchor, zone).atDay(1).atStartOfDay(zone).toInstant(), monthStart) else monthStart
        return transactions.asSequence().filter { it.ownerUserId == owner.value && it.entryStatus == TransactionEntryStatus.POSTED && !it.isArchived && it.deletedAt == null }
            .distinctBy { it.id }.filter { Instant.parse(it.occurredAt) >= start && Instant.parse(it.occurredAt) < monthEnd }
            .filter { record ->
                val category = index.category(record.categoryId)
                val identity = index.logical(if (branch) category?.parentCategoryId ?: record.categoryId else record.categoryId)
                val names = if (branch) listOf(category?.localizedBudgetName(language), index.category(category?.parentCategoryId)?.localizedBudgetName(language))
                    else listOf(category?.localizedBudgetName(language))
                (targetId != null && identity == targetId) || (targetName.isNotEmpty() && names.any { it != null && groupingKey(it) == targetName })
            }.map { record ->
                val expense = reportedBudgetExpense(record, index.category(record.categoryId), walletById[record.sourceWalletId], adjustmentTitles)
                planningMoneyMinorExact(expense, record.sourceCurrencyCode, plan.currencyCode, rates)
            }.fold(BigInteger.ZERO) { sum, amount -> sum.add(amount) }.clamped()
    }
    val rowComparator = Comparator<BudgetRow> { a, b ->
        val ratio = compareProgress(b.spentMinor, b.plan.limitMinor, a.spentMinor, a.plan.limitMinor)
        if (ratio != 0) ratio else Collator.getInstance().compare(a.name, b.name)
    }
    val branches = active.groupBy { allocation(it).branchCategoryId }.mapNotNull { (branchId, branchPlans) ->
        branchId ?: return@mapNotNull null
        val parent = branchPlans.firstOrNull { allocation(it).categoryIsParent }
        val children = branchPlans.filterNot { allocation(it).categoryIsParent }.map { plan ->
            val amount = spent(plan, false)
            BudgetRow(plan, name(plan), plan.categoryIconSymbolNameSnapshot ?: index.category(plan.categoryId)?.iconSymbolName ?: "questionmark.circle.fill",
                plan.categoryColorHexSnapshot ?: index.category(plan.categoryId)?.iconColorHex ?: "#8A8A8E", amount,
                budgetPace(amount, plan.limitMinor, selectedMonth, referenceDate, zone))
        }.sortedWith(rowComparator)
        val template = parent ?: branchPlans.first()
        val code = template.currencyCode
        val childLimit = sumBudgetExact(children.map { planningMoneyMinorExact(it.plan.limitMinor, it.plan.currencyCode, code, rates) })
        val totalSpent = if (parent != null) spent(parent, true) else sumBudgetExact(children.map { planningMoneyMinorExact(it.spentMinor, it.plan.currencyCode, code, rates) })
        val limit = parent?.limitMinor ?: childLimit
        val onlyChild = parent == null && children.size == 1
        val branchName = if (onlyChild) children.single().name else name(template, parent = parent == null)
        BudgetBranchRow(branchId, branchName,
            if (onlyChild) children.single().icon else parent?.categoryIconSymbolNameSnapshot ?: parent?.let { index.category(it.categoryId)?.iconSymbolName } ?: template.categoryParentIconSymbolNameSnapshot ?: index.category(index.category(template.categoryId)?.parentCategoryId)?.iconSymbolName ?: "questionmark.circle.fill",
            if (onlyChild) children.single().colorHex else parent?.categoryColorHexSnapshot ?: parent?.let { index.category(it.categoryId)?.iconColorHex } ?: template.categoryParentColorHexSnapshot ?: index.category(index.category(template.categoryId)?.parentCategoryId)?.iconColorHex ?: "#8A8A8E",
            code, limit, totalSpent, childLimit, limit.big().subtract(childLimit.big()).max(BigInteger.ZERO).clamped(),
            parent?.id ?: children.singleOrNull()?.plan?.id, parent?.id, if (onlyChild) emptyList() else children,
            budgetPace(totalSpent, limit, selectedMonth, referenceDate, zone))
    }.sortedWith { a, b ->
        val ratio = compareProgress(b.spentMinor, b.limitMinor, a.spentMinor, a.limitMinor)
        if (ratio != 0) ratio else Collator.getInstance().compare(a.name, b.name)
    }
    val limit = sumBudgetExact(branches.map { planningMoneyMinorExact(it.limitMinor, it.currencyCode, reportingCurrency, rates) })
    val spent = sumBudgetExact(branches.map { planningMoneyMinorExact(it.spentMinor, it.currencyCode, reportingCurrency, rates) })
    return BudgetProjection(branches, limit, spent, limit.big().subtract(spent.big()).max(BigInteger.ZERO).clamped())
}

fun TransactionCategoryRecord.localizedBudgetName(language: CategoryNameLanguage): String = when (language) {
    CategoryNameLanguage.VIETNAMESE -> name
    CategoryNameLanguage.ENGLISH -> nameEnglish.nonblank() ?: name
    CategoryNameLanguage.JAPANESE -> nameJapanese.nonblank() ?: name
}

private fun reportedBudgetExpense(record: LedgerTransactionRecord, category: TransactionCategoryRecord?, wallet: LedgerWalletRecord?, adjustmentTitles: Set<String>): Long {
    record.reportingExpenseMinor?.let { return it }
    if (category?.isBalanceAdjustmentSystemCategory == true || record.categoryId == TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID ||
        record.categoryId == TransactionCategoryRecord.BALANCE_ADJUSTMENT_INCOME_ID || adjustmentTitles.any { it.trim().equals(record.title.trim(), ignoreCase = true) }) return 0
    if (category?.systemKey == "loan_repayment" || record.categoryId == "d872b8af-d28a-5b90-8822-839dfa097b23") return 0
    val paidFor = record.primaryKind == TransactionPrimaryKind.TRANSFER && record.transferSubtype == TransactionTransferSubtype.DEBT &&
        record.debtIntent == TransactionDebtIntent.BORROW && record.sourceWalletId == null && record.categoryId != null
    if (paidFor) return record.amountMinor
    if (record.primaryKind != TransactionPrimaryKind.EXPENSE) return 0
    val title = record.title.lowercase(Locale.ROOT)
    val cardTitle = listOf("card payment", "thanh toán thẻ", "thanh toan the", "カード支払い").any(title::contains)
    return if (wallet?.kind != WalletKind.CREDIT_CARD && cardTitle) 0 else record.amountMinor
}
private fun currency(value: String?): String = value?.trim()?.uppercase(Locale.ROOT)?.takeIf { it == "JPY" || it == "VND" } ?: "JPY"
private fun sumBudgetExact(values: List<BigInteger>): Long = values.fold(BigInteger.ZERO, BigInteger::add).clamped()
private fun groupingKey(value: String): String = value.trim().replace(Regex("\\s+"), " ").lowercase(Locale.ROOT)
private fun String?.nonblank(): String? = this?.trim()?.takeIf(String::isNotEmpty)
private fun Long.big(): BigInteger = BigInteger.valueOf(this)
private fun Int.big(): BigInteger = toLong().big()
private fun BigInteger.clamped(): Long = max(BigInteger.valueOf(Long.MIN_VALUE)).min(BigInteger.valueOf(Long.MAX_VALUE)).toLong()
private fun compareProgress(a: Long, aLimit: Long, b: Long, bLimit: Long): Int {
    val aa = if (aLimit > 0) a else 0
    val bb = if (bLimit > 0) b else 0
    return aa.big().multiply(maxOf(bLimit, 1).big()).compareTo(bb.big().multiply(maxOf(aLimit, 1).big()))
}

fun BudgetPlanRecord.localizedBudgetPath(language: CategoryNameLanguage): String? {
    val path = when (language) {
        CategoryNameLanguage.VIETNAMESE -> categoryPathSnapshot
        CategoryNameLanguage.ENGLISH -> categoryPathEnglishSnapshot
        CategoryNameLanguage.JAPANESE -> categoryPathJapaneseSnapshot
    }.nonblank() ?: categoryPathSnapshot.nonblank()
    val name = when (language) {
        CategoryNameLanguage.VIETNAMESE -> categoryNameSnapshot
        CategoryNameLanguage.ENGLISH -> categoryNameEnglishSnapshot
        CategoryNameLanguage.JAPANESE -> categoryNameJapaneseSnapshot
    }.nonblank() ?: categoryNameSnapshot.nonblank()
    return path ?: name
}

fun budgetQuickCategories(
    owner: UserId,
    categories: List<TransactionCategoryRecord>,
    transactions: List<LedgerTransactionRecord>,
    favorites: Boolean,
    reference: Instant,
    zone: ZoneId,
): List<TransactionCategoryRecord> {
    val allowed = categories.filter { it.ownerUserId == owner.value && it.kind == TransactionCategoryKind.EXPENSE &&
        it.hierarchyRole == CategoryHierarchyRole.CHILD && !it.isArchived && it.deletedAt == null && !it.isBalanceAdjustmentSystemCategory }
    if (favorites) return allowed.filter { it.isFavorite }
        .sortedWith(compareBy(TransactionCategoryRecord::sortOrder, TransactionCategoryRecord::name, TransactionCategoryRecord::id))
    val cutoff = reference.atZone(zone).minusDays(90).toInstant()
    val usage = transactions.filter { it.ownerUserId == owner.value && !it.isArchived && it.deletedAt == null &&
        it.entryStatus == TransactionEntryStatus.POSTED && Instant.parse(it.occurredAt) >= cutoff }.groupBy { it.categoryId }
    return allowed.filter { it.id in usage }.sortedWith(
        compareByDescending<TransactionCategoryRecord> { usage[it.id]!!.size }
            .thenByDescending { usage[it.id]!!.maxOf { row -> Instant.parse(row.occurredAt) } }
            .thenBy { it.sortOrder }.thenBy { it.name }.thenBy { it.id }
    ).take(10)
}
