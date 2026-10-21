package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.saveable.listSaver
import java.time.YearMonth
import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Currency
import java.util.UUID
import vn.com.quyln.mistia.core.model.*

fun eligibleBillPaymentWallets(owner:String,currency:String,wallets:List<LedgerWalletRecord>):List<LedgerWalletRecord> = wallets.filter {
    it.ownerUserId==owner && !it.isArchived && it.deletedAt==null && it.kind!=null && it.kind!=WalletKind.INVESTMENT && billPaymentCurrenciesMatch(currency,it.currencyCode)
}.sortedWith(compareBy(LedgerWalletRecord::sortOrder,LedgerWalletRecord::name,LedgerWalletRecord::id))

data class BillPaymentState(val owner:String,val billId:String,val month:String,val currency:String,val walletId:String?,val amountText:String="") {
    fun request(row:RecurringBillDueRow,wallets:List<LedgerWalletRecord>):BillPaymentRequest {
        require(row.bill.id==billId && row.bill.ownerUserId==owner && !row.bill.isArchived && row.bill.deletedAt==null && row.status==DueStatus.PENDING)
        if(!billPaymentCurrenciesMatch(currency,row.bill.currencyCode)) throw BillPaymentException(BillPaymentError.WALLET_CURRENCY_MISMATCH)
        val wallet=eligibleBillPaymentWallets(owner,row.bill.currencyCode,wallets).firstOrNull {it.id==walletId}
            ?: throw BillPaymentException(BillPaymentError.INVALID_WALLET)
        val amount=if(row.amountMinor!=null) null else runCatching {
            BigDecimal(amountText.trim().replace(",",""))
                .movePointRight(Currency.getInstance(currency).defaultFractionDigits.coerceAtLeast(0))
                .setScale(0,RoundingMode.UNNECESSARY).longValueExact()
        }.getOrElse {throw BillPaymentException(BillPaymentError.MISSING_AMOUNT)}
        if((amount ?: row.amountMinor ?: 0)<=0) throw BillPaymentException(BillPaymentError.MISSING_AMOUNT)
        return BillPaymentRequest(RecordId(billId),YearMonth.parse(month),RecordId(wallet.id),amount ?: row.amountMinor,expectedBill=row.bill,expectedDueAmountMinor=row.amountMinor)
    }
    companion object {
        fun initial(owner:String,row:RecurringBillDueRow,month:YearMonth,wallets:List<LedgerWalletRecord>) =
            BillPaymentState(owner,row.bill.id,month.toString(),row.bill.currencyCode,eligibleBillPaymentWallets(owner,row.bill.currencyCode,wallets).firstOrNull {it.id==row.bill.paymentWalletId}?.id)
        fun saver(owner:String,billId:String,month:String)=listSaver<BillPaymentState,Any>(
            save={listOf(it.owner,it.billId,it.month,it.currency,it.walletId.orEmpty(),it.amountText)},
            restore={values -> runCatching {
                if(values.size!=6 || values[0]!=owner || values[1]!=billId || values[2]!=month) return@runCatching null
                BillPaymentState(owner,billId,month,values[3] as String,(values[4] as String).ifEmpty {null},values[5] as String)
            }.getOrNull()})
    }
}


data class BillPaymentNavigation(val owner:String,val billId:String?,val month:String,val undo:Boolean=false) {
    companion object {
        fun saver(owner:String)=listSaver<BillPaymentNavigation,Any>(
            save={listOf(it.owner,it.billId.orEmpty(),it.month,it.undo)},
            restore={values -> runCatching {
                if(values.size!=4 || values[0]!=owner) return@runCatching null
                val id=(values[1] as String).ifEmpty {null}?.let {UUID.fromString(it).toString()}
                BillPaymentNavigation(owner,id,YearMonth.parse(values[2] as String).toString(),values[3] as Boolean)
            }.getOrNull()})
    }
}
