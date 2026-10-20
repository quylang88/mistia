package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.math.BigDecimal
import java.math.RoundingMode
import java.text.Collator
import java.text.Normalizer
import java.util.Locale
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId

data class OverviewCategorySpendingSlice(val id:String,val categoryId:String?,val name:String?,val iconSymbolName:String,val colorHex:String,
    val amountMinor:BigInteger,val childSlices:List<OverviewCategorySpendingSlice>) {
    val canDrillDown:Boolean get()=categoryId!=null && childSlices.isNotEmpty()
    val withoutChildren:OverviewCategorySpendingSlice get()=copy(childSlices=emptyList())
}
data class OverviewCategorySpendingMonth(val month:YearMonth,val currencyCode:String,val slices:List<OverviewCategorySpendingSlice>,val totalMinor:BigInteger?)
data class OverviewCategoryChartSlice(val id:String,val name:String?,val iconSymbolName:String,val colorHex:String,val amountMinor:BigInteger,
    val children:List<OverviewCategorySpendingSlice>,val canSelect:Boolean,val isOverflow:Boolean)

fun overviewCategorySpendingMonths(owner:UserId,records:List<LedgerTransactionRecord>,wallets:List<LedgerWalletRecord>,categories:List<TransactionCategoryRecord>,currency:String,
    rates:List<ExchangeRateSnapshot> = emptyList(),language:String="vi",catalog:SystemCategoryCatalog?=null,reference:Instant,zone:ZoneId):List<OverviewCategorySpendingMonth> {
    val current=YearMonth.from(reference.atZone(zone))
    val target=currency.categoryCurrency() ?: "JPY"
    val ownedWallets=wallets.filter {it.ownerUserId==owner.value && it.deletedAt==null}.associateBy {it.id}
    // Metadata retains historical soft-deleted labels, independently of active edit eligibility.
    val ownedCategories=categories.filter {it.ownerUserId==owner.value}.associateBy {it.id}
    val definitions=catalog?.definitions?.associateBy {it.key}.orEmpty()
    val locale=Locale.forLanguageTag(language)
    fun name(category:TransactionCategoryRecord?):String? {
        if(category==null) return null
        val translated=when(locale.language) {"en" -> category.nameEnglish;"ja" -> category.nameJapanese;else -> return category.name}
        return translated?.trim(Char::isCategoryWhitespace)?.takeIf(String::isNotEmpty) ?: definitions[category.systemKey]?.translations?.get(locale.language) ?: category.name
    }
    data class Entry(val category:TransactionCategoryRecord?,val parent:TransactionCategoryRecord?,val amount:BigInteger?)
    val byMonth=mutableMapOf<YearMonth,MutableList<Entry>>()
    for(record in records) {
        if(record.ownerUserId!=owner.value || record.deletedAt!=null || record.isArchived || record.entryStatus!=TransactionEntryStatus.POSTED || record.primaryKind==null ||
            record.settlementRoleWireValue?.startsWith("investment")==true) continue
        val wallet=ownedWallets[record.sourceWalletId]
        val category=ownedCategories[record.categoryId]
        val eligible=record.reportingExpenseMinor?.let {it!=0L} ?: (isOverviewExpenseSpending(record,wallet?.kind) &&
            (record.primaryKind!=TransactionPrimaryKind.TRANSFER || category!=null))
        if(!eligible) continue
        val month=runCatching {YearMonth.from(Instant.parse(record.occurredAt).atZone(zone))}.getOrNull() ?: continue
        val parent=ownedCategories[category?.parentCategoryId]?.takeIf {it.id!=category?.id}
        val source=record.sourceCurrencyCode?.takeIf(String::isNotBlank) ?: wallet?.currencyCode ?: "JPY"
        val amount=categoryConvertedMinor(record.reportingExpenseMinor ?: record.amountMinor,source,target,rates)
        byMonth.getOrPut(month) {mutableListOf()}+=Entry(category,parent,amount)
    }
    val collator=Collator.getInstance(locale).apply {strength=Collator.SECONDARY;decomposition=Collator.CANONICAL_DECOMPOSITION}
    val sort=Comparator<OverviewCategorySpendingSlice> {a,b ->
        b.amountMinor.compareTo(a.amountMinor).takeIf {it!=0} ?: collator.compare(a.name.orEmpty(),b.name.orEmpty()).takeIf {it!=0} ?: a.id.compareTo(b.id)
    }
    fun slice(category:TransactionCategoryRecord?,amount:BigInteger,children:List<OverviewCategorySpendingSlice>)=OverviewCategorySpendingSlice(
        category?.let {"category-${it.id.lowercase(Locale.ROOT)}"} ?: "uncategorized-expense",category?.id,name(category),
        category?.iconSymbolName?.takeIf(String::isNotBlank) ?: "tray.full.fill",category?.iconColorHex?.takeIf(String::isNotBlank) ?: "#8A8A8E",amount,children)
    fun total(entries:List<Entry>)=entries.fold(BigInteger.ZERO) {sum,entry -> sum+checkNotNull(entry.amount)}
    val pages=mutableListOf<OverviewCategorySpendingMonth>()
    var month=(byMonth.keys.minOrNull() ?: current).coerceAtMost(current)
    while(month<=current) {
        val entries=byMonth[month].orEmpty()
        if(entries.any {it.amount==null}) pages+=OverviewCategorySpendingMonth(month,target,emptyList(),null)
        else {
            val slices=entries.groupBy {categoryNameKey(name(it.parent) ?: name(it.category))}.values.map {branch ->
                val template=branch.first()
                val children=branch.groupBy {categoryNameKey(name(it.category))}.values.map {child ->slice(child.first().category,total(child),emptyList())}.sortedWith(sort)
                slice(template.parent ?: template.category,total(branch),children)
            }.sortedWith(sort)
            pages+=OverviewCategorySpendingMonth(month,target,slices,total(entries))
        }
        month=month.plusMonths(1)
    }
    return pages
}

fun overviewCategoryChartSlices(source:List<OverviewCategorySpendingSlice>,overflowId:String,allowSelection:Boolean=true):List<OverviewCategoryChartSlice> {
    val positive=source.filter {it.amountMinor.signum()>0}
    val result=positive.take(5).map {OverviewCategoryChartSlice(it.id,it.name,it.iconSymbolName,it.colorHex,it.amountMinor,it.childSlices,allowSelection && it.canDrillDown,false)}.toMutableList()
    val overflow=positive.drop(5)
    if(overflow.isNotEmpty()) result+=OverviewCategoryChartSlice("other-$overflowId",null,"ellipsis.circle.fill","#7C85A3",overflow.fold(BigInteger.ZERO) {sum,slice ->sum+slice.amountMinor},overflow,allowSelection,true)
    return result
}
fun overviewCategoryPercentage(amount:BigInteger,total:BigInteger):Int = if(amount.signum()<=0 || total.signum()<=0) 0 else
    BigDecimal(amount).multiply(BigDecimal("100")).divide(BigDecimal(total),0,RoundingMode.HALF_UP).min(BigDecimal("100")).intValueExact()

private fun categoryNameKey(name:String?):String {
    val compact=buildString {
        var gap=false
        for(character in name.orEmpty()) {
            if(character.isCategoryWhitespace()) {if(isNotEmpty()) gap=true}
            else {if(gap) append(' ');append(character);gap=false}
        }
    }
    return Normalizer.normalize(compact.lowercase(Locale.ROOT),Normalizer.Form.NFC)
}
private fun String.categoryCurrency():String?=trim().uppercase(Locale.ROOT).takeIf {it.matches(Regex("[A-Z]{3}"))}
private fun categoryConvertedMinor(amount:Long,source:String,target:String,rates:List<ExchangeRateSnapshot>):BigInteger? {
    if(amount==0L) return BigInteger.ZERO
    val from=source.categoryCurrency() ?: return null
    if(from==target) return BigInteger.valueOf(amount)
    if(from !in CurrencyPreferences.supportedCurrencyCodes || target !in CurrencyPreferences.supportedCurrencyCodes || matchingExchangeRateSnapshot(from,target,rates)==null) return null
    return planningMoneyMinorExact(amount,from,target,rates)
}

private fun Char.isCategoryWhitespace():Boolean=isWhitespace() || this=='\u0085'
