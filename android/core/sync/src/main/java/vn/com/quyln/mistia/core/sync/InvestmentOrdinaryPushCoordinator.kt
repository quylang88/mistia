package vn.com.quyln.mistia.core.sync

import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.*
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.network.SupabaseHttpException

/** Publishes the ordinary ledger and its complete confirmed investment allocation together. */
class InvestmentOrdinaryPushCoordinator(
    private val localStore:LocalStore,
    private val remote:InvestmentOrdinaryRemote,
    private val writesEnabled:Boolean,
    private val currentSession:()->AuthSession?,
    private val nowEpochMillis:()->Long=System::currentTimeMillis,
):DomainPushCoordinator {
    override val entity=CloudEntity.INVESTMENT_POSTING
    override suspend fun pushPending(ownerUserId:UserId,accessToken:String):DomainPushSummary {
        if(!writesEnabled)return DomainPushSummary()
        val caller=currentCoroutineContext();caller.ensureActive();val captured=currentSession()
        if(captured==null || captured.userId!=ownerUserId || captured.accessToken!=accessToken || accessToken.isBlank())throw CancellationException("Ordinary session changed")
        fun checkCurrent(){caller.ensureActive();if(currentSession()!=captured)throw CancellationException("Ordinary session changed");caller.ensureActive()}
        suspend fun <T> persist(action:suspend ()->T):T=try{action()}catch(cancelled:CancellationException){throw cancelled}
            catch(error:Exception){throw PersistenceFailure(error)}
        suspend fun source(id:String):InvestmentOrdinaryPublicationSnapshot {
            checkCurrent();val s=localStore.investmentOrdinaryPublicationSnapshot(ownerUserId,id);checkCurrent()
            require(s.owner==ownerUserId && s.eventId==id);s.requireCoherent();return s
        }
        suspend fun unchanged(s:InvestmentOrdinaryPublicationSnapshot):Boolean=runCatching{s.requireUnchanged(persist{source(s.eventId)})}.fold({true},{e->
            if(e is CancellationException || e is PersistenceFailure)throw e;false
        })
        val now=nowEpochMillis();require(now>=0);var total=DomainPushSummary()
        val initial=source("00000000-0000-0000-0000-000000000000")
        for(id in investmentOrdinaryPublicationCandidates(initial)) {
            checkCurrent();var s=source(id)
            var group=runCatching{investmentOrdinaryPublicationGroup(s)}.getOrNull() ?: continue
            if(group.queues.isEmpty() || group.queues.any{it.nextAttemptAtEpochMillis>now})continue
            var driver=group.queues.singleOrNull{it.mutation.entity==CloudEntity.LEDGER_TRANSACTION && it.mutation.recordId==id}
                ?: group.queues.minBy{it.mutation.recordId}
            if(driver !in initial.pending){total=total.copy(staleResponses=total.staleResponses+1);continue}
            val driverKey=driver.mutation.entity.table to driver.mutation.recordId
            try {
                if(!ready(s,group))continue
                checkCurrent();val observed=remote.fetchEvent(ownerUserId,id,accessToken);checkCurrent()
                if(!unchanged(s)){total=total.copy(staleResponses=total.staleResponses+1);continue}
                val observedResult=observed.transaction?.let{InvestmentOrdinaryPublicationResult(observed.owner,observed.eventId,it,observed.adjustment,observed.postings)}
                if(observedResult!=null && runCatching{planInvestmentOrdinaryAcknowledgement(s,observedResult)}.isSuccess) {
                    val accepted=persist{localStore.acknowledgeInvestmentOrdinaryResult(s,observedResult){currentSession()==captured}};checkCurrent()
                    total=if(accepted)total.copy(acknowledged=total.acknowledged+1)else total.copy(staleResponses=total.staleResponses+1)
                    continue
                }
                if(runCatching{planInvestmentOrdinaryRebase(s,observed)}.isFailure) {
                    planInvestmentOrdinaryConflict(s,observed)
                    val resolved=persist{localStore.resolveInvestmentOrdinaryConflict(s,observed){currentSession()==captured}}
                        ?: run{total=total.copy(staleResponses=total.staleResponses+1);continue}
                    checkCurrent()
                    when(resolved) {
                        is InvestmentOrdinaryConflictPlan.Remote->{total=total.copy(reconciled=total.reconciled+1);continue}
                        is InvestmentOrdinaryConflictPlan.Unresolved->{total=total.copy(conflicts=total.conflicts+1);continue}
                        is InvestmentOrdinaryConflictPlan.Local->s=persist{source(id)}
                    }
                } else {
                    s=persist{localStore.rebaseInvestmentOrdinaryPublication(s,observed){currentSession()==captured}}
                        ?: run{total=total.copy(staleResponses=total.staleResponses+1);continue}
                }
                checkCurrent();group=investmentOrdinaryPublicationGroup(s)
                driver=s.pending.single{it.mutation.entity.table to it.mutation.recordId==driverKey}
                if(!ready(s,group))continue
                if(hasUnresolvedRelatedSource(s,group))continue
                if(!canPublishFinancialSource(s,group,observed,now)) {
                    val retained=persist{localStore.recordInvestmentOrdinaryFailure(driver,Long.MAX_VALUE,"ordinary_paid_source_locked",s){currentSession()==captured}}
                    checkCurrent()
                    total=if(retained)total.copy(conflicts=total.conflicts+1)else total.copy(staleResponses=total.staleResponses+1)
                    continue
                }
                val date=Instant.ofEpochMilli(now).toString()
                planInvestmentOrdinaryPreparation(s,driver.mutation.deviceId,date)
                s=persist{localStore.prepareInvestmentOrdinaryPublication(s,driver.mutation.deviceId,date){currentSession()==captured}}
                    ?: run{total=total.copy(staleResponses=total.staleResponses+1);continue}
                checkCurrent();group=investmentOrdinaryPublicationGroup(s)
                driver=s.pending.single{it.mutation.entity.table to it.mutation.recordId==driverKey}
                if(!ready(s,group))continue
                if(!unchanged(s)){total=total.copy(staleResponses=total.staleResponses+1);continue}
                checkCurrent();val result=remote.publish(s,accessToken);checkCurrent()
                if(!unchanged(s)){total=total.copy(staleResponses=total.staleResponses+1);continue}
                planInvestmentOrdinaryAcknowledgement(s,result)
                val accepted=persist{localStore.acknowledgeInvestmentOrdinaryResult(s,result){currentSession()==captured}};checkCurrent()
                total=if(accepted)total.copy(pushed=total.pushed+1)else total.copy(staleResponses=total.staleResponses+1)
            }catch(cancelled:CancellationException){throw cancelled}
            catch(error:Exception) {
                if(error is PersistenceFailure)throw error.failure
                checkCurrent()
                val retry=when(error){is SupabaseHttpException->error.statusCode>=500 || error.statusCode in setOf(408,409,429) || error.statusCode==400 && error.serviceCode in INVESTMENT_ORDINARY_RETRY_CODES;is IOException->true;else->false}
                val code=when(error){is SupabaseHttpException->error.serviceCode?.takeIf{error.statusCode==400 && it in INVESTMENT_ORDINARY_RETRY_CODES} ?: "http_${error.statusCode}";is IOException->"network_io";is Conflict->"ordinary_conflict_${error.reason}";else->"invalid_ordinary_publication"}
                val delay=minOf(30_000L*(1L shl driver.attemptCount.coerceIn(0,10)),21_600_000L)
                val next=if(retry && now<=Long.MAX_VALUE-delay)now+delay else Long.MAX_VALUE
                val recorded=localStore.recordInvestmentOrdinaryFailure(driver,next,code,s){currentSession()==captured};checkCurrent()
                total=when{!recorded->total.copy(staleResponses=total.staleResponses+1);error is Conflict->total.copy(conflicts=total.conflicts+1)
                    retry->total.copy(retryableFailures=total.retryableFailures+1);else->total.copy(permanentFailures=total.permanentFailures+1)}
            }
        }
        checkCurrent();return total
    }
    private fun hasUnresolvedRelatedSource(s:InvestmentOrdinaryPublicationSnapshot,g:InvestmentOrdinaryPublicationGroup):Boolean {
        fun wallets(group:InvestmentOrdinaryPublicationGroup)=(group.rows.mapNotNull{it.payload.financeRawString("wallet_id")}+
            listOfNotNull(group.primary.payload.financeRawString("source_wallet_id"),group.primary.payload.financeRawString("destination_wallet_id"))).toSet()-investmentSystemWalletId(s.owner)
        val current=wallets(g)
        return investmentOrdinaryPublicationCandidates(s).filter{it!=s.eventId}.any{id->
            val related=investmentOrdinaryPublicationGroup(s.copy(eventId=id))
            val stored=s.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id}
            val locked=stored.payload.containsKey(LOCAL_ORDINARY_CONFLICT_KEY) ||
                related.queues.any{it.lastError=="ordinary_paid_source_locked"}
            locked && wallets(related).any{it in current}
        }
    }
    private fun canPublishFinancialSource(s:InvestmentOrdinaryPublicationSnapshot,g:InvestmentOrdinaryPublicationGroup,
        observed:InvestmentOrdinaryCloudSnapshot,now:Long):Boolean {
        val remote=observed.transaction
        // Completing the same ledger's allocation does not edit a paid source.
        if(remote!=null && !ordinaryPublicationHasFinancialDifferences(g.primary,remote))return true
        fun clean(entity:CloudEntity)=s.rows.filter{it.entity==entity.table && it.deletedAt==null && it.entity to it.id !in s.dirtyKeys}
        val transactions=clean(CloudEntity.LEDGER_TRANSACTION).filterNot{it.id==g.primary.id}+
            listOfNotNull(remote?.takeIf{it.deletedAt==null})
        return listOfNotNull(remote,g.primary).none{candidate->LedgerTransactionRecord.fromCloudRecord(candidate).isLockedByPaidCreditCardStatement(
            s.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table && it.deletedAt==null}.map(LedgerWalletRecord::fromCloudRecord),
            s.rows.filter{it.entity==CloudEntity.CREDIT_CARD_PROFILE.table && it.deletedAt==null}.map(CreditCardProfileRecord::fromCloudRecord),
            s.rows.filter{it.entity==CloudEntity.TRANSACTION_CATEGORY.table && it.deletedAt==null}.map(TransactionCategoryRecord::fromCloudRecord),
            transactions.map(LedgerTransactionRecord::fromCloudRecord),clean(CloudEntity.DUE_OCCURRENCE_RECORD),referenceDate=Instant.ofEpochMilli(now))}
    }
    private fun ready(s:InvestmentOrdinaryPublicationSnapshot,g:InvestmentOrdinaryPublicationGroup):Boolean=runCatching {
        val wallets=s.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table}.associateBy{it.id}
        val rootId=investmentSystemWalletId(s.owner);val root=wallets[rootId] ?: return false
        canonicalInvestmentWalletForPublication(s.owner,root,forWrite=true)
        if(CloudEntity.LEDGER_WALLET.table to rootId in s.dirtyKeys || s.pending.any{it.mutation.entity==CloudEntity.INVESTMENT_TRADE})return false
        val dependencies=(g.rows.mapNotNull{it.payload.financeRawString("wallet_id")}+
            listOfNotNull(g.primary.payload.financeRawString("source_wallet_id"),g.primary.payload.financeRawString("destination_wallet_id"))).toSet()-rootId
        val proven=walletInvestmentActivePrerequisites(s,dependencies)
        for(id in dependencies) {
            if(CloudEntity.LEDGER_WALLET.table to id in s.dirtyKeys && id !in proven)return false
            val row=proven[id] ?: wallets[id] ?: return false;val w=investmentLinkedWalletRecord(row)
            if(w.deletedAt!=null || w.isArchived || w.systemPurposeRawValue!=null || w.kind in setOf(null,WalletKind.INVESTMENT))return false
            if(w.kind==WalletKind.CREDIT_CARD) {
                val profiles=s.rows.filter{it.entity==CloudEntity.CREDIT_CARD_PROFILE.table && it.deletedAt==null}
                    .map(CreditCardProfileRecord::fromCloudRecord).filter{it.walletId==id}
                val profile=profiles.singleOrNull() ?: return false
                if(CloudEntity.CREDIT_CARD_PROFILE.table to profile.id in s.dirtyKeys)return false
            }
        }
        val t=LedgerTransactionRecord.fromCloudRecord(g.primary)
        val active=t.deletedAt==null && !t.isArchived && t.entryStatus==TransactionEntryStatus.POSTED
        val categoryId=t.categoryId
        if(active && t.primaryKind in setOf(TransactionPrimaryKind.EXPENSE,TransactionPrimaryKind.INCOME) && categoryId==null)return false
        if(categoryId!=null) {
            val rows=s.rows.filter{it.entity==CloudEntity.TRANSACTION_CATEGORY.table}.associateBy{it.id}
            val category=rows[categoryId]?.let(TransactionCategoryRecord::fromCloudRecord) ?: return false
            if(category.deletedAt!=null || active && category.isArchived || category.hierarchyRole!=CategoryHierarchyRole.CHILD)return false
            val parent=category.parentCategoryId?.let(rows::get)?.let(TransactionCategoryRecord::fromCloudRecord) ?: return false
            if(parent.deletedAt!=null || active && parent.isArchived || parent.hierarchyRole!=CategoryHierarchyRole.PARENT || parent.kind!=category.kind)return false
            if(t.primaryKind==TransactionPrimaryKind.EXPENSE && category.kind!=TransactionCategoryKind.EXPENSE || t.primaryKind==TransactionPrimaryKind.INCOME && category.kind!=TransactionCategoryKind.INCOME)return false
            if(listOf(category.id,parent.id).any{CloudEntity.TRANSACTION_CATEGORY.table to it in s.dirtyKeys})return false
        }
        // Other complete ordinary groups may share this cash source. Blocking
        // every sibling would leave all of them waiting for one another.
        val knownPostingKeys=investmentOrdinaryPublicationCandidates(s).flatMap{id->
            runCatching{investmentOrdinaryPublicationGroup(s.copy(eventId=id)).postings}.getOrDefault(emptyList())
        }.map{it.entity to it.id}.toSet()
        if(s.pending.any{it.mutation.entity==CloudEntity.INVESTMENT_POSTING && it.mutation.entity.table to it.mutation.recordId !in knownPostingKeys})return false
        requireStableInvestmentOrdinaryAllocation(s,proven)
        true
    }.getOrDefault(false)
    private class PersistenceFailure(val failure:Exception):RuntimeException()
    private class Conflict(val reason:String):IllegalStateException()
}
