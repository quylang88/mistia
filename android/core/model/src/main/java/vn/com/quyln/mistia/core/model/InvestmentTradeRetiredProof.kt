package vn.com.quyln.mistia.core.model

import java.time.Instant
import kotlinx.serialization.json.*

/** A completed edit retains the original financial content of the legs it retired. */
internal fun requireInvestmentTradeRetiredProof(snapshot:InvestmentTradeCreationSnapshot,expected:CloudRecord) {
    fun fail():Nothing=investmentAssetFail(InvestmentAssetError.INVALID_ACCOUNTING)
    val p=expected.payload
    fun text(key:String)=p.financeRawString(key) ?: fail()
    fun amount(key:String)=p.financeRawLong(key) ?: fail()
    fun ref(key:String):String?=p.financeRawReference(key).let{if(!it.readable)fail();it.id}
    val account=text("accounting_currency_code");val asset=ref("asset_id") ?: fail()
    val occurred=Instant.parse(text("occurred_at")).toString()
    fun same(row:CloudRecord,fields:JsonObject):Boolean=fields.all{(key,value)->
        if(key=="occurred_at")row.payload.financeRawString(key)?.let{runCatching{Instant.parse(it).toString()}.getOrNull()}==occurred
        else row.payload[key]==value
    }
    fun magnitude(value:Long)=if(value<0)Math.negateExact(value) else value
    fun check(component:String,role:String,wallet:String,currency:String,local:Long,booked:Long,kind:String,
        postingRole:String,postingPart:String=component+"-posting",cash:Boolean=false) {
        val ledgerId=investmentLedgerIdentity(expected.id,component)
        val ledger=snapshot.rows.singleOrNull{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==ledgerId} ?: fail()
        if(ledger.financeRawDeleted(true)==true && !same(ledger,buildJsonObject {
            put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("settlement_role_raw_value",role)
            put("amount_minor",magnitude(local));put("source_wallet_id",wallet);put("source_currency_code",currency)
            put("destination_wallet_id",JsonNull);put("destination_currency_code",JsonNull);put("destination_amount_minor",JsonNull)
            put("reporting_amount_minor",magnitude(booked));put("reporting_currency_code",account)
            put("reporting_expense_minor",0L);put("reporting_income_minor",0L);put("occurred_at",occurred)
        }))fail()
        val posting=snapshot.rows.singleOrNull{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.id==investmentLedgerIdentity(expected.id,postingPart)} ?: fail()
        if(posting.financeRawDeleted(true)==true && !same(posting,buildJsonObject {
            put("event_id",expected.id);put("trade_id",expected.id);put("asset_id",asset);put("wallet_id",wallet);put("ledger_transaction_id",ledgerId)
            put("role_raw_value",postingRole);put("amount_minor",local);put("currency_code",currency);put("accounting_amount_minor",booked);put("accounting_currency_code",account)
            put("cash_bucket_raw_value",if(cash)JsonPrimitive("booked") else JsonNull);put("cash_origin_raw_value",if(cash)JsonPrimitive("derived") else JsonNull);put("occurred_at",occurred)
        }))fail()
    }
    if(ref("funding_ledger_transaction_id")!=null) {
        check("funding","investmentFunding",ref("funding_wallet_id") ?: fail(),text("funding_wallet_currency_code"),
            Math.negateExact(amount("funding_wallet_amount_minor")),Math.negateExact(amount("accounting_gross_amount_minor")),"expense","funding")
    }
    val capital=ref("capital_return_wallet_id")
    if(ref("capital_return_ledger_transaction_id")!=null) {
        check("capital-return","investmentCapitalReturn",capital ?: fail(),text("capital_return_wallet_currency_code"),
            amount("capital_return_wallet_amount_minor"),amount("released_cost_basis_minor"),"income","capitalReturn")
    }
    if(ref("profit_loss_ledger_transaction_id")!=null) {
        val profit=amount("realized_profit_loss_minor")
        val currency=if(capital==null)account else text("capital_return_wallet_currency_code")
        val local=if(capital==null)profit else Math.subtractExact(investmentPurchaseConvertedMinor(amount("accounting_gross_amount_minor"),account,currency,
            p.financeRawString("accounting_to_capital_return_rate_decimal_string")),amount("capital_return_wallet_amount_minor"))
        val wallet=capital ?: investmentSystemWalletId(snapshot.owner)
        val kind=if(profit>0)"income" else "expense"
        check("profit-loss","investmentRealizedProfit",wallet,currency,local,profit,kind,"realizedProfit")
        check("profit-loss","investmentRealizedProfit",wallet,currency,local,profit,kind,"cashAccrual","cash-accrual-posting",true)
    }
}
