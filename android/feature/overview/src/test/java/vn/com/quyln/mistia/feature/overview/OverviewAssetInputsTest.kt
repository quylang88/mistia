package vn.com.quyln.mistia.feature.overview

import java.math.BigInteger
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class OverviewAssetInputsTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val time="2026-10-20T00:00:00Z"
    private fun raw(entity:CloudEntity,fields:JsonObject=JsonObject(emptyMap())):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(entity.table,id,owner.value,JsonObject(buildJsonObject {put("id",id);put("user_id",owner.value);put("created_at",time);put("occurred_at",time);put("updated_at",time);put("is_archived",false)}+fields),time,null,0)
    }
    private fun wallet(amount:Long=10)=raw(CloudEntity.LEDGER_WALLET,buildJsonObject {
        put("name","Raw cash");put("kind_raw_value","cash");put("opening_balance_minor",amount);put("currency_code","JPY")
    })
    private fun row(wallet:CloudRecord?,amount:Long=3,kind:String="expense")=raw(CloudEntity.LEDGER_TRANSACTION,buildJsonObject {
        put("title","Raw cash leg");put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("amount_minor",amount);put("source_currency_code","JPY")
        wallet?.let {put("source_wallet_id",it.id)}
    })
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    private fun total(wallets:List<CloudRecord>,rows:List<CloudRecord> = emptyList())=overviewAssetBalance(owner,rows,wallets,"JPY")
    private fun minor(expected:Long,actual:Any?)=assertEquals(expected.toString(),actual?.toString())
    @Test fun `unreadable eligible opening holds whole assets instead of silently omitting cash`() {
        val good=wallet(7);val damaged=wallet()
        for(value in listOf(JsonPrimitive("broken"),JsonNull,JsonPrimitive(1.5))) assertNull(total(listOf(good,damaged.with("opening_balance_minor",value))))
        minor(17,total(listOf(good,damaged)))
    }
    @Test fun `unreadable posted owned wallet leg holds assets until money is repaired`() {
        val cash=wallet();val good=row(cash)
        for(value in listOf(JsonPrimitive("broken"),JsonNull,JsonPrimitive(1.5))) assertNull(total(listOf(cash),listOf(good.with("amount_minor",value))))
        minor(7,total(listOf(cash),listOf(good)))
    }
    @Test fun `numeric strings are not valid wire opening or ledger minor units`() {
        val cash=wallet();assertNull(total(listOf(cash.with("opening_balance_minor",JsonPrimitive("10")))))
        assertNull(total(listOf(cash),listOf(row(cash).with("amount_minor",JsonPrimitive("3")))))
    }
    @Test fun `cash survives unrelated unreadable calendars reporting or unused destination metadata`() {
        val cash=wallet();val original=row(cash)
        for(key in listOf("occurred_at","created_at","reporting_expense_minor","reporting_income_minor","destination_amount_minor"))
            minor(7,total(listOf(cash),listOf(original.with(key,JsonPrimitive("broken")))))
        minor(7,total(listOf(cash),listOf(original.with("occurred_at",JsonPrimitive("2030-01-01T00:00:00Z")))))
    }
    @Test fun `unresolved active wallet or posted record eligibility cannot produce a confident number`() {
        val cash=wallet();val original=row(cash)
        for(key in listOf("is_archived","kind_raw_value")) assertNull(total(listOf(cash.with(key,JsonPrimitive("broken")))))
        for(key in listOf("is_archived","entry_status_raw_value","primary_kind_raw_value")) assertNull(total(listOf(cash),listOf(original.with(key,JsonPrimitive("broken")))))
    }
    @Test fun `known excluded or unselected malformed cash rows never poison owned active balances`() {
        val cash=wallet(7);val damaged=wallet().with("opening_balance_minor",JsonPrimitive("broken"))
        val hidden=listOf(damaged.copy(ownerUserId=other),damaged.with("user_id",JsonPrimitive(other)),damaged.with("id",JsonPrimitive(UUID.randomUUID().toString())),
            damaged.copy(deletedAt=time),damaged.with("is_archived",JsonPrimitive(true)),damaged.with("kind_raw_value",JsonPrimitive("creditCard")))
        val bad=row(cash).with("amount_minor",JsonPrimitive("broken"))
        val irrelevant=listOf(bad.copy(ownerUserId=other),bad.copy(deletedAt=time),bad.with("is_archived",JsonPrimitive(true)),bad.with("entry_status_raw_value",JsonPrimitive("draft")),
            row(null).with("amount_minor",JsonPrimitive("broken")),bad.with("source_wallet_id",JsonPrimitive(UUID.randomUUID().toString())))
        val before=hidden+irrelevant+cash
        minor(7,total(listOf(cash)+hidden,irrelevant));assertEquals(before,hidden+irrelevant+cash)
    }
    @Test fun `internal transfer reads only the required owned wallet legs`() {
        val cash=wallet();val foreign=wallet().copy(ownerUserId=other)
        val incoming=row(foreign,kind="transfer").with("transfer_subtype_raw_value",JsonPrimitive("internalTransfer"))
            .with("destination_wallet_id",JsonPrimitive(cash.id)).with("destination_amount_minor",JsonPrimitive(100)).with("amount_minor",JsonPrimitive("broken"))
        minor(110,total(listOf(cash),listOf(incoming)))
        val outgoing=row(cash,kind="transfer").with("transfer_subtype_raw_value",JsonPrimitive("internalTransfer"))
            .with("destination_wallet_id",JsonPrimitive(foreign.id)).with("destination_amount_minor",JsonPrimitive("broken"))
        minor(7,total(listOf(cash),listOf(outgoing)))
    }
    @Test fun `archive booleans are strict while matching legacy identities may be absent`() {
        val cash=wallet();assertNull(total(listOf(cash.with("is_archived",JsonPrimitive("false")))))
        assertNull(total(listOf(cash),listOf(row(cash).with("is_archived",JsonPrimitive("false")))))
        minor(10,total(listOf(cash.copy(payload=JsonObject(cash.payload-listOf("id","user_id"))))))
    }
    @Test fun `unreadable required wallet identity holds cash but unused identity does not`() {
        val cash=wallet();val original=row(cash)
        for(value in listOf(JsonPrimitive("broken"),JsonPrimitive(123))) assertNull(total(listOf(cash),listOf(original.with("source_wallet_id",value))))
        minor(7,total(listOf(cash),listOf(original.with("destination_wallet_id",JsonPrimitive("broken")))))
        minor(10,total(listOf(cash),listOf(original.with("source_wallet_id",JsonNull))))
    }
    @Test fun `unreadable tombstone flags hold potential cash instead of silently dropping it`() {
        val cash=wallet()
        assertNull(total(listOf(cash.with("deleted_at",JsonPrimitive(false)))))
        assertNull(total(listOf(cash),listOf(row(cash).with("deleted_at",JsonPrimitive(false)))))
        minor(0,total(listOf(cash.with("deleted_at",JsonPrimitive(time)))))
    }
    @Test fun `same currency credit source metadata does not require an unused credit opening`() {
        val cash=wallet();val credit=wallet().with("kind_raw_value",JsonPrimitive("creditCard")).with("opening_balance_minor",JsonPrimitive("broken"))
        val transfer=row(credit,kind="transfer").with("transfer_subtype_raw_value",JsonPrimitive("internalTransfer"))
            .with("destination_wallet_id",JsonPrimitive(cash.id)).with("source_currency_code",JsonNull)
        minor(13,total(listOf(cash,credit),listOf(transfer)))
        assertNull(total(listOf(cash,credit.with("currency_code",JsonPrimitive("VND"))),listOf(transfer)))
        minor(110,total(listOf(cash,credit.with("currency_code",JsonPrimitive("VND"))),listOf(transfer.with("destination_amount_minor",JsonPrimitive(100)))))
    }
    @Test fun `unreadable explicit source currency cannot become a legacy incoming pair`() {
        val cash=wallet();val source=wallet()
        val transfer=row(source,kind="transfer").with("transfer_subtype_raw_value",JsonPrimitive("internalTransfer"))
            .with("destination_wallet_id",JsonPrimitive(cash.id))
        for(value in listOf(JsonPrimitive(123),JsonPrimitive(false),buildJsonObject {})) {
            assertNull(total(listOf(cash,source),listOf(transfer.with("source_currency_code",value))))
            minor(117,total(listOf(cash,source),listOf(transfer.with("source_currency_code",value).with("destination_amount_minor",JsonPrimitive(100)))))
        }
    }
    @Test fun `resale uses its required cost leg while shared principal and unused money remain neutral`() {
        val cash=wallet();val resale=row(cash,kind="transfer").with("transfer_subtype_raw_value",JsonPrimitive("debt")).with("debt_intent_raw_value",JsonPrimitive("lend"))
            .with("settlement_role_raw_value",JsonPrimitive("resaleReceivable")).with("reporting_expense_minor",JsonPrimitive(3))
        minor(7,total(listOf(cash),listOf(resale.with("amount_minor",JsonPrimitive("broken")))))
        assertNull(total(listOf(cash),listOf(resale.with("reporting_expense_minor",JsonPrimitive("broken")))))
        val shared=resale.with("settlement_role_raw_value",JsonPrimitive("sharedExpenseReceivable")).with("amount_minor",JsonPrimitive("broken")).with("reporting_expense_minor",JsonPrimitive("broken"))
        minor(10,total(listOf(cash),listOf(shared)))
    }
}
