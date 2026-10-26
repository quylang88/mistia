package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.JsonObject
import vn.com.quyln.mistia.core.model.*

/** Closed canonical-root metadata publication; financial queues retain their own RPC domains. */
class InvestmentWalletPushCoordinator(
    private val localStore:LocalStore,private val remoteStore:RemoteMutationStore,private val writesEnabled:Boolean,
    private val currentSession:()->AuthSession?,private val nowEpochMillis:()->Long=System::currentTimeMillis,
):DomainPushCoordinator {
    override val entity=CloudEntity.LEDGER_WALLET
    override suspend fun pushPending(ownerUserId:UserId,accessToken:String):DomainPushSummary {
        if(!writesEnabled)return DomainPushSummary()
        val caller=currentCoroutineContext();caller.ensureActive()
        val captured=currentSession()
        if(captured==null || captured.userId!=ownerUserId || captured.accessToken!=accessToken || accessToken.isBlank())
            throw CancellationException("Investment wallet session changed")
        fun checkSession() {
            caller.ensureActive()
            if(currentSession()!=captured)throw CancellationException("Investment wallet session changed")
            caller.ensureActive()
        }
        var source:InvestmentWalletPublicationSnapshot?=null
        var remote:CloudRecord?=null
        fun sameCurrency(local:CloudRecord,server:CloudRecord)=
            canonicalInvestmentWalletForPublication(ownerUserId,local).currencyCode==canonicalInvestmentWalletForPublication(ownerUserId,server).currencyCode
        fun equalMetadata(local:CloudRecord,server:CloudRecord):Boolean {
            val current=canonicalInvestmentWalletForPublication(ownerUserId,server)
            return !current.isArchived && server.deletedAt==null && local.deletedAt==null && sameCurrency(local,server) &&
                ConflictResolver.semanticFingerprint(investmentWalletMetadataForComparison(local.payload))==
                ConflictResolver.semanticFingerprint(investmentWalletMetadataForComparison(server.payload))
        }
        suspend fun preflight(q:QueuedMutation,row:CloudRecord,beforeWrite:Boolean):MutationPreflight {
            checkSession()
            val fresh=localStore.investmentWalletPublicationSnapshot(ownerUserId)
            checkSession()
            if(!fresh.matches(q) || fresh.record!=row)return MutationPreflight.Stale
            source=fresh
            when(fresh.dependency()) {
                InvestmentWalletPublicationDependency.WAITING_FOR_LINKED_WALLET->return MutationPreflight.Deferred
                InvestmentWalletPublicationDependency.INVALID_LINK->return MutationPreflight.Conflict("investment_wallet_invalid_link")
                InvestmentWalletPublicationDependency.UNREADABLE_SOURCE->return MutationPreflight.Conflict("investment_wallet_unreadable_source")
                InvestmentWalletPublicationDependency.READY->Unit
            }
            if(beforeWrite && remote?.let{!sameCurrency(row,it)}==true)
                return MutationPreflight.Conflict("investment_wallet_currency_changed")
            return MutationPreflight.Continue
        }
        val scoped=object:LocalStore by localStore {
            override suspend fun pendingMutations(ownerUserId:UserId,entity:CloudEntity,dueAtEpochMillis:Long,limit:Int):List<QueuedMutation> {
                checkSession();require(ownerUserId==captured.userId && entity==CloudEntity.LEDGER_WALLET && limit>0)
                val current=localStore.investmentWalletPublicationSnapshot(ownerUserId)
                checkSession();source=current
                return listOfNotNull(current.pending).filter{it.nextAttemptAtEpochMillis<=dueAtEpochMillis}
            }
        }
        val adapter=object:RemoteMutationStore {
            override suspend fun fetchRecord(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId):CloudRecord? {
                checkSession()
                val result=remoteStore.fetchRecord(entity,recordId,accessToken,ownerUserId)
                checkSession()
                result?.let{require(LOCAL_INVESTMENT_WALLET_PARENTS_KEY !in it.payload);canonicalInvestmentWalletForPublication(ownerUserId,it)}
                remote=result
                return result
            }
            override suspend fun createRecord(entity:CloudEntity,accessToken:String,ownerUserId:UserId,payload:JsonObject):CloudRecord {
                checkSession()
                val sent=investmentWalletPayloadForCloud(payload)
                val result=remoteStore.createRecord(entity,accessToken,ownerUserId,sent)
                checkSession();validateWriteReply(ownerUserId,sent,result)
                localStore.recordInvestmentWalletPublicationReceipt(requireNotNull(source?.pending),sent,0,result,{currentSession()==captured})
                checkSession();return result
            }
            override suspend fun conditionalUpdate(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId,expectedVersion:Long,payload:JsonObject):CloudRecord? {
                checkSession()
                val sent=investmentWalletPayloadForCloud(payload)
                val result=remoteStore.conditionalUpdate(entity,recordId,accessToken,ownerUserId,expectedVersion,sent)
                checkSession()
                if(result!=null) {
                    validateWriteReply(ownerUserId,sent,result)
                    localStore.recordInvestmentWalletPublicationReceipt(requireNotNull(source?.pending),sent,expectedVersion,result,{currentSession()==captured})
                }
                checkSession();return result
            }
        }
        val delegate=OutboxPushCoordinator(entity,scoped,adapter,writesEnabled,nowEpochMillis,
            validateRecord={canonicalInvestmentWalletForPublication(ownerUserId,it);localInvestmentWalletPublicationParents(it)},
            normalizeSemanticPayload=::investmentWalletMetadataForComparison,
            preferRemoteRecord={_,local,server->equalMetadata(local,server)},
            conflictDecisionOverride={local,server->
                val serverWallet=canonicalInvestmentWalletForPublication(ownerUserId,server)
                when {
                    !sameCurrency(local,server)->ConflictDecision(ConflictWinner.UNRESOLVED,"investment_wallet_currency_changed")
                    serverWallet.isArchived || server.deletedAt!=null->ConflictDecision(ConflictWinner.LOCAL,"canonical_investment_wallet_active")
                    isKnownPriorInvestmentWalletPublication(local,server,requireNotNull(deviceId(source)))->ConflictDecision(ConflictWinner.LOCAL,"own_prior_investment_wallet_publication")
                    server.payload.financeRawString("last_modified_by_device_id")==deviceId(source) &&
                        !equalMetadata(local,server) && ConflictResolver.resolve(local,server).winner==ConflictWinner.REMOTE->
                        ConflictDecision(ConflictWinner.UNRESOLVED,"investment_wallet_unproven_own_publication")
                    else->null
                }
            },preflight={q,row,_,_->preflight(q,row,false)},beforeRemoteWrite={q,row,_,_->preflight(q,row,true)},
            acknowledgeOverride={q,server->
                checkSession()
                val accepted=localStore.acknowledgeInvestmentWalletMutation(q,server,requireNotNull(source),{currentSession()==captured})
                checkSession()
                if(accepted)MutationAcknowledgement.Committed else MutationAcknowledgement.Stale
            },recordFailureOverride={q,next,code->
                checkSession()
                val accepted=localStore.recordInvestmentWalletMutationFailure(q,next,code,requireNotNull(source),{currentSession()==captured})
                checkSession();accepted
            })
        return delegate.pushPending(ownerUserId,accessToken).also{checkSession()}
    }
    private fun validateWriteReply(owner:UserId,sent:JsonObject,result:CloudRecord) {
        require(LOCAL_INVESTMENT_WALLET_PARENTS_KEY !in result.payload)
        val wallet=canonicalInvestmentWalletForPublication(owner,result,forWrite=true)
        require(wallet.currencyCode==sent.financeRawString("currency_code")?.financeReportingCode() && result.syncVersion==sent.financeRawLong("sync_version"))
    }
    private fun deviceId(source:InvestmentWalletPublicationSnapshot?)=source?.pending?.mutation?.deviceId
}
