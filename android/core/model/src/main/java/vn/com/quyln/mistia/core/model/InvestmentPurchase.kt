package vn.com.quyln.mistia.core.model

import java.math.BigDecimal
import java.util.Currency

typealias InvestmentPurchaseSnapshot=InvestmentTradeCreationSnapshot
typealias InvestmentPurchaseConsent=InvestmentTradeCreationConsent
typealias InvestmentPurchaseReview=InvestmentTradeCreationReview
typealias InvestmentPurchasePlan=InvestmentTradeCreationPlan
data class InvestmentPurchaseDraft(val id:String,val assetId:String,val quantity:String,val unit:String,val grossMinor:Long,
    val accountingMinor:Long,val accountingCurrency:String,val sourceRate:String?,val rateProvider:String?,val rateDate:String?,
    val fundingWalletId:String?,val fundingMinor:Long?,val fundingToAccountingRate:String?,val note:String?,val occurredAt:String,val createdAt:String)
class InvestmentPurchaseConfirmationRequired(val review:InvestmentPurchaseReview):IllegalStateException("Purchase fund confirmation required")
data class InvestmentPurchaseRequest(val draft:InvestmentPurchaseDraft,val expectedAsset:InvestmentAssetRecord,val expectedWallet:LedgerWalletRecord?,
    val consent:InvestmentPurchaseConsent?,val adjustmentTitle:String)
fun planInvestmentPurchase(snapshot:InvestmentPurchaseSnapshot,request:InvestmentPurchaseRequest,deviceId:String,now:String):InvestmentPurchasePlan {
    val d=request.draft
    return planInvestmentTradeCreation(snapshot,InvestmentTradeCreationRequest(InvestmentTradeCreationDraft(d.id,d.assetId,InvestmentTradeKind.BUY,d.quantity,d.unit,d.grossMinor,
        d.accountingMinor,d.accountingCurrency,d.sourceRate,d.rateProvider,d.rateDate,d.fundingWalletId,d.fundingMinor,d.fundingToAccountingRate,d.note,d.occurredAt,d.createdAt),
        request.expectedAsset,request.expectedWallet,request.consent,request.adjustmentTitle),deviceId,now)
}

fun investmentPurchaseConvertedMinor(amount:Long,source:String,destination:String,rate:String?,inverse:Boolean=false):Long {
    if(source==destination)return amount
    val decimal=rate?.takeIf{it.length<=256}?.toBigDecimalOrNull()?.takeIf{it.signum()>0 && it.scale() in -165..128}
        ?: investmentAssetFail(InvestmentAssetError.MISSING_EXCHANGE_RATE)
    val scale=BigDecimal.ONE.scaleByPowerOfTen(Currency.getInstance(destination).defaultFractionDigits-Currency.getInstance(source).defaultFractionDigits)
    return try {
        if(inverse)InvestmentDecimalMath.proportionalMinor(amount,scale,InvestmentDecimalMath.quantity(decimal))
        else InvestmentDecimalMath.proportionalMinor(amount,InvestmentDecimalMath.quantity(decimal.multiply(scale)),BigDecimal.ONE)
    }catch(_:ArithmeticException){investmentAssetFail(InvestmentAssetError.INVALID_ACCOUNTING)}
}
/** Stored inverse rate uses the same Foundation Decimal arithmetic as the Swift trade form. */
fun investmentPurchaseInverseRate(value:String):String {
    val rate=value.takeIf{it.length<=256}?.toBigDecimalOrNull()?.takeIf{it.signum()>0 && it.scale() in -165..128}
        ?: investmentAssetFail(InvestmentAssetError.MISSING_EXCHANGE_RATE)
    return InvestmentDecimalMath.divide(BigDecimal.ONE,InvestmentDecimalMath.quantity(rate)).toPlainString()
}
