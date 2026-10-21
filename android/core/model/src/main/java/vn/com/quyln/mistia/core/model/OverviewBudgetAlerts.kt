package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.text.Collator
import java.util.Locale

/** Watchlist selection preserves branch currency money and exact progress ordering. */
fun overviewBudgetAlerts(projection:BudgetProjection,maximumCount:Int?=3,includesStable:Boolean=false,locale:Locale=Locale.getDefault()):List<BudgetBranchRow>? {
    if(projection.branches.isEmpty() && (projection.totalLimitMinor==null || projection.totalSpentMinor==null)) return null
    fun rank(row:BudgetBranchRow)=if(row.spentMinor==null || row.limitMinor==null || row.currencyCode==null) 3 else when(row.pace.health) {
        null -> 3
        BudgetHealth.EXCEEDED -> 2
        BudgetHealth.CAUTION -> 1
        BudgetHealth.STABLE -> 0
    }
    fun progress(row:BudgetBranchRow):Pair<BigInteger,BigInteger> =
        if(row.limitMinor!=null && row.limitMinor.signum()>0 && row.spentMinor!=null) row.spentMinor to row.limitMinor
        else BigInteger.ZERO to BigInteger.ONE
    val collator=Collator.getInstance(locale).apply {strength=Collator.SECONDARY;decomposition=Collator.CANONICAL_DECOMPOSITION}
    val rows=projection.branches.filter {includesStable || rank(it)!=0}.sortedWith {a,b ->
        rank(b).compareTo(rank(a)).takeIf {it!=0} ?: run {
            val (an,ad)=progress(a);val (bn,bd)=progress(b)
            (bn*ad).compareTo(an*bd).takeIf {it!=0} ?: collator.compare(a.name,b.name)
        }
    }
    return maximumCount?.let {rows.take(it.coerceAtLeast(0))} ?: rows
}
