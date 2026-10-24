package vn.com.quyln.mistia.core.model

data class InvestmentTradeEditDraft(val id:String,val assetId:String,val kind:InvestmentTradeKind,val quantity:String,val unit:String,val grossMinor:Long,
    val accountingMinor:Long,val accountingCurrency:String,val sourceRate:String?,val rateProvider:String?,val rateDate:String?,val walletId:String?,val walletMinor:Long?,
    val walletRate:String?,val note:String?,val occurredAt:String,val createdAt:String)
data class InvestmentTradeEditRequest(val expectedTrade:CloudRecord,val draft:InvestmentTradeEditDraft,val expectedAsset:InvestmentAssetRecord,val expectedWallet:LedgerWalletRecord?,
    val consent:InvestmentTradeCreationConsent?,val adjustmentTitle:String)
typealias InvestmentTradeEditPlan=InvestmentTradeCreationPlan
class InvestmentTradeEditConfirmationRequired(val review:InvestmentTradeCreationReview):IllegalStateException("Trade edit fund confirmation required")
fun planInvestmentTradeEdit(snapshot:InvestmentTradeCreationSnapshot,request:InvestmentTradeEditRequest,deviceId:String,now:String):InvestmentTradeEditPlan =
    request.draft.let{d->planInvestmentTradeCreation(snapshot,InvestmentTradeCreationRequest(InvestmentTradeCreationDraft(d.id,d.assetId,d.kind,d.quantity,d.unit,d.grossMinor,
        d.accountingMinor,d.accountingCurrency,d.sourceRate,d.rateProvider,d.rateDate,d.walletId,d.walletMinor,d.walletRate,d.note,d.occurredAt,d.createdAt),
        request.expectedAsset,request.expectedWallet,request.consent,request.adjustmentTitle),deviceId,now,InvestmentTradeWriteIntent.Edit(request.expectedTrade))}
