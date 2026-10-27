package vn.com.quyln.mistia.core.model

data class InvestmentCashEventProposal(val transaction:CloudRecord,val posting:CloudRecord)
data class InvestmentCashEventCloudSnapshot(val owner:UserId,val eventId:String,val transaction:CloudRecord?,val postings:List<CloudRecord>,val remoteIntentWinner:Boolean=false)
interface InvestmentCashEventRemote {
    suspend fun fetchEvent(owner:UserId,eventId:String,accessToken:String):InvestmentCashEventCloudSnapshot
    suspend fun mutateEvent(owner:UserId,proposal:InvestmentCashEventProposal,expectedVersion:Long,expectedPostingVersion:Long?,accessToken:String):CloudRecord?
    suspend fun deleteEvent(owner:UserId,eventId:String,expectedVersion:Long,expectedPostingVersion:Long?,modifiedAt:String,deviceId:String,accessToken:String):CloudRecord?
}

/** Existing cash RPC conditions that can change after a fresh wallet/cash pull. */
val INVESTMENT_CASH_EVENT_RETRY_CODES=setOf("investment_cash_limit_conflict","investment_cash_has_dependent_events",
    "investment_cash_linked_wallet_required","investment_cash_invalid_linked_wallet","investment_cash_invalid_wallet",
    "investment_cash_invalid_destination","investment_cash_invalid_source")
