package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.time.Instant
import java.util.Currency
import kotlinx.serialization.json.JsonNull

/** Matches Swift's linked-wallet/alive cash-metadata guard, without overflowing accounting sums. */
fun walletHasProtectedInvestmentCash(owner:UserId,walletId:String,rows:List<CloudRecord>):Boolean {
    require(financeRawUuid(owner.value)==owner.value && financeRawUuid(walletId)==walletId)
    val entities=setOf(CloudEntity.LEDGER_WALLET,CloudEntity.INVESTMENT_POSTING)
    require(rows.map{it.entity to it.id}.distinct().size==rows.size)
    for(row in rows) {
        val entity=requireNotNull(CloudEntity.fromTable(row.entity))
        require(entity in entities && financeRawUuid(row.id)==row.id && row.financeRawIdentity(owner,entity,true))
        val body=row.payload["deleted_at"]
        require(body==null || body==JsonNull || row.payload.financeRawString("deleted_at")!=null)
        require(row.deletedAt==row.payload.financeRawString("deleted_at"))
        row.deletedAt?.let{Instant.parse(it)}
    }
    val rootId=investmentSystemWalletId(owner)
    val roots=rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table && (it.id==rootId || it.payload.financeRawString("system_purpose_raw_value")=="investmentProfit")}
    require(roots.size<=1)
    val root=roots.singleOrNull()
    val linked=root?.let{row->
        require(row.id==rootId && row.payload.financeRawString("kind_raw_value")=="investment" && row.payload.financeRawString("system_purpose_raw_value")=="investmentProfit" && row.deletedAt==null && row.payload.financeRawArchived()==false)
        row.payload.financeRawReference("investment_linked_wallet_id").also{require(it.readable)}.id
    }
    if(linked==walletId)return true
    val totals=mutableMapOf<String,BigInteger>()
    for(row in rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table}) {
        val p=row.payload;val ref=p.financeRawReference("wallet_id");require(ref.readable && ref.id!=null)
        if(ref.id!=walletId || row.deletedAt!=null)continue
        if(p["cash_bucket_raw_value"]==null || p["cash_bucket_raw_value"]==JsonNull) {
            // Legacy noncash FIFO postings carry no cash-location metadata.
            require(p.financeRawString("role_raw_value") in setOf("funding","capitalReturn","realizedProfit","transferOut","transferIn"))
            continue
        }
        require(p.financeRawString("cash_bucket_raw_value") in setOf("booked","unreconciled") &&
            p.financeRawString("role_raw_value") in setOf("cashAccrual","cashReconciliation","cashConsumption","cashTransfer","cashCorrection") &&
            p.financeRawString("cash_origin_raw_value") in setOf("manual","derived","inferred"))
        val amount=requireNotNull(p.financeRawLong("accounting_amount_minor"))
        val code=requireNotNull(p.financeRawString("accounting_currency_code"))
        require(code.financeReportingCode()==code && Currency.getInstance(code).defaultFractionDigits>=0)
        totals[code]=(totals[code] ?: BigInteger.ZERO)+BigInteger.valueOf(amount)
    }
    // Different accounting units must never cancel one another into a false zero.
    return totals.values.any{it.signum()!=0}
}

/** Only financial shape/state changes need the allocation guard; names, icons and notes remain editable. */
fun walletMutationNeedsInvestmentProtection(previous:CloudRecord,proposed:CloudRecord):Boolean {
    require(previous.entity==CloudEntity.LEDGER_WALLET.table && proposed.entity==previous.entity && previous.ownerUserId==proposed.ownerUserId && previous.id==proposed.id)
    return previous.payload.financeRawString("kind_raw_value")!=proposed.payload.financeRawString("kind_raw_value") ||
        previous.payload.financeRawString("currency_code")?.financeReportingCode()!=proposed.payload.financeRawString("currency_code")?.financeReportingCode() ||
        (previous.payload.financeRawArchived()!=true && proposed.payload.financeRawArchived()==true) ||
        (previous.deletedAt==null && proposed.deletedAt!=null)
}
