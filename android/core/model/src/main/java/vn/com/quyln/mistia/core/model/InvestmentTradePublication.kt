package vn.com.quyln.mistia.core.model

import java.time.Instant
import kotlinx.serialization.json.*

/** Validate submitted intent separately from the server's rebuilt FIFO/financial projection. */
fun requireInvestmentTradeForPublication(owner:UserId,row:CloudRecord,forWrite:Boolean=true,allowLocalEvidence:Boolean=true) {
    require(financeRawUuid(owner.value)==owner.value && financeRawUuid(row.id)==row.id)
    require(row.entity==CloudEntity.INVESTMENT_TRADE.table && row.ownerUserId==owner.value &&
        row.financeRawIdentity(owner,CloudEntity.INVESTMENT_TRADE,true))
    val p=row.payload
    if(allowLocalEvidence)localInvestmentTradePublicationParents(row) else require(LOCAL_TRADE_PUBLICATION_PARENTS_KEY !in p)
    require(p.financeRawString("id")==row.id && p.financeRawString("user_id")==owner.value)
    require(p.financeRawLong("sync_version")==row.syncVersion && row.syncVersion>=0)
    for(key in LOCAL_ASSET_PUBLICATION_KEYS+LOCAL_INVESTMENT_WALLET_PARENTS_KEY)require(key !in p)
    for(key in listOf("asset_id","channel_id")) {
        val id=requireNotNull(p.financeRawString(key));require(financeRawUuid(id)==id)
    }
    for(key in listOf("created_at","updated_at","occurred_at"))Instant.parse(requireNotNull(p.financeRawString(key)))
    require(row.updatedAt==p.financeRawString("updated_at"))
    require(row.financeRawDeleted(true)!=null && row.deletedAt==p.financeRawString("deleted_at"))
    if(forWrite)require(row.deletedAt==null)
    fun text(key:String):String? {
        val value=p[key];require(value==null || value==JsonNull || value is JsonPrimitive && value.isString)
        return p.financeRawString(key)
    }
    val device=text("last_modified_by_device_id")
    if(forWrite)require(device!=null)
    device?.let{require(financeRawUuid(it)==it)}
    val kind=requireNotNull(text("kind_raw_value"));require(kind in setOf("buy","sell"))
    require(investmentTradeQuantity(requireNotNull(text("quantity_decimal_string")))!=null)
    val unit=text("unit_label")
    if(forWrite)require(InvestmentUnitLabel.normalizedDisplay(unit)!=null)
    val amount=requireNotNull(p.financeRawLong("gross_amount_minor"));val accounting=requireNotNull(p.financeRawLong("accounting_gross_amount_minor"))
    require(amount>=0 && accounting>=0 && (amount==0L)==(accounting==0L))
    val currency=requireNotNull(investmentAssetCurrency(requireNotNull(text("currency_code"))))
    val accountingCode=requireNotNull(investmentAssetCurrency(requireNotNull(text("accounting_currency_code"))))
    fun reference(key:String):String? {
        val ref=p.financeRawReference(key);require(ref.readable)
        ref.id?.let{require(financeRawUuid(it)==it)}
        return ref.id
    }
    val funding=reference("funding_wallet_id");val capital=reference("capital_return_wallet_id")
    val rates=listOf("exchange_rate_decimal_string","funding_to_accounting_rate_decimal_string","accounting_to_capital_return_rate_decimal_string").associateWith{key->
        text(key)?.also { value->
            require(value.length<=256)
            val decimal=requireNotNull(value.toBigDecimalOrNull());require(decimal.signum()>0 && decimal.scale() in -165..128)
            InvestmentDecimalMath.quantity(decimal)
        }
    }
    for(key in listOf("exchange_rate_provider","exchange_rate_date","note"))text(key)
    if(amount==0L) {
        require(funding==null && capital==null && rates.values.all{it==null})
    } else {
        if(kind=="buy")require(funding!=null && capital==null) else require(capital!=null && funding==null)
        require(investmentPurchaseConvertedMinor(amount,currency,accountingCode,rates["exchange_rate_decimal_string"])==accounting)
    }
}

/** The RPC rebuilds these fields; their cached values cannot authorize a financial write. */
private val derivedTradePublicationFields=setOf(
    "funding_wallet_currency_code","capital_return_wallet_currency_code","funding_wallet_amount_minor","capital_return_wallet_amount_minor",
    "funding_ledger_transaction_id","capital_return_ledger_transaction_id","profit_loss_ledger_transaction_id",
    "released_cost_basis_minor","realized_profit_loss_minor","position_quantity_after_decimal_string","position_cost_basis_after_minor",
)
fun investmentTradePayloadForCloud(payload:JsonObject):JsonObject=JsonObject(payload-derivedTradePublicationFields-LOCAL_TRADE_PUBLICATION_PARENTS_KEY)

data class InvestmentTradeMutationResult(val requested:CloudRecord,val trades:List<CloudRecord>)
interface InvestmentTradeRemote {
    suspend fun fetchTradeResult(owner:UserId,affectedAssetIds:Set<String>,knownTradeIds:Set<String>,accessToken:String):InvestmentTradeCloudSnapshot =
        throw UnsupportedOperationException("Investment trade result reads are unavailable")
    suspend fun fetchTrade(owner:UserId,id:String,accessToken:String):CloudRecord?
    suspend fun mutateTrade(owner:UserId,proposal:CloudRecord,expectedVersion:Long,affectedAssetIds:Set<String>,accessToken:String):InvestmentTradeMutationResult?
    suspend fun deleteTrade(owner:UserId,id:String,expectedVersion:Long,modifiedAt:String,deviceId:String,accessToken:String):CloudRecord?
}

/** Whether this one desired intent can be applied before the other queued intents, using wire-precision FIFO dates. */
fun canApplyInvestmentTradeToCloudHistory(owner:UserId,history:List<CloudRecord>,proposal:CloudRecord):Boolean {
    require(history.size<=10000 && history.map{it.id}.distinct().size==history.size)
    history.forEach{requireInvestmentTradeForPublication(owner,it,forWrite=false,allowLocalEvidence=false)}
    requireInvestmentTradeForPublication(owner,proposal,forWrite=false)
    fun date(raw:CloudRecord,key:String):Instant {
        val parsed=Instant.parse(requireNotNull(raw.payload.financeRawString(key)))
        return Instant.ofEpochSecond(parsed.epochSecond,Math.rint(parsed.nano.toDouble()/1000).toLong()*1000)
    }
    val desired=(history.filterNot{it.id==proposal.id}+proposal).filter{it.deletedAt==null}
    return try {
        for(rows in desired.groupBy{it.payload.financeRawString("asset_id")}.values)InvestmentAccountingEngine.projection(rows.map{raw->
            val p=raw.payload
            InvestmentTradeInput(java.util.UUID.fromString(raw.id),if(p.financeRawString("kind_raw_value")=="buy")InvestmentTradeKind.BUY else InvestmentTradeKind.SELL,
                requireNotNull(investmentTradeQuantity(requireNotNull(p.financeRawString("quantity_decimal_string")))),p.financeRawString("unit_label"),
                requireNotNull(p.financeRawLong("accounting_gross_amount_minor")),date(raw,"occurred_at"),date(raw,"created_at"))
        })
        true
    }catch(dependency:InvestmentAccountingException){false}
    catch(overflow:ArithmeticException){false}
}
