package vn.com.quyln.mistia.core.sync

import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.*
import vn.com.quyln.mistia.core.model.*

/** Each wallet push owns a separate captured run; concurrent syncs share no response state. */
class WalletInvestmentPrerequisiteCoordinator(private val local:LocalStore,private val remote:WalletInvestmentPrerequisiteRemote,
    private val enabled:Boolean,private val currentSession:()->AuthSession?) {
    internal suspend fun begin(owner:UserId,token:String):WalletInvestmentPrerequisiteRun? {
        if(!enabled)return null
        val caller=currentCoroutineContext();caller.ensureActive();val captured=currentSession()
        if(captured==null || captured.userId!=owner || captured.accessToken!=token || token.isBlank())throw CancellationException("Wallet prerequisite session changed")
        return WalletInvestmentPrerequisiteRun(local,remote,owner,token,captured,currentSession,caller)
    }
}
internal class WalletInvestmentPrerequisiteRun(private val local:LocalStore,private val remote:WalletInvestmentPrerequisiteRemote,
    private val owner:UserId,private val token:String,private val session:AuthSession,private val currentSession:()->AuthSession?,private val caller:CoroutineContext) {
    private val attempts=mutableMapOf<QueuedMutation,InvestmentTradePublicationSnapshot>()
    fun checkCurrent(){caller.ensureActive();if(currentSession()!=session)throw CancellationException("Wallet prerequisite session changed");caller.ensureActive()}
    private suspend fun <T> persist(action:suspend ()->T):T=try{action()}catch(cancelled:CancellationException){throw cancelled}
        catch(error:Exception){throw MutationFailurePersistenceException(error)}
    private suspend fun unchanged(s:InvestmentTradePublicationSnapshot):Boolean {
        checkCurrent();val fresh=persist{local.investmentTradePublicationSnapshot(owner,s.tradeId)};checkCurrent()
        return runCatching{s.requireUnchanged(fresh)}.isSuccess
    }
    suspend fun prepare(s:InvestmentTradePublicationSnapshot,q:QueuedMutation,row:CloudRecord):MutationPreflight {
        checkCurrent();s.requireCoherent();require(s.owner==owner && q in s.pending && s.rows.singleOrNull{it.entity==row.entity && it.id==row.id}==row)
        attempts[q]=s
        val observed=remote.fetchWallet(owner,row.id,token);checkCurrent()
        if(!unchanged(s))return MutationPreflight.Stale
        // A prior own active write may have committed without a usable response.
        if(LOCAL_WALLET_INVESTMENT_PREREQUISITE_KEY in row.payload && observed!=null) {
            val recover=runCatching{planWalletInvestmentPrerequisiteRebase(s,row.id,observed,s)}.getOrNull()
            if(recover!=null) {
                val accepted=persist{local.rebaseWalletInvestmentPrerequisite(s,row.id,observed){currentSession()==session}};checkCurrent()
                return if(accepted)MutationPreflight.Reconciled else MutationPreflight.Stale
            }
        }
        if(observed==null && (row.syncVersion>0 || q.remoteIdentityObserved))return MutationPreflight.Conflict("wallet_prerequisite_missing")
        if(observed!=null) {
            if(observed.deletedAt!=null || observed.payload.financeRawArchived()!=false)return MutationPreflight.Conflict("wallet_prerequisite_remote_inactive")
            if(observed.payload.financeRawString("currency_code")!=row.payload.financeRawString("currency_code"))return MutationPreflight.Conflict("wallet_prerequisite_currency_changed")
            if(observed.syncVersion!=row.syncVersion)return MutationPreflight.Conflict("wallet_prerequisite_remote_changed")
        }
        val preview=runCatching{prepareWalletInvestmentPrerequisite(s,row.id,observed)}.getOrNull() ?: return MutationPreflight.Deferred
        if(!preview.needsWrite && preview.preparedRecord==row)return MutationPreflight.Deferred
        val p=persist{local.prepareWalletInvestmentPrerequisite(s,row.id,observed){currentSession()==session}} ?: return MutationPreflight.Stale
        checkCurrent();attempts[q]=p.preparedSource
        if(!p.needsWrite)return MutationPreflight.Reconciled
        if(!unchanged(p.preparedSource))return MutationPreflight.Stale
        val saved=remote.publishActive(owner,p,token);checkCurrent()
        if(!unchanged(p.preparedSource))return MutationPreflight.Stale
        if(saved==null)return MutationPreflight.Deferred
        val accepted=persist{local.rebaseWalletInvestmentPrerequisite(p.preparedSource,row.id,saved){currentSession()==session}};checkCurrent()
        return if(accepted)MutationPreflight.Reconciled else MutationPreflight.Stale
    }
    suspend fun failure(q:QueuedMutation,next:Long,code:String):Boolean? {
        val s=attempts[q] ?: return null
        checkCurrent();val driver=s.pending.single{it.mutation.entity==CloudEntity.LEDGER_WALLET && it.mutation.recordId==q.mutation.recordId}
        val recorded=local.recordWalletInvestmentPrerequisiteFailure(driver,next,code,s){currentSession()==session};checkCurrent();return recorded
    }
}
