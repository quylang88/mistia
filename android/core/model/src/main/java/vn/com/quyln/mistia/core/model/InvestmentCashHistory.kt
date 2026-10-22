package vn.com.quyln.mistia.core.model

import java.math.BigDecimal
import java.math.BigInteger
import java.time.Instant
import kotlinx.serialization.json.*

enum class InvestmentCashHistoryKind { REALIZED_PROFIT, LIQUIDATION, DEPOSIT, WITHDRAWAL, SPENDING, MOVEMENT, ADJUSTMENT }
enum class InvestmentCashHistoryFilter { ALL, INCOMING, OUTGOING, MOVEMENT }
data class InvestmentCashHistoryItem(val id:String,val kind:InvestmentCashHistoryKind,val occurredAt:String,
    val accountingAmountMinor:BigInteger,val accountingCurrencyCode:String,val sourceWalletId:String?,val destinationWalletId:String?,
    val ledgerTransactionId:String?,val tradeId:String?,val assetId:String?,val title:String?,val grossAmountMinor:Long?,val grossCurrencyCode:String?,val isEditable:Boolean) {
    val filter:InvestmentCashHistoryFilter get()=when(kind) {
        InvestmentCashHistoryKind.REALIZED_PROFIT,InvestmentCashHistoryKind.DEPOSIT -> if(accountingAmountMinor.signum()>=0)InvestmentCashHistoryFilter.INCOMING else InvestmentCashHistoryFilter.OUTGOING
        InvestmentCashHistoryKind.LIQUIDATION,InvestmentCashHistoryKind.WITHDRAWAL,InvestmentCashHistoryKind.SPENDING -> InvestmentCashHistoryFilter.OUTGOING
        InvestmentCashHistoryKind.MOVEMENT -> InvestmentCashHistoryFilter.MOVEMENT
        InvestmentCashHistoryKind.ADJUSTMENT -> when(accountingAmountMinor.signum()) {1->InvestmentCashHistoryFilter.INCOMING;-1->InvestmentCashHistoryFilter.OUTGOING;else->InvestmentCashHistoryFilter.MOVEMENT}
    }
}

/** Same owned four-entity financial snapshot used by the cash summary and forms. */
fun investmentCashHistory(snapshot:InvestmentCashReadSnapshot,accountingCurrencyCode:String,limit:Int?=null):List<InvestmentCashHistoryItem> {
    snapshot.requireScoped()
    val code=investmentAssetCurrency(accountingCurrencyCode) ?: throw InvestmentCashReadException(InvestmentCashReadError.INVALID_CURRENCY)
    fun active(entity:CloudEntity)=snapshot.rows.filter{it.entity==entity.table}.filter{
        when(it.financeRawDeleted(true)){true->false;false->true;null->historyUnreadable()}
    }
    val transactions=active(CloudEntity.LEDGER_TRANSACTION).associateBy{it.id}
    val trades=active(CloudEntity.INVESTMENT_TRADE).map{historyTrade(it,code)}.associateBy{it.id}
    val postings=active(CloudEntity.INVESTMENT_POSTING).mapNotNull{raw ->
        val p=raw.payload
        val role=p.historyText("role_raw_value")
        if(role !in setOf("funding","capitalReturn","realizedProfit","transferOut","transferIn","cashAccrual","cashTransfer","cashConsumption","cashReconciliation","cashCorrection"))historyUnreadable()
        val bucket=p.historyOptional("cash_bucket_raw_value")
        if(bucket!=null && bucket !in setOf("booked","unreconciled"))historyUnreadable()
        if(bucket==null && role !in setOf("transferOut","transferIn")) {
            if(role !in setOf("funding","capitalReturn","realizedProfit"))historyUnreadable()
            null
        } else {
            val currency=p.historyText("currency_code").let(::investmentAssetCurrency) ?: historyUnreadable()
            val accounting=p.historyText("accounting_currency_code").let(::investmentAssetCurrency) ?: historyUnreadable()
            val local=p.historyMinor("amount_minor");val amount=p.historyMinor("accounting_amount_minor")
            if(accounting!=code || (currency==accounting && local!=amount))historyUnreadable()
            HistoryPosting(raw.id,p.historyReference("event_id") ?: historyUnreadable(),p.historyReference("ledger_transaction_id") ?: historyUnreadable(),
                p.historyReference("trade_id"),p.historyReference("wallet_id") ?: historyUnreadable(),role,bucket!=null,BigInteger.valueOf(amount),p.historyInstant("occurred_at"))
        }
    }
    val funding=historySaleFunding(trades.values.toList())
    val events=postings.groupBy{it.eventId}.map{(id,values)->Triple(id,values.sortedBy{it.id},values.maxOf{it.occurredAt})}
        .sortedWith(compareByDescending<Triple<String,List<HistoryPosting>,Instant>>{it.third}.thenBy{it.first})
    return (if(limit==null)events else events.take(limit.coerceAtLeast(0))).map{(event,values,occurredAt)->
        val latest=values.last{it.occurredAt==occurredAt}
        val transaction=transactions[latest.ledgerId];val p=transaction?.payload
        val role=p?.historyOptional("settlement_role_raw_value")
        val trade=values.firstNotNullOfOrNull{it.tradeId?.let(trades::get)} ?: trades[event]
        val cash=values.filter{it.cash}
        val net=cash.fold(BigInteger.ZERO){sum,it ->sum+it.amount}
        val sourcePosting=cash.firstOrNull{it.amount.signum()<0};val destinationPosting=cash.firstOrNull{it.amount.signum()>0}
        val kind:InvestmentCashHistoryKind;val amount:BigInteger
        when {
            trade?.kind=="sell" && cash.any{it.role=="cashAccrual"} -> {
                if(trade.gross==0L && trade.profit<0){kind=InvestmentCashHistoryKind.LIQUIDATION;amount=BigInteger.valueOf(trade.profit).abs().negate()}
                else {kind=InvestmentCashHistoryKind.REALIZED_PROFIT;amount=net}
            }
            role=="investmentCashDeposit"->{kind=InvestmentCashHistoryKind.DEPOSIT;amount=net.abs()}
            role=="investmentCashWithdrawal"->{kind=InvestmentCashHistoryKind.WITHDRAWAL;amount=net.abs().negate()}
            cash.any{it.role=="cashConsumption"}->{kind=InvestmentCashHistoryKind.SPENDING;amount=net.abs().negate()}
            cash.size>1 && net.signum()==0->{kind=InvestmentCashHistoryKind.MOVEMENT;amount=cash.maxOf{it.amount.abs()}}
            values.any{it.role=="transferOut"}->{kind=InvestmentCashHistoryKind.WITHDRAWAL;amount=values.fold(BigInteger.ZERO){sum,it->sum+it.amount}.abs().negate()}
            values.any{it.role=="transferIn"}->{kind=InvestmentCashHistoryKind.DEPOSIT;amount=values.fold(BigInteger.ZERO){sum,it->sum+it.amount}.abs()}
            else->{kind=InvestmentCashHistoryKind.ADJUSTMENT;amount=net}
        }
        val source=if(trade?.kind=="sell")funding[trade.id] ?: trade.fundingWallet else p?.historyReference("source_wallet_id") ?: sourcePosting?.walletId
        val destination=if(trade?.kind=="sell")trade.capitalWallet else p?.historyReference("destination_wallet_id") ?: destinationPosting?.walletId
        InvestmentCashHistoryItem(event,kind,occurredAt.toString(),amount,code,source,destination,transaction?.id ?: latest.ledgerId,trade?.id,trade?.assetId,
            p?.historyOptional("title"),trade?.gross,trade?.currency,role in setOf("investmentCashDeposit","investmentCashWithdrawal"))
    }
}
fun filterInvestmentCashHistory(items:List<InvestmentCashHistoryItem>,filter:InvestmentCashHistoryFilter):List<InvestmentCashHistoryItem> =
    if(filter==InvestmentCashHistoryFilter.ALL)items else items.filter{it.filter==filter}

private data class HistoryPosting(val id:String,val eventId:String,val ledgerId:String,val tradeId:String?,val walletId:String,val role:String,val cash:Boolean,val amount:BigInteger,val occurredAt:Instant)
private data class HistoryTrade(val id:String,val assetId:String,val kind:String,val quantity:BigDecimal,val unit:String?,val fundingWallet:String?,val capitalWallet:String?,
    val occurredAt:Instant,val createdAt:Instant,val profit:Long,val gross:Long,val currency:String)
private fun historyUnreadable():Nothing=throw InvestmentCashReadException(InvestmentCashReadError.UNREADABLE_SOURCE)
private fun JsonObject.historyText(key:String)=financeRawString(key) ?: historyUnreadable()
private fun JsonObject.historyOptional(key:String):String?=if(this[key]==null || this[key]==JsonNull)null else historyText(key)
private fun JsonObject.historyReference(key:String)=financeRawReference(key).let{if(!it.readable)historyUnreadable() else it.id}
private fun JsonObject.historyMinor(key:String)=financeRawLong(key) ?: historyUnreadable()
private fun JsonObject.historyInstant(key:String)=runCatching{Instant.parse(historyText(key))}.getOrElse{historyUnreadable()}
private fun historyTrade(raw:CloudRecord,accountingCode:String):HistoryTrade {
    val p=raw.payload
    if(p.historyText("accounting_currency_code").let(::investmentAssetCurrency)!=accountingCode)historyUnreadable()
    return HistoryTrade(raw.id,p.historyReference("asset_id") ?: historyUnreadable(),p.historyText("kind_raw_value").takeIf{it in setOf("buy","sell")} ?: historyUnreadable(),
        runCatching{InvestmentDecimalMath.quantity(p.historyText("quantity_decimal_string").toBigDecimal())}.getOrElse{historyUnreadable()},p.historyOptional("unit_label"),
        p.historyReference("funding_wallet_id"),p.historyReference("capital_return_wallet_id"),p.historyInstant("occurred_at"),p.historyInstant("created_at"),
        p.historyMinor("realized_profit_loss_minor"),p.historyMinor("gross_amount_minor").takeIf{it>=0} ?: historyUnreadable(),
        p.historyText("currency_code").let(::investmentAssetCurrency) ?: historyUnreadable())
}
private fun historySaleFunding(trades:List<HistoryTrade>):Map<String,String> {
    data class Lot(val unit:String,val wallet:String?,var remaining:BigDecimal)
    val result=mutableMapOf<String,String>()
    for(assetTrades in trades.groupBy{it.assetId}.values) {
        val lots=mutableListOf<Lot>()
        for(trade in assetTrades.sortedWith(compareBy(HistoryTrade::occurredAt,HistoryTrade::createdAt,HistoryTrade::id))) {
            if(trade.quantity.signum()<=0)continue
            val unit=InvestmentUnitLabel.comparisonKey(trade.unit)
            if(trade.kind=="buy")lots+=Lot(unit,trade.fundingWallet,trade.quantity)
            else {
                var remaining=trade.quantity;var matched:String?=null
                for(lot in lots) {
                    if(remaining.signum()<=0)break
                    if(lot.remaining.signum()>0 && lot.unit==unit) {
                        val deducted=remaining.min(lot.remaining)
                        if(matched==null)matched=lot.wallet
                        lot.remaining=InvestmentDecimalMath.subtract(lot.remaining,deducted);remaining=InvestmentDecimalMath.subtract(remaining,deducted)
                    }
                }
                if(matched!=null)result[trade.id]=matched
            }
        }
    }
    return result
}
