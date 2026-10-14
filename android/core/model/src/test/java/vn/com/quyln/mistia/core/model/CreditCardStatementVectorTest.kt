package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
class CreditCardStatementVectorTest(private val name:String,private val vector:JsonObject,private val document:JsonObject) {
    private fun JsonObject.string(key:String)=this[key]?.jsonPrimitive?.contentOrNull
    private fun JsonObject.number(key:String)=this[key]?.jsonPrimitive?.longOrNull
    @Test fun `shared Swift statement and retry business vector`() {
        val owner=UserId(document.string("owner")!!);val card=document.string("card")!!
        val opened=vector.string("openedAt")!!
        val wallet=LedgerWalletRecord(card,owner.value,"Card","creditCard","card","#000000","JPY",0,null,null,0,false,null,opened,opened,null,0,null,null,null)
        val profile=CreditCardProfileRecord("55555555-5555-5555-5555-555555555555",owner.value,"Issuer","visa","1234",100_000,
            vector.number("closingDay")!!.toInt(),vector.number("dueDay")!!.toInt(),null,card,vector.string("paymentSource"),true,opened,opened,null,0,null)
        val records=vector.getValue("transactions").jsonArray.map {it.jsonObject}.map {record ->
            val id=record.string("id")!!;val recordOwner=record.string("owner") ?: owner.value;val at=record.string("at")!!
            val payload=buildJsonObject {
                put("id",id);put("user_id",recordOwner);put("primary_kind_raw_value",record.string("kind"));put("entry_status_raw_value",record.string("status") ?: "posted")
                put("title",record.string("title") ?: "Record");put("amount_minor",record.number("amount"));put("occurred_at",at);put("created_at",at);put("updated_at",at)
                put("created_by_user_id",recordOwner);put("last_modified_by_user_id",recordOwner);put("sync_version",0)
                put("source_wallet_id",record.string("source"));put("destination_wallet_id",record.string("destination"));put("category_id",record.string("category"))
                put("source_currency_code","JPY");put("destination_currency_code","JPY");put("destination_amount_minor",record["destinationAmount"] ?: JsonNull)
                put("transfer_subtype_raw_value",record.string("subtype"));put("debt_intent_raw_value",record.string("intent"))
                put("is_archived",record["archived"]?.jsonPrimitive?.booleanOrNull ?: false)
                put("deleted_at",if(record["deleted"]?.jsonPrimitive?.booleanOrNull==true) JsonPrimitive(at) else JsonNull)
            }
            LedgerTransactionRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,recordOwner,payload,at,null,0))
        }
        val occurrences=vector.getValue("occurrences").jsonArray.mapIndexed {index,item ->
            val row=item.jsonObject;val at=vector.string("reference")!!
            DueOccurrenceRecord("60000000-0000-0000-0000-${(index+1).toString().padStart(12,'0')}",owner.value,"creditCard",card,row.string("month")!!,
                at,row.number("amount"),row.string("status")!!,null,row.string("linked"),at,at,null,0,null)
        }
        val reference=Instant.parse(vector.string("reference"));val zone=ZoneId.of(vector.string("zone"))
        val rows=creditCardStatementItems(owner,listOf(CreditCardAccount(wallet,profile)),records,occurrences,listOf(YearMonth.parse(vector.string("month"))),reference,zone)
        val expected=vector.getValue("expected")
        if(expected==JsonNull) {assertTrue(name,rows.isEmpty());return}
        val wanted=expected.jsonObject;assertEquals(name,1,rows.size);val actual=rows.single()
        assertEquals(name,wanted.number("availableCredit"),actual.availableCreditMinor)
        assertEquals(name,wanted.number("amount"),actual.amountMinor);assertEquals(name,wanted.string("state"),actual.state.wireValue)
        assertEquals(name,wanted.string("status"),actual.status.wireValue);assertEquals(name,wanted.string("linked"),actual.linkedTransactionId)
        assertEquals(name,Instant.parse(wanted.string("closing")),actual.closingDate);assertEquals(name,Instant.parse(wanted.string("due")),actual.dueDate)
        assertEquals(name,wanted.string("decision"),creditCardAutoPaymentDecision(actual,vector.number("sourceBalance"),reference,zone).kind.wireValue)
    }
    companion object {
        @JvmStatic @Parameterized.Parameters(name="{0}") fun vectors():List<Array<Any>> {
            val raw=CreditCardStatementVectorTest::class.java.getResourceAsStream("/credit-card-statements-v1.json")!!.bufferedReader().use {it.readText()}
            val document=Json.parseToJsonElement(raw).jsonObject
            return document.getValue("cases").jsonArray.map {item -> val vector=item.jsonObject;arrayOf<Any>(vector.getValue("name").jsonPrimitive.content,vector,document)}
        }
    }
}
