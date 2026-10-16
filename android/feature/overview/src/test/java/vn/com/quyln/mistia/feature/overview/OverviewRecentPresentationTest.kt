package vn.com.quyln.mistia.feature.overview

import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class OverviewRecentPresentationTest {
    private val owner="11111111-1111-1111-1111-111111111111"
    private val id="22222222-2222-2222-2222-222222222222"
    private val categoryId="33333333-3333-3333-3333-333333333333"
    private val time=Instant.parse("2026-10-16T12:00:00Z")
    private fun transaction(kind:String="transfer",subtype:String?="debt",intent:String?="borrow",source:String?=id,destination:String?=null,category:String?=null):LedgerTransactionRecord {
        val payload=buildJsonObject {
            put("id",id);put("user_id",owner);put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted")
            put("title","Exact");put("amount_minor",9007199254740993L);put("source_currency_code","VND")
            put("occurred_at",time.toString());put("created_at",time.toString());put("updated_at",time.toString())
            put("transfer_subtype_raw_value",subtype?.let(::JsonPrimitive) ?: JsonNull)
            put("debt_intent_raw_value",intent?.let(::JsonPrimitive) ?: JsonNull)
            put("source_wallet_id",source?.let(::JsonPrimitive) ?: JsonNull);put("destination_wallet_id",destination?.let(::JsonPrimitive) ?: JsonNull)
            put("category_id",category?.let(::JsonPrimitive) ?: JsonNull)
        }
        return LedgerTransactionRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner,payload,null,null,0))
    }
    @Test fun `income expense and family transfers have Swift directions without changing original minor amount`() {
        val cases=listOf(transaction("income") to OverviewCashflow.INCOME,transaction("expense") to OverviewCashflow.EXPENSE,
            transaction(subtype="internalTransfer") to OverviewCashflow.NEUTRAL,
            transaction(subtype="familyTransfer",destination=null) to OverviewCashflow.INCOME,
            transaction(subtype="familyTransfer",destination=id) to OverviewCashflow.EXPENSE)
        for((record,style) in cases) {val before=record.toPayload();assertEquals(style,overviewCashflow(record));assertEquals(before,record.toPayload());assertEquals(9007199254740993L,record.amountMinor)}
    }
    @Test fun `debt intent includes paid for expense but not adjustments or installment categories`() {
        for(intent in listOf("borrow","collect")) assertEquals(OverviewCashflow.INCOME,overviewCashflow(transaction(intent=intent)))
        for(intent in listOf("lend","repay")) assertEquals(OverviewCashflow.EXPENSE,overviewCashflow(transaction(intent=intent)))
        assertEquals(OverviewCashflow.NEUTRAL,overviewCashflow(transaction(source=null)))
        assertEquals(OverviewCashflow.EXPENSE,overviewCashflow(transaction(source=null,category=categoryId)))
        for(category in listOf(TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID,TransactionCategoryRecord.BALANCE_ADJUSTMENT_INCOME_ID,"d872b8af-d28a-5b90-8822-839dfa097b23")) {
            assertEquals(OverviewCashflow.NEUTRAL,overviewCashflow(transaction(source=null,category=category)))
        }
        assertEquals(OverviewCashflow.NEUTRAL,overviewCashflow(transaction(intent=null)))
    }
    @Test fun `relative minutes hours same day and calendar days match Swift thresholds`() {
        val zone=ZoneId.of("Asia/Tokyo")
        for((seconds,expected) in listOf(0L to 1L,59L to 1L,60L to 1L,119L to 1L,120L to 2L,3599L to 59L,-120L to 1L))
            assertEquals(OverviewRelativeTime.Minutes(expected),overviewRelativeTime(time.minusSeconds(seconds),time,zone))
        assertEquals(OverviewRelativeTime.Hours(1),overviewRelativeTime(time.minusSeconds(3600),time,zone))
        assertEquals(OverviewRelativeTime.Hours(5),overviewRelativeTime(time.minusSeconds(21599),time,zone))
        assertEquals(OverviewRelativeTime.Today,overviewRelativeTime(time.minusSeconds(21600),time,zone))
        assertEquals(OverviewRelativeTime.Yesterday,overviewRelativeTime(time.minusSeconds(86400),time,zone))
        assertEquals(OverviewRelativeTime.TwoDaysAgo,overviewRelativeTime(time.minusSeconds(172800),time,zone))
        assertEquals(OverviewRelativeTime.Date(java.time.LocalDate.of(2026,10,13)),overviewRelativeTime(time.minusSeconds(259200),time,zone))
    }
    @Test fun `Japan and Vietnam midnight boundaries use calendar rather than elapsed twenty four hours`() {
        val reference=Instant.parse("2026-10-16T15:30:00Z");val date=Instant.parse("2026-10-16T14:45:00Z")
        assertEquals(OverviewRelativeTime.Yesterday,overviewRelativeTime(date,reference,ZoneId.of("Asia/Tokyo")))
        assertEquals(OverviewRelativeTime.Minutes(45),overviewRelativeTime(date,reference,ZoneId.of("Asia/Ho_Chi_Minh")))
        val future=reference.plusSeconds(86400)
        assertEquals(OverviewRelativeTime.Date(java.time.LocalDate.of(2026,10,18)),overviewRelativeTime(future,reference,ZoneId.of("Asia/Tokyo")))
    }
    @Test fun `icon uses only owned matching category otherwise transaction kind`() {
        val category=CategoryDraft(id=categoryId,name="Food",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT,iconSymbolName="mistia.category.food")
            .toMutation(UserId(owner),null,null,id,time.toString()).record
        val record=transaction("expense",category=categoryId)
        assertEquals(category.iconSymbolName,overviewRecentIcon(record,category))
        assertEquals("mistia.flow.expense",overviewRecentIcon(record,category.copy(ownerUserId=id)))
        assertEquals("mistia.flow.expense",overviewRecentIcon(record,category.copy(id=id)))
        assertEquals("mistia.flow.income",overviewRecentIcon(transaction("income"),null))
        assertEquals("mistia.flow.transfer",overviewRecentIcon(transaction(),null))
    }
}
