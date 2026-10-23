package vn.com.quyln.mistia.core.model

data class InvestmentSaleDraft(val id:String,val assetId:String,val quantity:String,val unit:String,val grossMinor:Long,
    val accountingMinor:Long,val accountingCurrency:String,val sourceRate:String?,val rateProvider:String?,val rateDate:String?,
    val capitalWalletId:String?,val accountingToCapitalRate:String?,val note:String?,val occurredAt:String,val createdAt:String)
data class InvestmentSaleRequest(val draft:InvestmentSaleDraft,val expectedAsset:InvestmentAssetRecord,val expectedWallet:LedgerWalletRecord?,
    val consent:InvestmentPurchaseConsent?,val adjustmentTitle:String)
typealias InvestmentSalePlan=InvestmentTradeCreationPlan
typealias InvestmentSaleSnapshot=InvestmentTradeCreationSnapshot
class InvestmentSaleConfirmationRequired(val review:InvestmentPurchaseReview):IllegalStateException("Sale fund changes require confirmation")
fun planInvestmentSale(snapshot:InvestmentPurchaseSnapshot,request:InvestmentSaleRequest,deviceId:String,now:String):InvestmentSalePlan =
    request.draft.let{d->planInvestmentTradeCreation(snapshot,InvestmentTradeCreationRequest(InvestmentTradeCreationDraft(d.id,d.assetId,InvestmentTradeKind.SELL,d.quantity,d.unit,d.grossMinor,
        d.accountingMinor,d.accountingCurrency,d.sourceRate,d.rateProvider,d.rateDate,d.capitalWalletId,null,d.accountingToCapitalRate,d.note,d.occurredAt,d.createdAt),
        request.expectedAsset,request.expectedWallet,request.consent,request.adjustmentTitle),deviceId,now)}
