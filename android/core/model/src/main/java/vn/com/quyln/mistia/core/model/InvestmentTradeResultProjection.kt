package vn.com.quyln.mistia.core.model

import java.time.Instant
import kotlinx.serialization.json.*

enum class InvestmentTradeResultError { UNREADABLE_SOURCE, DEPENDENCY_PENDING, INVALID_RESULT, INCOMPLETE_RESULT }
class InvestmentTradeResultException(val reason:InvestmentTradeResultError):IllegalArgumentException(reason.name)

/** A mathematical result proof, not permission to acknowledge any queue. */
fun projectInvestmentTradePublicationResult(
    source:InvestmentTradePublicationSnapshot,remoteTrades:List<CloudRecord>,affectedAssetIds:Set<String>,deviceId:String,now:String,
    metadata:List<CloudRecord> = emptyList(),
):List<CloudRecord> {
    fun fail(reason:InvestmentTradeResultError=InvestmentTradeResultError.INVALID_RESULT):Nothing=throw InvestmentTradeResultException(reason)
    fun context():Nothing=fail(InvestmentTradeResultError.UNREADABLE_SOURCE)
    try{source.requireCoherent();investmentAssetIdentity(deviceId);Instant.parse(now)}catch(_:Exception){context()}
    if(affectedAssetIds.size !in 1..2 || affectedAssetIds.any{financeRawUuid(it)!=it})fail()
    if(remoteTrades.map{it.id}.distinct().size!=remoteTrades.size)fail()
    for(row in remoteTrades) {
        try{requireInvestmentTradeForPublication(source.owner,row,forWrite=false,allowLocalEvidence=false)}catch(_:Exception){fail()}
        if(row.payload.financeRawString("asset_id") !in affectedAssetIds)fail()
    }
    val sourceByKey=source.rows.associateBy{it.entity to it.id}
    fun row(entity:CloudEntity,id:String)=sourceByKey[entity.table to id] ?: context()
    fun reference(p:JsonObject,key:String):String?=p.financeRawReference(key).let{if(!it.readable)fail();it.id}
    val remoteIds=remoteTrades.map{it.id}.toSet()
    for(local in source.rows.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table}) {
        val asset=local.payload.financeRawReference("asset_id")
        if(!asset.readable || asset.id==null)context()
        if(asset.id in affectedAssetIds) {
            val deleted=local.financeRawDeleted(true) ?: context()
            if(!deleted && local.id !in remoteIds)fail(InvestmentTradeResultError.INCOMPLETE_RESULT)
        }
    }
    val systemId=investmentSystemWalletId(source.owner)
    val system=row(CloudEntity.LEDGER_WALLET,systemId)
    try{canonicalInvestmentWalletForPublication(source.owner,system,forWrite=true)}catch(_:Exception){context()}
    val assets=affectedAssetIds.associateWith{id->
        val raw=row(CloudEntity.INVESTMENT_ASSET,id)
        val asset=try{InvestmentAssetRecord.fromCloudRecord(raw)}catch(_:Exception){context()}
        row(CloudEntity.INVESTMENT_CHANNEL,asset.channelId)
        asset
    }
    val dependencies=linkedSetOf(CloudEntity.LEDGER_WALLET.table to systemId)
    for(asset in assets.values) {
        dependencies+=CloudEntity.INVESTMENT_ASSET.table to asset.id
        dependencies+=CloudEntity.INVESTMENT_CHANNEL.table to asset.channelId
    }
    for(trade in remoteTrades.filter{it.deletedAt==null}) {
        val id=reference(trade.payload,if(trade.payload.financeRawString("kind_raw_value")=="buy")"funding_wallet_id" else "capital_return_wallet_id")
        id?.let{row(CloudEntity.LEDGER_WALLET,it);dependencies+=CloudEntity.LEDGER_WALLET.table to it}
    }
    val walletProofs=try{walletInvestmentActivePrerequisites(source,dependencies.filter{it.first==CloudEntity.LEDGER_WALLET.table}.map{it.second}.toSet())}catch(_:Exception){fail()}
    val proven=(if(metadata.isEmpty())emptySet() else try {
        investmentTradeActiveMetadataPrerequisites(source,affectedAssetIds,metadata)
    }catch(_:Exception){fail()})+walletProofs.keys.map{CloudEntity.LEDGER_WALLET.table to it}
    if(dependencies.any{it in source.dirtyKeys && it !in proven})fail(InvestmentTradeResultError.DEPENDENCY_PENDING)
    // Project against the proven active prerequisite view; the final archived
    // local row and its queue remain in source for the exact-generation ACK.
    val rows=source.rows.filterNot{it.entity==CloudEntity.INVESTMENT_TRADE.table && reference(it.payload,"asset_id") in affectedAssetIds}
        .map{if(it.entity==CloudEntity.LEDGER_WALLET.table)walletProofs[it.id] ?: it else it}+remoteTrades
    val snapshot=InvestmentAssetSnapshot(source.owner,rows.filter{CloudEntity.fromTable(it.entity) in InvestmentAssetSnapshot.entities})
    val result=linkedMapOf<Pair<String,String>,CloudRecord>()
    for(asset in assets.values) {
        val projected=try{rebuildInvestmentAssetUnitHistory(snapshot,asset,asset.defaultUnitLabel ?: "legacy",deviceId,now,
            resolveZeroBuyFunding=false,preserveLegacyUnitLabels=true)}catch(_:Exception){fail()}
        projected.forEach{result[it.entity to it.id]=it}
    }
    fun code(id:String):JsonPrimitive {
        val wallet=row(CloudEntity.LEDGER_WALLET,id)
        val code=wallet.payload.financeRawString("currency_code")?.let(::investmentAssetCurrency) ?: context()
        return JsonPrimitive(code)
    }
    fun normalized(value:JsonElement?,key:String):JsonElement {
        if(value==null || value==JsonNull)return JsonNull
        if(key=="position_quantity_after_decimal_string") {
            val text=(value as? JsonPrimitive)?.takeIf{it.isString}?.content ?: fail()
            val amount=text.takeIf{it.length<=256}?.toBigDecimalOrNull()?.takeIf{it.signum()>=0 && it.scale() in -165..128} ?: fail()
            return JsonPrimitive(InvestmentDecimalMath.quantity(amount).stripTrailingZeros().toPlainString())
        }
        if(key.endsWith("_minor")) {
            val number=(value as? JsonPrimitive)?.takeIf{!it.isString}?.longOrNull ?: fail()
            return JsonPrimitive(number)
        }
        if(key.endsWith("_currency_code")) {
            val text=(value as? JsonPrimitive)?.takeIf{it.isString}?.content ?: fail()
            return JsonPrimitive(investmentAssetCurrency(text) ?: fail())
        }
        val text=(value as? JsonPrimitive)?.takeIf{it.isString}?.content ?: fail()
        return JsonPrimitive(financeRawUuid(text) ?: fail())
    }
    for(trade in remoteTrades.filter{it.deletedAt==null}) {
        val generated=result[trade.entity to trade.id] ?: fail()
        val p=generated.payload.toMutableMap()
        val buying=trade.payload.financeRawString("kind_raw_value")=="buy"
        val selected=reference(trade.payload,if(buying)"funding_wallet_id" else "capital_return_wallet_id")
        p["funding_wallet_currency_code"]=if(buying && selected!=null)code(selected) else JsonNull
        p["capital_return_wallet_currency_code"]=if(!buying && selected!=null)code(selected) else JsonNull
        if(buying)p["capital_return_wallet_amount_minor"]=JsonNull else p["funding_wallet_amount_minor"]=JsonNull
        val expected=JsonObject(p)
        for(key in DERIVED_TRADE_RESULT_KEYS)if(normalized(expected[key],key)!=normalized(trade.payload[key],key))fail()
        result[trade.entity to trade.id]=generated.copy(payload=expected)
    }
    val ledgerRoles=mapOf("funding" to "investmentFunding","capital-return" to "investmentCapitalReturn","profit-loss" to "investmentRealizedProfit")
    val postingRoles=mapOf("funding-posting" to "funding","capital-return-posting" to "capitalReturn","profit-loss-posting" to "realizedProfit","cash-accrual-posting" to "cashAccrual")
    val financialIdentities=linkedMapOf<Pair<String,String>,Triple<String,String,String>>()
    for(trade in remoteTrades)for((entity,roles) in listOf(CloudEntity.LEDGER_TRANSACTION to ledgerRoles,CloudEntity.INVESTMENT_POSTING to postingRoles))
        for((component,role) in roles) {
            val key=entity.table to investmentLedgerIdentity(trade.id,component)
            if(financialIdentities.put(key,Triple(trade.id,component,role))!=null)fail()
        }
    for(generated in result.values.filter{it.entity!=CloudEntity.INVESTMENT_TRADE.table}) {
        val key=generated.entity to generated.id
        val old=sourceByKey[key]
        val isLedger=generated.entity==CloudEntity.LEDGER_TRANSACTION.table
        val identity=financialIdentities[key] ?: fail()
        val(trade,component,role)=identity
        val roleKey=if(isLedger)"settlement_role_raw_value" else "role_raw_value"
        if(generated.payload.financeRawString(roleKey)!=role || old!=null && old.payload.financeRawString(roleKey)!=role)context()
        if(!isLedger) {
            val ledgerComponent=if(component=="cash-accrual-posting")"profit-loss" else component.removeSuffix("-posting")
            for(raw in listOfNotNull(old,generated))if(reference(raw.payload,"trade_id")!=trade || reference(raw.payload,"event_id")!=trade ||
                reference(raw.payload,"ledger_transaction_id")!=investmentLedgerIdentity(trade,ledgerComponent))context()
        }
    }
    return result.values.toList()
}

internal val DERIVED_TRADE_RESULT_KEYS=setOf(
    "funding_wallet_currency_code","capital_return_wallet_currency_code","funding_wallet_amount_minor","capital_return_wallet_amount_minor",
    "funding_ledger_transaction_id","capital_return_ledger_transaction_id","profit_loss_ledger_transaction_id",
    "released_cost_basis_minor","realized_profit_loss_minor","position_quantity_after_decimal_string","position_cost_basis_after_minor",
)
