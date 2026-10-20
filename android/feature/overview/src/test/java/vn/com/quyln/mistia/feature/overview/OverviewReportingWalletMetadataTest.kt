package vn.com.quyln.mistia.feature.overview

import java.math.BigInteger
import java.time.*
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class OverviewReportingWalletMetadataTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val time="2026-10-20T12:00:00Z"
    private val reference=Instant.parse(time)
    private val zone=ZoneOffset.UTC
    private val day=reference.atZone(zone).toLocalDate()
    private val rates=listOf(ExchangeRateSnapshot("JPY","VND","165","test",0,null))
    private fun raw(entity:CloudEntity,fields:JsonObject):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(entity.table,id,owner.value,JsonObject(buildJsonObject {
            put("id",id);put("user_id",owner.value);put("is_archived",false);put("created_at",time);put("updated_at",time);put("occurred_at",time)
        }+fields),time,null,0)
    }
    private fun wallet(code:String="VND",kind:String="cash")=raw(CloudEntity.LEDGER_WALLET,buildJsonObject {
        put("name","Reporting metadata");put("kind_raw_value",kind);put("currency_code",code);put("opening_balance_minor","broken")
    })
    private fun row(wallet:CloudRecord,amount:Long=165,kind:String="expense",title:String="Metadata expense")=raw(CloudEntity.LEDGER_TRANSACTION,buildJsonObject {
        put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("title",title);put("amount_minor",amount);put("source_wallet_id",wallet.id);put("source_currency_code",JsonNull)
    })
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    private fun inputs(wallet:CloudRecord,rows:List<CloudRecord> = listOf(row(wallet)))=overviewFinancialInputs(owner,rows,listOf(wallet))
    private fun OverviewFinancialInputs.month()=overviewMonthlyCashflow(owner,records,wallets,"JPY",rates,reference=reference,zone=zone).single()
    private fun OverviewFinancialInputs.week()=overviewWeeklySpending(owner,records,wallets,"JPY",rates,reference=reference,zone=zone).single()
    private fun OverviewFinancialInputs.category()=overviewCategorySpendingMonths(owner,records,wallets,emptyList(),"JPY",rates,reference=reference,zone=zone).single()
    private fun OverviewFinancialInputs.details()=overviewExpenseDay(owner,records,wallets,day,"JPY",rates,zone=zone)
    private fun minor(expected:Long,actual:BigInteger?)=assertEquals(BigInteger.valueOf(expected),actual)
    @Test fun `monthly both directions use wallet currency without reading unused opening`() {
        val wallet=wallet();val rows=listOf(row(wallet),row(wallet,330,"income"))
        for(value in listOf(JsonPrimitive("broken"),JsonNull,JsonPrimitive(1.5),JsonPrimitive("10"))) {
            val changed=wallet.with("opening_balance_minor",value);val month=inputs(changed,rows).month()
            minor(1,month.expenseMinor);minor(2,month.incomeMinor)
            assertNull(overviewAssetBalance(owner,rows,listOf(changed),"JPY",rates))
        }
    }
    @Test fun `weekly exact conversion retains metadata with an unreadable cash opening`() {
        minor(1,inputs(wallet()).week().points.single {it.date==day}.amountMinor)
    }
    @Test fun `category exact conversion retains metadata with an unreadable cash opening`() {
        val category=inputs(wallet()).category();minor(1,category.totalMinor);minor(1,category.slices.single().amountMinor)
    }
    @Test fun `day total converts while row keeps original VND money without opening dependency`() {
        val details=inputs(wallet()).details();minor(1,details.totalMinor);assertEquals(Money(165,"VND"),details.rows.single().money)
    }
    @Test fun `unreadable existing currency is unavailable rather than a legacy JPY fallback`() {
        val financial=inputs(wallet("???"));assertNull(financial.month().expenseMinor);minor(0,financial.month().incomeMinor)
        assertNull(financial.week().totalMinor);assertNull(financial.category().totalMinor)
        assertNull(financial.details().totalMinor);assertNull(financial.details().rows.single().money)
    }
    @Test fun `historical archived and credit kind metadata survive unreadable unused opening`() {
        minor(1,inputs(wallet().with("is_archived",JsonPrimitive(true))).month().expenseMinor)
        val credit=wallet("JPY","creditCard");val financial=inputs(credit,listOf(row(credit,3,title="Card payment")))
        minor(3,financial.month().expenseMinor);minor(3,financial.week().totalMinor);minor(3,financial.details().totalMinor)
    }
    @Test fun `foreign deleted and mismatched metadata cannot supply currency or poison legacy records`() {
        val wallet=wallet();val rows=listOf(row(wallet))
        for(ineligible in listOf(wallet.copy(ownerUserId=other),wallet.with("user_id",JsonPrimitive(other)),wallet.with("id",JsonPrimitive(UUID.randomUUID().toString())),
            wallet.copy(deletedAt=time),wallet.with("deleted_at",JsonPrimitive(time)))) minor(165,inputs(ineligible,rows).month().expenseMinor)
        minor(165,inputs(wallet,listOf(rows.single().with("source_currency_code",JsonPrimitive("JPY")))).month().expenseMinor)
    }
}
