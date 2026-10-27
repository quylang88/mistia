package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.util.UUID

/** Complete owned metadata/history candidate, followed by the server's atomic archive guard. */
data class InvestmentRetirementHistory(val owner:UserId,val entity:CloudEntity,val id:String,
    val assets:List<CloudRecord>,val trades:List<CloudRecord>)
/** Owned individually valid rows can disagree because the REST reads are not one transaction. */
class InvestmentRetirementHistoryChanged:IllegalStateException("Investment retirement history changed during reads")
interface InvestmentRetirementRemote {
    suspend fun fetchRetirementHistory(owner:UserId,entity:CloudEntity,id:String,accessToken:String):InvestmentRetirementHistory
}
fun investmentRetirementHasPendingDependencies(source:InvestmentTradePublicationSnapshot,history:InvestmentRetirementHistory):Boolean {
    source.requireCoherent();history.requireValid();require(source.owner==history.owner)
    val assets=history.assets.map{it.id}.toSet()+source.rows.filter{it.entity==CloudEntity.INVESTMENT_ASSET.table &&
        if(history.entity==CloudEntity.INVESTMENT_ASSET)it.id==history.id else it.payload.financeRawString("channel_id")==history.id}.map{it.id}
    val trades=history.trades.map{it.id}.toSet()+source.rows.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.payload.financeRawString("asset_id") in assets}.map{it.id}
    return source.pending.any{q->q.mutation.entity==CloudEntity.INVESTMENT_TRADE && q.mutation.recordId in trades ||
        history.entity==CloudEntity.INVESTMENT_CHANNEL && q.mutation.entity==CloudEntity.INVESTMENT_ASSET && q.mutation.recordId in assets}
}
fun InvestmentRetirementHistory.requireValid() {
    require(financeRawUuid(owner.value)==owner.value && financeRawUuid(id)==id)
    require(entity in setOf(CloudEntity.INVESTMENT_ASSET,CloudEntity.INVESTMENT_CHANNEL))
    require(assets.size<=10000 && trades.size<=10000 && assets.map{it.id}.distinct().size==assets.size && trades.map{it.id}.distinct().size==trades.size)
    for(raw in assets) {
        require(raw.entity==CloudEntity.INVESTMENT_ASSET.table && raw.ownerUserId==owner.value && raw.payload.financeRawString("id")==raw.id &&
            raw.payload.financeRawString("user_id")==owner.value && raw.syncVersion==raw.payload.financeRawLong("sync_version") &&
            raw.updatedAt==raw.payload.financeRawString("updated_at") && raw.financeRawDeleted(true)!=null && raw.deletedAt==raw.payload.financeRawString("deleted_at"))
        require(raw.payload.keys.none{it.startsWith("_mistia_android_")})
        val typed=InvestmentAssetRecord.fromCloudRecord(raw)
        require(if(entity==CloudEntity.INVESTMENT_ASSET)typed.id==id else typed.channelId==id)
    }
    val byId=assets.associateBy{it.id}
    for(trade in trades) {
        requireInvestmentTradeForPublication(owner,trade,forWrite=false,allowLocalEvidence=false)
        require(trade.payload.keys.none{it.startsWith("_mistia_android_")})
        val asset=byId[trade.payload.financeRawString("asset_id")] ?: throw InvestmentRetirementHistoryChanged()
        if(trade.payload.financeRawString("channel_id")!=asset.payload.financeRawString("channel_id") ||
            trade.deletedAt==null && asset.deletedAt!=null)throw InvestmentRetirementHistoryChanged()
    }
}
fun investmentRetirementHistoryIsClosed(history:InvestmentRetirementHistory):Boolean {
    history.requireValid()
    fun instant(raw:String):Instant {
        val parsed=Instant.parse(raw)
        return Instant.ofEpochSecond(parsed.epochSecond,Math.rint(parsed.nano.toDouble()/1000).toLong()*1000)
    }
    return history.trades.filter{it.deletedAt==null}.groupBy{it.payload.financeRawString("asset_id")}.values.all{rows->
        val inputs=rows.map{raw->val p=raw.payload
            InvestmentTradeInput(UUID.fromString(raw.id),if(p.financeRawString("kind_raw_value")=="buy")InvestmentTradeKind.BUY else InvestmentTradeKind.SELL,
                requireNotNull(investmentTradeQuantity(requireNotNull(p.financeRawString("quantity_decimal_string")))),p.financeRawString("unit_label"),
                requireNotNull(p.financeRawLong("accounting_gross_amount_minor")),instant(requireNotNull(p.financeRawString("occurred_at"))),instant(requireNotNull(p.financeRawString("created_at"))))
        }
        try{InvestmentAccountingEngine.projection(inputs).unitPositions.all{it.quantity.signum()==0}}
        catch(_:InvestmentAccountingException){false}
    }
}
