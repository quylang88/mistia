package vn.com.quyln.mistia.feature.planning

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

/** Strict persistence failures remain unavailable read data, never an absent/zero template. */
internal fun projectRawBudgetPlans(owner:UserId,rawPlans:List<CloudRecord>?,categories:List<TransactionCategoryRecord>,
    transactions:List<LedgerTransactionRecord>,wallets:List<LedgerWalletRecord>,month:YearMonth,reference:Instant,zone:ZoneId,
    rates:List<ExchangeRateSnapshot>,language:CategoryNameLanguage,adjustmentTitles:Set<String>,currency:String,deletedCategoryName:String="",
):BudgetProjection {
    fun unavailable()=BudgetProjection(emptyList(),null,null,null)
    if(rawPlans==null) return unavailable()
    val plans=mutableListOf<BudgetPlanRecord>()
    val seen=mutableSetOf<String>()
    val index=CategoryIdentityIndex(owner,categories)
    for(raw in rawPlans) {
        if(!raw.hasBudgetReadIdentity(owner) || !seen.add(rawBudgetUuid(raw.id)!!)) continue
        if(raw.deletedAt!=null) continue
        val p=raw.payload
        val archived=(p["is_archived"] as? JsonPrimitive)?.takeUnless {it.isString}?.booleanOrNull
        val deleted=p["deleted_at"]
        val knownDeleted=p.budgetRawString("deleted_at")?.let {runCatching {Instant.parse(it)}.isSuccess}==true
        if(archived==true || knownDeleted) continue
        val anchor=p.budgetRawString("month_anchor")?.let {runCatching {budgetMonth(it,zone)}.getOrNull()}
        // A proved future template is irrelevant even when another field is unreadable.
        if(anchor!=null && anchor>month) continue
        if(archived!=false || (deleted!=null && deleted!=JsonNull) || anchor==null) return unavailable()
        val plan=runCatching {BudgetPlanRecord.fromCloudRecord(raw)}.getOrNull() ?: return unavailable()
        if(plan.limitMinor<=0 || plan.logicalAllocation(index).branchCategoryId==null) return unavailable()
        plans+=plan
    }
    return projectBudgets(owner,plans,categories,transactions,wallets,month,reference,zone,rates,language,adjustmentTitles,currency,deletedCategoryName)
}

/** Reload the exact strict read row; a delayed typed stream must never turn Edit into Create. */
internal fun storedBudgetReadPlan(owner:UserId,id:String,rows:List<CloudRecord>?):BudgetPlanRecord? =
    rows.orEmpty().firstOrNull {it.hasBudgetReadIdentity(owner) && rawBudgetUuid(it.id)==rawBudgetUuid(id)}?.let {raw ->
        runCatching {BudgetPlanRecord.fromCloudRecord(raw)}.getOrNull()?.takeIf {
            raw.deletedAt==null && !it.isArchived && it.deletedAt==null && it.limitMinor>0
        }
    }

private fun CloudRecord.hasBudgetReadIdentity(owner:UserId):Boolean {
    val expectedOwner=rawBudgetUuid(owner.value) ?: return false
    val expectedId=rawBudgetUuid(id) ?: return false
    return entity==CloudEntity.BUDGET_PLAN.table && ownerUserId==owner.value &&
        rawBudgetUuid(payload.budgetRawString("id"))==expectedId && rawBudgetUuid(payload.budgetRawString("user_id"))==expectedOwner
}

private fun JsonObject.budgetRawString(key:String)=(get(key) as? JsonPrimitive)?.takeIf {it.isString}?.contentOrNull
private val budgetRawUuidPattern=Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
private fun rawBudgetUuid(value:String?):String?=value?.trim()?.takeIf {budgetRawUuidPattern.matches(it)}?.let {text ->
    runCatching {UUID.fromString(text).toString().takeIf {it==text.lowercase(Locale.ROOT)}}.getOrNull()
}
