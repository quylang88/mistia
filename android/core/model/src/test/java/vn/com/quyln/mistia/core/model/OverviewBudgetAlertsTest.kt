package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.util.Locale
import org.junit.Assert.*
import org.junit.Test

class OverviewBudgetAlertsTest {
    private fun row(id:String,spent:String="1200",limit:String="1000",health:BudgetHealth?=BudgetHealth.EXCEEDED,name:String=id)=BudgetBranchRow(
        id,name,"fork.knife","#F45C7E","JPY",BigInteger(limit),BigInteger(spent),BigInteger.ZERO,BigInteger.ZERO,id,null,emptyList(),
        BudgetPace(health,BigInteger(spent),BigInteger.ZERO,10,false,false))
    private fun projection(vararg rows:BudgetBranchRow)=BudgetProjection(rows.toList(),BigInteger.valueOf(1000),BigInteger.valueOf(1200),BigInteger.ZERO)
    private fun ids(rows:List<BudgetBranchRow>?)=rows?.map {it.id}
    @Test fun `stable budgets are hidden while alarms retain exact original branch money`() {
        val stable=row("stable",spent="10",health=BudgetHealth.STABLE);val alarm=row("alarm")
        assertEquals(listOf(alarm),overviewBudgetAlerts(projection(stable,alarm)))
        assertTrue(overviewBudgetAlerts(projection(stable))!!.isEmpty())
        assertEquals(listOf("alarm","stable"),ids(overviewBudgetAlerts(projection(stable,alarm),includesStable=true)))
    }
    @Test fun `exceeded ranks before caution then exact descending progress and defaults to three`() {
        val caution=row("caution",spent="999",health=BudgetHealth.CAUTION)
        val a=row("a",spent="1000");val b=row("b",spent="2000");val c=row("c",spent="1500")
        assertEquals(listOf("b","c","a"),ids(overviewBudgetAlerts(projection(caution,a,c,b))))
        assertEquals(listOf("b","c","a","caution"),ids(overviewBudgetAlerts(projection(caution,a,c,b),maximumCount=null)))
    }
    @Test fun `ratio sort never collapses distinct aggregates above Double precision`() {
        val low=row("alphabetically-first","9007199254740992","9007199254740992")
        val high=row("last","9007199254740993","9007199254740992")
        assertEquals(listOf(high,low),overviewBudgetAlerts(projection(low,high)))
        val max=BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO
        val exact=row("max",max.toString(),"9223372036854775807")
        assertEquals(max,overviewBudgetAlerts(projection(exact))!!.single().spentMinor)
    }
    @Test fun `unknown branch remains visible and cannot be discarded as stable or an empty read`() {
        val unknown=row("unknown",health=null).copy(spentMinor=null)
        val exceeded=row("exceeded")
        assertEquals(listOf(unknown,exceeded),overviewBudgetAlerts(projection(exceeded,unknown)))
        assertNull(overviewBudgetAlerts(BudgetProjection(emptyList(),null,null,null)))
        assertTrue(overviewBudgetAlerts(BudgetProjection(emptyList(),BigInteger.ZERO,BigInteger.ZERO,BigInteger.ZERO))!!.isEmpty())
    }
    @Test fun `branch alerts do not depend on summary currency conversion availability`() {
        val readable=row("vnd").copy(currencyCode="VND")
        assertEquals(listOf(readable),overviewBudgetAlerts(BudgetProjection(listOf(readable),null,null,null)))
    }
    @Test fun `names break equal ratios with the requested locale and count zero stays empty`() {
        val z=row("z",name="Zulu");val a=row("a",name="Alpha")
        assertEquals(listOf(a,z),overviewBudgetAlerts(projection(z,a),locale=Locale.ENGLISH))
        assertTrue(overviewBudgetAlerts(projection(z,a),maximumCount=0)!!.isEmpty())
        assertTrue(overviewBudgetAlerts(projection(z,a),maximumCount=-1)!!.isEmpty())
    }
    @Test fun `signed stable ratios and zero limits follow Swift progress definition`() {
        val negative=row("negative",spent="-1",health=BudgetHealth.STABLE)
        val zero=row("zero",spent="99",limit="0",health=BudgetHealth.STABLE)
        assertEquals(listOf(zero,negative),overviewBudgetAlerts(projection(negative,zero),includesStable=true))
    }
    @Test fun `one parent branch yields one alert regardless of its children allocation`() {
        val parent=row("parent").copy(parentBudgetId="parent-template",allocatedMinor=BigInteger.valueOf(500))
        assertEquals(listOf(parent),overviewBudgetAlerts(projection(parent)))
    }
}
