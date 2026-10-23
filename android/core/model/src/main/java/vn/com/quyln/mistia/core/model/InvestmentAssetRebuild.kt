package vn.com.quyln.mistia.core.model

import java.math.BigDecimal
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.json.*

fun investmentLedgerIdentity(eventId:String,component:String):String {
    investmentAssetIdentity(eventId)
    val bytes=MessageDigest.getInstance("SHA-256").digest("com.mistia.investment.ledger:$eventId:$component".toByteArray(Charsets.UTF_8)).copyOf(16)
    bytes[6]=((bytes[6].toInt() and 0x0f) or 0x50).toByte()
    bytes[8]=((bytes[8].toInt() and 0x3f) or 0x80).toByte()
    val buffer=java.nio.ByteBuffer.wrap(bytes)
    return UUID(buffer.long,buffer.long).toString()
}

internal fun rebuildInvestmentAssetUnitHistory(
    snapshot:InvestmentAssetSnapshot,asset:InvestmentAssetRecord,unit:String,device:String,now:String,
    resolveZeroBuyFunding:Boolean=true,
    preserveAccountingErrors:Boolean=false,
):List<CloudRecord> {
    fun fail(reason:InvestmentAssetError=InvestmentAssetError.INVALID_ACCOUNTING):Nothing=investmentAssetFail(reason)
    fun JsonObject.text(key:String)=financeRawString(key) ?: fail()
    fun JsonObject.amount(key:String)=financeRawLong(key)?.takeIf{it>=0} ?: fail()
    fun JsonObject.reference(key:String):String? {
        val ref=financeRawReference(key)
        if(!ref.readable)fail()
        return ref.id
    }
    fun code(value:String)=investmentAssetCurrency(value) ?: fail()
    val rows=linkedMapOf<Pair<String,String>,CloudRecord>()
    fun existing(entity:CloudEntity,id:String)=snapshot.records(entity).singleOrNull{it.id==id}
    fun write(raw:CloudRecord){rows[raw.entity to raw.id]=raw}
    fun fieldVersion(raw:CloudRecord?):Long=raw?.let{try{investmentAssetVersion(it)}catch(_:Exception){fail(InvestmentAssetError.UNREADABLE_SOURCE)}} ?: 0L
    fun upsert(entity:CloudEntity,id:String,fields:JsonObject):CloudRecord {
        val old=existing(entity,id)
        val version=fieldVersion(old)
        if(old!=null) {
            investmentAssetDate(old.payload.financeRawString("created_at") ?: fail(InvestmentAssetError.UNREADABLE_SOURCE))
            if(entity==CloudEntity.LEDGER_TRANSACTION && old.payload.financeRawString("settlement_role_raw_value")?.startsWith("investment")!=true)fail()
            if(entity==CloudEntity.INVESTMENT_POSTING && old.payload.reference("trade_id") !in investmentAssetHistory(snapshot,asset.id).map{it.id}.toSet())fail()
        }
        val p=buildJsonObject {
            old?.payload?.forEach{put(it.key,it.value)}
            put("id",id);put("user_id",snapshot.owner.value);put("created_at",old?.payload?.text("created_at") ?: now)
            put("updated_at",now);put("deleted_at",JsonNull);put("last_modified_by_device_id",device)
            if(old==null || "sync_version" in old.payload)put("sync_version",version)
            fields.forEach{put(it.key,it.value)}
        }
        return CloudRecord(entity.table,id,snapshot.owner.value,p,now,null,version).also(::write)
    }
    fun tombstone(raw:CloudRecord) {
        if(raw.financeRawDeleted(true)==false)write(investmentAssetChanged(raw,buildJsonObject{put("deleted_at",now)},device,now).copy(deletedAt=now))
        else if(raw.financeRawDeleted(true)==null)fail(InvestmentAssetError.UNREADABLE_SOURCE)
    }
    fun wallet(id:String?):CloudRecord {
        val result=id?.let{existing(CloudEntity.LEDGER_WALLET,it)} ?: fail(InvestmentAssetError.MISSING_WALLET)
        if(result.financeRawDeleted(true)!=false)fail(InvestmentAssetError.MISSING_WALLET)
        code(result.payload.text("currency_code"))
        return result
    }
    fun convert(amount:Long,source:String,destination:String,rate:String?,inverse:Boolean=false):Long {
        if(code(source)==code(destination))return amount
        val decimal=rate?.toBigDecimalOrNull()?.takeIf{it.signum()>0} ?: fail(InvestmentAssetError.MISSING_EXCHANGE_RATE)
        // Stored FX rates describe major units. Swift's enabled JPY/VND both
        // have zero fraction digits; imported ISO currencies can differ.
        val scale=BigDecimal.ONE.scaleByPowerOfTen(java.util.Currency.getInstance(code(destination)).defaultFractionDigits-
            java.util.Currency.getInstance(code(source)).defaultFractionDigits)
        return try {
            if(inverse)InvestmentDecimalMath.proportionalMinor(amount,scale,InvestmentDecimalMath.quantity(decimal))
            else InvestmentDecimalMath.proportionalMinor(amount,InvestmentDecimalMath.quantity(decimal.multiply(scale)),BigDecimal.ONE)
        }catch(_:ArithmeticException){fail()}
    }
    val history=investmentAssetHistory(snapshot,asset.id)
    val labelled=history.map{raw ->
        val label=raw.payload["unit_label"]
        if(label!=null && label!=JsonNull && raw.payload.financeRawString("unit_label")==null)
            fail(InvestmentAssetError.UNREADABLE_SOURCE)
        if(raw.payload["unit_label"]==null || raw.payload["unit_label"]==JsonNull)
            investmentAssetChanged(raw,buildJsonObject{put("unit_label",unit)},device,now).also(::write)
        else raw
    }
    val active=labelled.filter{
        it.financeRawDeleted(true) ?: fail(InvestmentAssetError.UNREADABLE_SOURCE)
        it.financeRawDeleted(true)==false
    }
    if(active.isEmpty())return rows.values.toList()
    val system=wallet(investmentSystemWalletId(snapshot.owner))
    val systemCurrency=code(system.payload.text("currency_code"))
    val inputs=active.map{raw ->
        val p=raw.payload
        val kind=when(p.text("kind_raw_value")){"buy"->InvestmentTradeKind.BUY;"sell"->InvestmentTradeKind.SELL;else->fail()}
        val quantity=p.text("quantity_decimal_string").toBigDecimalOrNull() ?: fail()
        val accountingCurrency=code(p.text("accounting_currency_code"))
        if(accountingCurrency!=systemCurrency)fail()
        try{fieldVersion(raw)
            InvestmentTradeInput(UUID.fromString(raw.id),kind,quantity,p.financeRawString("unit_label"),p.amount("accounting_gross_amount_minor"),
                Instant.parse(p.text("occurred_at")),Instant.parse(p.text("created_at")))
        }catch(_:Exception){fail()}
    }
    val calculations=try{InvestmentAccountingEngine.projection(inputs).calculations.associateBy{it.id.toString()}}
        catch(error:InvestmentAccountingException){if(preserveAccountingErrors)throw error else fail()}
    fun ledger(trade:CloudRecord,component:String,kind:String,role:String,amount:Long,source:CloudRecord,reporting:Long,reportingCode:String):String {
        val id=investmentLedgerIdentity(trade.id,component)
        val fields=buildJsonObject {
            put("primary_kind_raw_value",kind);put("transfer_subtype_raw_value",JsonNull);put("debt_intent_raw_value",JsonNull)
            put("entry_status_raw_value","posted");put("title",asset.name);put("note",JsonNull);put("amount_minor",amount)
            put("source_currency_code",code(source.payload.text("currency_code")));put("destination_currency_code",JsonNull);put("destination_amount_minor",JsonNull)
            put("reporting_currency_code",reportingCode);put("reporting_amount_minor",reporting)
            put("reporting_expense_minor",0L);put("reporting_income_minor",0L);put("source_wallet_id",source.id);put("destination_wallet_id",JsonNull)
            put("category_id",JsonNull);put("settlement_group_id",JsonNull);put("settlement_obligation_id",JsonNull);put("settlement_role_raw_value",role)
            put("occurred_at",trade.payload.text("occurred_at"));put("is_archived",false);put("archived_at",JsonNull)
            put("created_by_user_id",snapshot.owner.value);put("last_modified_by_user_id",snapshot.owner.value)
            if(existing(CloudEntity.LEDGER_TRANSACTION,id)==null) {
                for(key in listOf("conversion_mode_raw_value","exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","counterparty_name","normalized_counterparty_key"))put(key,JsonNull)
            }
        }
        upsert(CloudEntity.LEDGER_TRANSACTION,id,fields)
        return id
    }
    fun posting(trade:CloudRecord,component:String,role:String,source:CloudRecord,ledgerId:String,amount:Long,accounting:Long,cash:Boolean=false):String {
        val id=investmentLedgerIdentity(trade.id,component)
        upsert(CloudEntity.INVESTMENT_POSTING,id,buildJsonObject {
            put("event_id",trade.id);put("trade_id",trade.id);put("asset_id",asset.id);put("wallet_id",source.id);put("ledger_transaction_id",ledgerId)
            put("role_raw_value",role);put("amount_minor",amount);put("currency_code",code(source.payload.text("currency_code")))
            put("accounting_amount_minor",accounting);put("accounting_currency_code",trade.payload.text("accounting_currency_code"))
            put("occurred_at",trade.payload.text("occurred_at"))
            put("cash_bucket_raw_value",if(cash)JsonPrimitive("booked") else JsonNull)
            put("cash_origin_raw_value",if(cash)JsonPrimitive("derived") else JsonNull)
        })
        return id
    }
    for(raw in active) {
        val p=raw.payload
        val calculation=calculations.getValue(raw.id)
        val accountingCode=code(p.text("accounting_currency_code"))
        val gross=p.amount("gross_amount_minor")
        val accounting=p.amount("accounting_gross_amount_minor")
        code(p.text("currency_code"))
        val ledgerIds=linkedSetOf<String>();val postingIds=linkedSetOf<String>()
        val fields=buildJsonObject {
            put("released_cost_basis_minor",calculation.releasedCostBasisMinor);put("realized_profit_loss_minor",calculation.realizedProfitLossMinor)
            put("position_quantity_after_decimal_string",calculation.positionQuantityAfter.toPlainString())
            put("position_cost_basis_after_minor",calculation.positionCostBasisAfterMinor)
        }.toMutableMap()
        fun clear(vararg keys:String){keys.forEach{fields[it]=JsonNull}}
        fun set(key:String,value:String){fields[key]=JsonPrimitive(value)}
        if(p.text("kind_raw_value")=="buy") {
            // Swift's legacy rebuild resolves funding before reconciling even
            // a zero-cost buy; a missing dependency must not be invented.
            val funding=if(gross==0L && !resolveZeroBuyFunding)null else wallet(p.reference("funding_wallet_id"))
            val local=if(funding==null)0L else convert(accounting,accountingCode,code(funding.payload.text("currency_code")),p.financeRawString("funding_to_accounting_rate_decimal_string"),true)
            if(gross==0L) {
                if(accounting!=0L)fail()
                clear("funding_wallet_id","funding_wallet_currency_code","funding_wallet_amount_minor","funding_ledger_transaction_id","capital_return_ledger_transaction_id","profit_loss_ledger_transaction_id")
            } else {
                fields["funding_wallet_amount_minor"]=JsonPrimitive(local)
                val id=ledger(raw,"funding","expense","investmentFunding",local,requireNotNull(funding),accounting,accountingCode)
                ledgerIds+=id;set("funding_ledger_transaction_id",id);clear("capital_return_ledger_transaction_id","profit_loss_ledger_transaction_id")
                postingIds+=posting(raw,"funding-posting","funding",funding,id,Math.negateExact(local),Math.negateExact(accounting))
            }
        } else {
            val capital:CloudRecord?
            var capitalAmount=0L
            if(gross>0L) {
                capital=wallet(p.reference("capital_return_wallet_id"))
                capitalAmount=convert(calculation.releasedCostBasisMinor,accountingCode,code(capital.payload.text("currency_code")),p.financeRawString("accounting_to_capital_return_rate_decimal_string"))
                fields["capital_return_wallet_amount_minor"]=JsonPrimitive(capitalAmount)
                val id=ledger(raw,"capital-return","income","investmentCapitalReturn",capitalAmount,capital,calculation.releasedCostBasisMinor,accountingCode)
                ledgerIds+=id;set("capital_return_ledger_transaction_id",id);clear("funding_ledger_transaction_id")
                postingIds+=posting(raw,"capital-return-posting","capitalReturn",capital,id,capitalAmount,calculation.releasedCostBasisMinor)
            } else {
                capital=null
                if(accounting!=0L)fail()
                clear("capital_return_wallet_id","capital_return_wallet_currency_code","capital_return_ledger_transaction_id","capital_return_wallet_amount_minor","funding_ledger_transaction_id")
            }
            val profit=calculation.realizedProfitLossMinor
            if(profit!=0L) {
                val profitWallet=capital ?: system
                val cashAmount=if(capital==null)profit else Math.subtractExact(convert(accounting,accountingCode,
                    code(capital.payload.text("currency_code")),p.financeRawString("accounting_to_capital_return_rate_decimal_string")),capitalAmount)
                val localMagnitude=try{if(cashAmount<0)Math.negateExact(cashAmount) else cashAmount}catch(_:ArithmeticException){fail()}
                val reportMagnitude=try{if(profit<0)Math.negateExact(profit) else profit}catch(_:ArithmeticException){fail()}
                val id=ledger(raw,"profit-loss",if(profit>0)"income" else "expense","investmentRealizedProfit",localMagnitude,profitWallet,reportMagnitude,systemCurrency)
                ledgerIds+=id;set("profit_loss_ledger_transaction_id",id)
                postingIds+=posting(raw,"profit-loss-posting","realizedProfit",profitWallet,id,cashAmount,profit)
                postingIds+=posting(raw,"cash-accrual-posting","cashAccrual",profitWallet,id,cashAmount,profit,true)
            } else clear("profit_loss_ledger_transaction_id")
        }
        write(investmentAssetChanged(raw,JsonObject(fields),device,now))
        val priorPostings=snapshot.records(CloudEntity.INVESTMENT_POSTING).filter{it.payload.reference("trade_id")==raw.id}
        priorPostings.filter{it.id !in postingIds}.forEach(::tombstone)
        val priorLedger=setOf("funding","capital-return","profit-loss").map{investmentLedgerIdentity(raw.id,it)}.toSet()
        for(id in priorLedger-ledgerIds) {
            val transaction=existing(CloudEntity.LEDGER_TRANSACTION,id) ?: continue
            if(transaction.payload.financeRawString("settlement_role_raw_value")?.startsWith("investment")!=true)fail()
            tombstone(transaction)
        }
    }
    return rows.values.toList()
}
