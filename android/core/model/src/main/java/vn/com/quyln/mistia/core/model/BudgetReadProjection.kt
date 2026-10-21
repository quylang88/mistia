package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import kotlinx.serialization.json.*

fun projectRawBudgetReadSnapshot(owner:UserId,snapshot:BudgetReadSnapshot?,month:YearMonth,reference:Instant,zone:ZoneId,
    rates:List<ExchangeRateSnapshot>,language:CategoryNameLanguage,adjustmentTitles:Set<String>,currency:String,deletedCategoryName:String="",
):BudgetProjection {
    fun unavailable()=BudgetProjection(emptyList(),null,null,null)
    if(snapshot==null || snapshot.owner!=owner) return unavailable()
    return runCatching {
        val metadata=budgetCategoryReadMetadata(owner,snapshot.records(CloudEntity.TRANSACTION_CATEGORY),language)
        val categories=metadata.records;val index=CategoryIdentityIndex(owner,categories)
        val plans=snapshot.records(CloudEntity.BUDGET_PLAN)
        val current=plans.mapNotNull {raw ->
            if(!raw.financeRawIdentity(owner,CloudEntity.BUDGET_PLAN,requireBodyIdentity=true)) null
            else runCatching {BudgetPlanRecord.fromCloudRecord(raw)}.getOrNull()?.takeIf {
                !it.isArchived && it.deletedAt==null && budgetMonth(it.monthAnchor,zone)<=month
            }
        }
        val references=current.flatMap {listOfNotNull(it.categoryId,it.categoryIdSnapshot,it.categoryParentIdSnapshot)}.toSet()
        if((current.isNotEmpty() && metadata.allAliasesUncertain) || references.any {it in metadata.uncertainAliasRefs}) return unavailable()
        for(plan in current) {
            val category=index.category(plan.categoryId)
            if(category!=null && ((plan.categoryIsParentSnapshot==null && category.id in metadata.unknownRoles) ||
                    (plan.categoryIsParentSnapshot!=true && plan.categoryParentIdSnapshot==null && category.id in metadata.unknownParents))) return unavailable()
        }
        val effects=budgetRawExpenseEffects(owner,snapshot.records(CloudEntity.LEDGER_TRANSACTION),snapshot.records(CloudEntity.LEDGER_WALLET),metadata,index,adjustmentTitles)
        projectRawBudgetPlans(owner,plans,categories,emptyList(),emptyList(),month,reference,zone,rates,language,adjustmentTitles,currency,deletedCategoryName,effects)
    }.getOrElse {unavailable()}
}

private fun budgetRawExpenseEffects(owner:UserId,rows:List<CloudRecord>,walletRows:List<CloudRecord>,metadata:BudgetCategoryReadMetadata,index:CategoryIdentityIndex,adjustmentTitles:Set<String>):List<BudgetExpenseEffect> {
    val wallets=walletRows.filter {it.financeRawIdentity(owner,CloudEntity.LEDGER_WALLET,requireBodyIdentity=true) && it.financeRawDeleted(requireTimestamp=true)!=true}.associateBy {financeRawUuid(it.id)}
    val seen=mutableSetOf<String>()
    return rows.mapNotNull {raw ->
        if(!raw.financeRawIdentity(owner,CloudEntity.LEDGER_TRANSACTION,requireBodyIdentity=true) || !seen.add(financeRawUuid(raw.id)!!)) return@mapNotNull null
        val p=raw.payload;val deleted=raw.financeRawDeleted(requireTimestamp=true);val archived=p.financeRawArchived()
        val status=p.financeRawString("entry_status_raw_value")?.let(TransactionEntryStatus::fromWireValue)
        if(deleted==true || archived==true || status==TransactionEntryStatus.DRAFT) return@mapNotNull null
        val categoryRef=p.financeRawReference("category_id");val category=index.category(categoryRef.id)
        val categoryRaw=metadata.rawById[category?.id ?: categoryRef.id]
        val parentRef=categoryRaw?.payload?.financeRawReference("parent_category_id") ?: FinanceRawReference(null,categoryRef.id==null)
        val parent=index.category(category?.parentCategoryId)
        val unknownCategory=!categoryRef.readable || (categoryRef.id!=null && (category==null || category.id in metadata.unknownNames))
        val unknownBranch=unknownCategory || !parentRef.readable || (parentRef.id!=null && (parent==null || parent.id in metadata.unknownNames))
        val branchIdentityKnown=categoryRef.readable && (categoryRef.id==null || (parentRef.readable && (category!=null || (categoryRaw!=null && parentRef.id==null))))
        val source=p.financeRawReference("source_wallet_id");val wallet=wallets[source.id]
        val kind=wallet?.payload?.financeRawString("kind_raw_value")?.let(WalletKind::fromWireValue)
        val kindKnown=source.readable && ((source.id==null && wallet==null) || (wallet!=null && wallet.financeRawDeleted(requireTimestamp=true)==false && kind!=null))
        val code=when {
            p.financePresent("source_currency_code") -> p.financeRawString("source_currency_code")?.financeReportingCode()
            !source.readable -> null
            source.id==null -> "JPY"
            wallet==null || wallet.financeRawDeleted(requireTimestamp=true)!=false -> null
            else -> wallet.payload.financeRawString("currency_code")?.financeReportingCode()
        }
        val expense=rawBudgetExpense(raw,categoryRaw,category,kind,kindKnown,adjustmentTitles)
        val eligible=deleted==false && archived==false && status==TransactionEntryStatus.POSTED
        BudgetExpenseEffect(financeRawUuid(raw.id)!!,owner.value,categoryRef.id,
            p.financeRawString("occurred_at")?.let {runCatching {Instant.parse(it)}.getOrNull()},code,
            if(eligible || expense==0L) expense else null,unknownCategory,unknownBranch,branchIdentityKnown)
    }
}

private fun rawBudgetExpense(raw:CloudRecord,categoryRaw:CloudRecord?,category:TransactionCategoryRecord?,kind:WalletKind?,kindKnown:Boolean,titles:Set<String>):Long? {
    val p=raw.payload
    val override=p.financePresent("reporting_expense_minor")
    val original=p.financeRawLong("amount_minor");val expense=p.financeRawLong("reporting_expense_minor")
    if(override) return expense
    if(original==0L) return 0
    val categoryRef=p.financeRawReference("category_id")
    val keyKnown=categoryRef.readable && (categoryRef.id==null || (categoryRaw!=null &&
        (!categoryRaw.payload.financePresent("system_key") || categoryRaw.payload.financeRawString("system_key")!=null)))
    val keys=when {
        category?.isBalanceAdjustmentSystemCategory==true -> listOf(TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_KEY)
        keyKnown -> listOf(categoryRaw?.payload?.financeRawString("system_key"))
        else -> listOf(null,"loan_repayment",TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_KEY,TransactionCategoryRecord.BALANCE_ADJUSTMENT_INCOME_KEY)
    }
    val primary=p.financeRawString("primary_kind_raw_value")?.let(TransactionPrimaryKind::fromWireValue)?.let(::listOf) ?: TransactionPrimaryKind.entries
    var seen=false;var result:Long?=null
    for(value in primary) for((candidate,walletKind) in financeClassificationCandidates(raw,value,kind,kindKnown,mapOf(GeneratedTransactionTitle.BALANCE_ADJUSTMENT to titles))) for(key in keys) {
        val amount=when(budgetExpenseSource(candidate,key,walletKind,titles)) {
            OverviewReportingSource.NONE -> 0L
            OverviewReportingSource.ORIGINAL -> original
            OverviewReportingSource.EXPENSE_OVERRIDE -> expense
            OverviewReportingSource.INCOME_OVERRIDE -> null
        }
        if(!seen){seen=true;result=amount} else if(result!=amount) return null
    }
    return result
}
