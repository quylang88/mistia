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
    val health: BudgetHealth?,
    val projectedSpentMinor: BigInteger?,
    val dailyAllowanceMinor: BigInteger?,
    val daysRemaining: Int,
    val isPastMonth: Boolean,
    val isFutureMonth: Boolean,
)
data class BudgetRow(
    val plan: BudgetPlanRecord,
    val name: String,
    val icon: String,
    val colorHex: String,
    val spentMinor: BigInteger?,
    val pace: BudgetPace,
) {
    val currencyCode:String? get()=plan.currencyCode.overviewCurrencyCode()
    val limitMinor:BigInteger? get()=currencyCode?.let {plan.limitMinor.big()}
}
data class BudgetBranchRow(
    val id: String,
    val name: String,
    val icon: String,
    val colorHex: String,
    val currencyCode: String?,
    val limitMinor: BigInteger?,
    val spentMinor: BigInteger?,
    val allocatedMinor: BigInteger?,
    val unallocatedMinor: BigInteger?,
    val primaryBudgetId: String?,
    val parentBudgetId: String?,
    val children: List<BudgetRow>,
    val pace: BudgetPace,
)
data class BudgetProjection(
    val branches: List<BudgetBranchRow>,
    val totalLimitMinor: BigInteger?,
    val totalSpentMinor: BigInteger?,
    val remainingMinor: BigInteger?,
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

fun budgetPace(spent:Long,limit:Long,month:YearMonth,reference:Instant,zone:ZoneId):BudgetPace =
    budgetPace(spent.big(),limit.big(),month,reference,zone)

/** Read-only exact assessment; unknown required spending/limit cannot assert stable health. */
fun budgetPace(spent:BigInteger?,limit:BigInteger?,month:YearMonth,reference:Instant,zone:ZoneId):BudgetPace {
    val date=reference.atZone(zone).toLocalDate()
    val past=month<YearMonth.from(date);val future=month>YearMonth.from(date)
    val days=month.lengthOfMonth()
    val elapsed=if(past) days else if(future) 0 else date.dayOfMonth.coerceIn(1,days)
    val remainingDays=if(past) 0 else if(future) days else days-elapsed
    val projected=spent?.let {value ->
        if(past || future || elapsed==0 || value.signum()<=0) value.max(BigInteger.ZERO)
        else BigDecimal(value).multiply(BigDecimal.valueOf(days.toLong())).divide(BigDecimal.valueOf(elapsed.toLong()),0,RoundingMode.HALF_UP).toBigIntegerExact()
    }
    val health=if(spent==null || limit==null) null else {
        val numerator=spent.max(BigInteger.ZERO).multiply(days.big()).multiply(100.big())
            .subtract(limit.multiply(elapsed.big()).multiply(115.big()))
        val aboveBuffer=numerator.multiply(1_000_000_000.big())>limit.multiply(days.big()).multiply(100.big())
        when {
            future -> BudgetHealth.STABLE
            limit.signum()>0 && spent>=limit -> BudgetHealth.EXCEEDED
            past || limit.signum()<=0 || elapsed<=0 -> BudgetHealth.STABLE
            aboveBuffer -> BudgetHealth.CAUTION
            else -> BudgetHealth.STABLE
        }
    }
    val allowance=if(spent==null || limit==null) null else if(remainingDays==0) BigInteger.ZERO
        else limit.subtract(spent).max(BigInteger.ZERO).divide(remainingDays.big())
    return BudgetPace(health,projected,allowance,remainingDays,past,future)
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
    val walletById = wallets.filter { it.ownerUserId == owner.value && it.deletedAt==null }.associateBy { it.id }
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
    fun convert(amount:BigInteger?,source:String?,target:String?):BigInteger? {
        if(amount==BigInteger.ZERO) return BigInteger.ZERO
        return if(amount==null || source==null || target==null) null else overviewMoneyMinorExact(amount,source,target,rates)
    }
    fun spent(plan:BudgetPlanRecord,branch:Boolean):BigInteger? {
        val snapshot=allocation(plan)
        val targetId=if(branch) snapshot.branchCategoryId else snapshot.categoryId
        val targetName=groupingKey(name(plan,parent=branch && !snapshot.categoryIsParent))
        val start=if(plan.rolloverEnabled) minOf(budgetMonth(plan.monthAnchor,zone).atDay(1).atStartOfDay(zone).toInstant(),monthStart) else monthStart
        var total:BigInteger?=BigInteger.ZERO
        for(record in transactions.asSequence().filter {it.ownerUserId==owner.value && it.entryStatus!=TransactionEntryStatus.DRAFT && !it.isArchived && it.deletedAt==null}.distinctBy {it.id}) {
            val category=index.category(record.categoryId)
            val identity=index.logical(if(branch) category?.parentCategoryId ?: record.categoryId else record.categoryId)
            val names=if(branch) listOf(category?.localizedBudgetName(language),index.category(category?.parentCategoryId)?.localizedBudgetName(language)) else listOf(category?.localizedBudgetName(language))
            if(!((targetId!=null && identity==targetId) || (targetName.isNotEmpty() && names.any {it!=null && groupingKey(it)==targetName}))) continue
            val wallet=walletById[record.sourceWalletId]
            val expense=reportedBudgetExpense(record,category,wallet,adjustmentTitles)
            if(expense==0L) continue
            val occurred=runCatching {Instant.parse(record.occurredAt)}.getOrNull()
            if(occurred!=null && (occurred<start || occurred>=monthEnd)) continue
            val source=if(record.sourceCurrencyCode!=null) record.sourceCurrencyCode.overviewCurrencyCode()
                else if(wallet!=null) wallet.currencyCode.overviewCurrencyCode() else "JPY"
            val amount=if(record.entryStatus!=TransactionEntryStatus.POSTED || occurred==null) null else convert(expense?.big(),source,plan.currencyCode.overviewCurrencyCode())
            total=total?.let {subtotal ->amount?.let(subtotal::plus)}
        }
        return total
    }
    val rowComparator = Comparator<BudgetRow> { a, b ->
        val ratio = compareProgress(b.spentMinor,b.limitMinor,a.spentMinor,a.limitMinor)
        if (ratio != 0) ratio else Collator.getInstance().compare(a.name, b.name)
    }
    val branches = active.groupBy { allocation(it).branchCategoryId }.mapNotNull { (branchId, branchPlans) ->
        branchId ?: return@mapNotNull null
        val parent = branchPlans.firstOrNull { allocation(it).categoryIsParent }
        val children = branchPlans.filterNot { allocation(it).categoryIsParent }.map { plan ->
            val amount = spent(plan, false)
            BudgetRow(plan, name(plan), plan.categoryIconSymbolNameSnapshot ?: index.category(plan.categoryId)?.iconSymbolName ?: "questionmark.circle.fill",
                plan.categoryColorHexSnapshot ?: index.category(plan.categoryId)?.iconColorHex ?: "#8A8A8E", amount,
                budgetPace(amount,plan.currencyCode.overviewCurrencyCode()?.let {plan.limitMinor.big()},selectedMonth,referenceDate,zone))
        }.sortedWith(rowComparator)
        val template = parent ?: branchPlans.first()
        val code=template.currencyCode.overviewCurrencyCode()
        val childLimit = sumBudgetExact(children.map {convert(it.limitMinor,it.currencyCode,code)})
        val totalSpent = if (parent != null) spent(parent, true) else sumBudgetExact(children.map {convert(it.spentMinor,it.currencyCode,code)})
        val limit=if(parent!=null) code?.let {parent.limitMinor.big()} else childLimit
        val onlyChild = parent == null && children.size == 1
        val branchName = if (onlyChild) children.single().name else name(template, parent = parent == null)
        BudgetBranchRow(branchId, branchName,
            if (onlyChild) children.single().icon else parent?.categoryIconSymbolNameSnapshot ?: parent?.let { index.category(it.categoryId)?.iconSymbolName } ?: template.categoryParentIconSymbolNameSnapshot ?: index.category(index.category(template.categoryId)?.parentCategoryId)?.iconSymbolName ?: "questionmark.circle.fill",
            if (onlyChild) children.single().colorHex else parent?.categoryColorHexSnapshot ?: parent?.let { index.category(it.categoryId)?.iconColorHex } ?: template.categoryParentColorHexSnapshot ?: index.category(index.category(template.categoryId)?.parentCategoryId)?.iconColorHex ?: "#8A8A8E",
            code, limit, totalSpent, childLimit, limit?.let {value ->childLimit?.let {value.subtract(it).max(BigInteger.ZERO)}},
            parent?.id ?: children.singleOrNull()?.plan?.id, parent?.id, if (onlyChild) emptyList() else children,
            budgetPace(totalSpent, limit, selectedMonth, referenceDate, zone))
    }.sortedWith { a, b ->
        val ratio = compareProgress(b.spentMinor, b.limitMinor, a.spentMinor, a.limitMinor)
        if (ratio != 0) ratio else Collator.getInstance().compare(a.name, b.name)
    }
    val limit = sumBudgetExact(branches.map {convert(it.limitMinor,it.currencyCode,reportingCurrency.overviewCurrencyCode())})
    val spent = sumBudgetExact(branches.map {convert(it.spentMinor,it.currencyCode,reportingCurrency.overviewCurrencyCode())})
    return BudgetProjection(branches, limit, spent, limit?.let {value ->spent?.let {value.subtract(it).max(BigInteger.ZERO)}})
}

fun TransactionCategoryRecord.localizedBudgetName(language: CategoryNameLanguage): String = when (language) {
    CategoryNameLanguage.VIETNAMESE -> name
    CategoryNameLanguage.ENGLISH -> nameEnglish.nonblank() ?: name
    CategoryNameLanguage.JAPANESE -> nameJapanese.nonblank() ?: name
}

private fun reportedBudgetExpense(record: LedgerTransactionRecord, category: TransactionCategoryRecord?, wallet: LedgerWalletRecord?, adjustmentTitles: Set<String>): Long? {
    record.reportingExpenseMinor?.let { return it }
    if(record.amountMinor==0L) return 0
    if (category?.isBalanceAdjustmentSystemCategory == true || record.categoryId == TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID ||
        record.categoryId == TransactionCategoryRecord.BALANCE_ADJUSTMENT_INCOME_ID || adjustmentTitles.any { it.trim().equals(record.title.trim(), ignoreCase = true) }) return 0
    if (category?.systemKey == "loan_repayment" || record.categoryId == "d872b8af-d28a-5b90-8822-839dfa097b23") return 0
    val primary=record.primaryKind?.let(::listOf) ?: TransactionPrimaryKind.entries
    fun <T> choices(wire:String?,parsed:T?,all:List<T>):List<T?> = if(wire==null) listOf(null) else parsed?.let(::listOf) ?: (listOf(null)+all)
    val subtypes=choices(record.transferSubtypeWireValue,record.transferSubtype,TransactionTransferSubtype.entries)
    val intents=choices(record.debtIntentWireValue,record.debtIntent,TransactionDebtIntent.entries)
    val kinds=if(wallet!=null && wallet.kind==null) listOf(null,WalletKind.CREDIT_CARD) else listOf(wallet?.kind)
    val titles=mapOf(GeneratedTransactionTitle.BALANCE_ADJUSTMENT to adjustmentTitles)
    var seen=false;var result:Long?=null
    // Finite equivalence classes use the existing core expense classifier; no future enum becomes a neutral default.
    for(kind in primary) for(subtype in subtypes) for(intent in intents) for(walletKind in kinds) {
        val candidate=record.copy(primaryKindWireValue=kind.wireValue,transferSubtypeWireValue=subtype?.wireValue,debtIntentWireValue=intent?.wireValue)
        val amount=if(isOverviewExpenseSpending(candidate,walletKind,titles)) record.amountMinor else 0L
        if(!seen) {seen=true;result=amount} else if(result!=amount) return null
    }
    return result
}

private fun currency(value: String?): String = value?.trim()?.uppercase(Locale.ROOT)?.takeIf { it == "JPY" || it == "VND" } ?: "JPY"
private fun sumBudgetExact(values:List<BigInteger?>):BigInteger?=values.fold<BigInteger?,BigInteger?>(BigInteger.ZERO) {sum,value ->sum?.let {subtotal ->value?.let(subtotal::plus)}}
private fun groupingKey(value: String): String = value.trim().replace(Regex("\\s+"), " ").lowercase(Locale.ROOT)
private fun String?.nonblank(): String? = this?.trim()?.takeIf(String::isNotEmpty)
private fun Long.big(): BigInteger = BigInteger.valueOf(this)
private fun Int.big(): BigInteger = toLong().big()
private fun compareProgress(a:BigInteger?,aLimit:BigInteger?,b:BigInteger?,bLimit:BigInteger?):Int {
    val aKnown=a!=null && aLimit!=null;val bKnown=b!=null && bLimit!=null
    if(!aKnown || !bKnown) return aKnown.compareTo(bKnown)
    val aa=if(aLimit!!.signum()>0) a!! else BigInteger.ZERO
    val bb=if(bLimit!!.signum()>0) b!! else BigInteger.ZERO
    return aa.multiply(bLimit.max(BigInteger.ONE)).compareTo(bb.multiply(aLimit.max(BigInteger.ONE)))
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
