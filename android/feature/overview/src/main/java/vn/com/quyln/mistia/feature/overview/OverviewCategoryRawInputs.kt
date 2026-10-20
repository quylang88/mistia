package vn.com.quyln.mistia.feature.overview

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

/** Category-specific intake, independent of unused cash/reporting directions and creation clocks. */
internal fun overviewRawCategorySpendingMonths(owner:UserId,records:List<CloudRecord>,wallets:List<CloudRecord>,categories:List<TransactionCategoryRecord>,currency:String,
    rates:List<ExchangeRateSnapshot> = emptyList(),language:String="vi",catalog:SystemCategoryCatalog?=null,reference:Instant,zone:ZoneId):List<OverviewCategorySpendingMonth> {
    val current=YearMonth.from(reference.atZone(zone))
    val categoryIds=categories.filter {it.ownerUserId==owner.value}.map {it.id}.toSet()
    val metadata=wallets.filter {it.overviewRawIdentity(owner,CloudEntity.LEDGER_WALLET) && it.overviewRawDeleted()!=true}.associateBy {overviewRawUuid(it.id)}
    val effects=records.mapNotNull {raw ->
        if(!raw.overviewRawIdentity(owner,CloudEntity.LEDGER_TRANSACTION)) return@mapNotNull null
        val p=raw.payload
        val deleted=raw.overviewRawDeleted();val archived=p.overviewRawArchived()
        val status=p.overviewRawString("entry_status_raw_value")?.let(TransactionEntryStatus::fromWireValue)
        if(deleted==true || archived==true || status==TransactionEntryStatus.DRAFT || p.overviewRawString("settlement_role_raw_value")?.startsWith("investment")==true) return@mapNotNull null
        val occurred=p.overviewRawString("occurred_at")?.let {runCatching {Instant.parse(it)}.getOrNull()}
        val month=occurred?.let {runCatching {YearMonth.from(it.atZone(zone))}.getOrNull()}
        if(month!=null && month>current) return@mapNotNull null
        val source=p.overviewRawReference("source_wallet_id")
        val wallet=metadata[source.id]
        val kind=wallet?.payload?.overviewRawString("kind_raw_value")?.let(WalletKind::fromWireValue)
        val kindKnown=source.readable && (wallet==null || (wallet.overviewRawDeleted()==false && kind!=null))
        val category=p.overviewRawReference("category_id")
        val eligibility=categoryEligibility(raw,kind,kindKnown,categoryIds)
        if(eligibility==false) return@mapNotNull null
        val original=p.overviewRawLong("amount_minor")
        val amount=if(p.present("reporting_expense_minor")) p.overviewRawLong("reporting_expense_minor") else original
        val roleKnown=!p.present("settlement_role_raw_value") || p.overviewRawString("settlement_role_raw_value")!=null
        val eligibilityKnown=eligibility==true && roleKnown && deleted==false && archived==false && status==TransactionEntryStatus.POSTED
        val code=when {
            p.present("source_currency_code") -> p.overviewRawString("source_currency_code")?.overviewReportingCode()
            !source.readable -> null
            wallet==null -> "JPY"
            wallet.overviewRawDeleted()==null -> null
            else -> wallet.payload.overviewRawString("currency_code")?.overviewReportingCode()
        }
        OverviewCategoryExpenseEffect(occurred,category.id,code,if(eligibilityKnown || amount==0L) amount else null,category.readable)
    }
    return overviewCategorySpendingEffects(owner,effects,categories,currency,rates,language,catalog,reference,zone)
}

private fun categoryEligibility(raw:CloudRecord,kind:WalletKind?,kindKnown:Boolean,categoryIds:Set<String>):Boolean? {
    val p=raw.payload
    if(p.present("reporting_expense_minor")) return p.overviewRawLong("reporting_expense_minor")?.let {it!=0L}
    val primary=p.overviewRawString("primary_kind_raw_value")?.let(TransactionPrimaryKind::fromWireValue)
    val category=p.overviewRawReference("category_id")
    var result:Boolean?=null;var seen=false
    for(value in primary?.let(::listOf) ?: TransactionPrimaryKind.entries) {
        for((candidate,walletKind) in overviewClassificationCandidates(raw,value,kind,kindKnown,emptyMap())) {
            val available=if(category.readable || candidate.categoryId==null || categoryIds.isEmpty()) listOf(candidate.categoryId in categoryIds) else listOf(false,true)
            for(hasCategory in available) {
                val next=isOverviewCategorySpending(candidate,walletKind,hasCategory)
                if(!seen) {seen=true;result=next} else if(result!=next) return null
            }
        }
    }
    return result
}
