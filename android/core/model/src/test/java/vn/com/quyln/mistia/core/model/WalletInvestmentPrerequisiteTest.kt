package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class WalletInvestmentPrerequisiteTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val now="2026-10-28T00:00:00Z"
    private val later="2026-10-28T00:01:00Z"
    private val event=id(20)
    private fun version(row:CloudRecord,n:Long)=row.copy(syncVersion=n,payload=JsonObject(row.payload+("sync_version" to JsonPrimitive(n))))
    private fun source(newWallet:Boolean=false):InvestmentTradePublicationSnapshot {
        fun wallet(n:Int)=version(WalletDraft(id=id(n),name="Wallet$n",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=150).toMutation(owner,null,device,now).record,if(newWallet && n==1)0 else 1)
        val root=wallet(99).let{it.copy(id=investmentSystemWalletId(owner),payload=JsonObject(it.payload+buildJsonObject {
            put("id",investmentSystemWalletId(owner));put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",id(1));put("opening_balance_minor",0)
        }))}
        val cash=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",1L)
            put("event_id",id(110));put("wallet_id",id(1));put("ledger_transaction_id",id(110));put("role_raw_value","cashAccrual")
            put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived");put("amount_minor",50L);put("accounting_amount_minor",50L)
            put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at",now)
        },now,null,1)
        val before=InvestmentWalletSnapshot(owner,listOf(root,wallet(1),wallet(2),cash))
        val plan=planInvestmentWalletLink(before,InvestmentWalletLinkRequest(LedgerWalletRecord.fromCloudRecord(root),LedgerWalletRecord.fromCloudRecord(before.rows.single{it.id==id(2)}),event,true,50,"Move all"),device,now)
        val changed=plan.mutations.map{it.first}.associateBy{it.entity to it.id}
        val rows=(before.rows.map{changed[it.entity to it.id] ?: it}+changed.values.filter{r->before.rows.none{it.entity==r.entity && it.id==r.id}}).map{if(it.id==root.id)version(it,2) else it}
        val archive=LedgerWalletRecord.fromCloudRecord(rows.single{it.id==id(1)}).toArchiveMutation(device,later)
        val pending=plan.mutations.filter{it.second.entity!=CloudEntity.LEDGER_WALLET}.map{QueuedMutation(it.second,0,0,null)}+QueuedMutation(archive.pending,0,0,null)
        return InvestmentTradePublicationSnapshot(owner,event,rows.map{if(it.id==id(1))archive.record else it},pending,pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet()).also{it.requireCoherent()}
    }
    private fun active(s:InvestmentTradePublicationSnapshot)=s.rows.single{it.id==id(1)}.let{it.copy(payload=JsonObject(it.payload+buildJsonObject{put("is_archived",false);put("archived_at",JsonNull)}))}
    private fun withChange(s:InvestmentTradePublicationSnapshot,row:CloudRecord)=s.copy(rows=s.rows.map{if(it.entity==row.entity && it.id==row.id)row else it},pending=s.pending.map{q->if(q.mutation.recordId==row.id)q.copy(mutation=q.mutation.copy(payload=row.payload,baseVersion=row.syncVersion,modifiedAt=row.updatedAt!!)) else q})
    @Test fun observedActiveWalletProvesPrerequisiteWithoutAnotherWriteOrLosingFinalArchive() {
        val s=source();val p=prepareWalletInvestmentPrerequisite(s,id(1),active(s))
        assertFalse(p.needsWrite);assertEquals(s.pending.size,p.preparedSource.pending.size)
        assertEquals(true,p.preparedRecord.payload.financeRawArchived());assertEquals(1L,p.preparedRecord.syncVersion)
        val proof=walletInvestmentActivePrerequisite(p.preparedRecord)
        assertEquals(false,proof!!.payload.financeRawArchived());assertEquals(1L,proof.syncVersion)
        assertEquals(s.pending.filter{it.mutation.entity!=CloudEntity.LEDGER_WALLET},p.preparedSource.pending.filter{it.mutation.entity!=CloudEntity.LEDGER_WALLET})
    }
    @Test fun neverPublishedWalletPreparesAnOwnActiveInsertThenRebasesOnlyFinalArchiveBase() {
        val s=source(true);val p=prepareWalletInvestmentPrerequisite(s,id(1),null)
        assertTrue(p.needsWrite);assertEquals(1L,p.proposal.syncVersion);assertEquals(false,p.proposal.payload.financeRawArchived());assertEquals(JsonNull,p.proposal.payload["archived_at"])
        assertEquals(true,p.preparedRecord.payload.financeRawArchived());assertNull(walletInvestmentActivePrerequisite(p.preparedRecord))
        assertTrue(p.proposal.payload.keys.none{it.startsWith("_mistia_android_")})
        val change=planWalletInvestmentPrerequisiteRebase(p.preparedSource,id(1),p.proposal,p.preparedSource)!!
        assertEquals(true,change.first.payload.financeRawArchived());assertEquals(1L,change.first.syncVersion)
        assertEquals(1L,change.second.mutation.baseVersion);assertEquals(later,change.second.mutation.modifiedAt);assertTrue(change.second.remoteIdentityObserved)
        assertNotNull(walletInvestmentActivePrerequisite(change.first));assertEquals(s.pending.size,p.preparedSource.pending.size)
    }
    @Test fun archivedDeletedForeignNewerOrWrongCurrencyRemoteCannotBeReactivated() {
        val s=source();val good=active(s)
        val invalid=listOf(s.rows.single{it.id==id(1)},good.copy(deletedAt=now,payload=JsonObject(good.payload+("deleted_at" to JsonPrimitive(now)))),
            good.copy(ownerUserId=device,payload=JsonObject(good.payload+("user_id" to JsonPrimitive(device)))),version(good,2),good.copy(payload=JsonObject(good.payload+("currency_code" to JsonPrimitive("VND")))))
        for(remote in invalid)assertTrue(runCatching{prepareWalletInvestmentPrerequisite(s,id(1),remote)}.isFailure)
    }
    @Test fun lostReplyCanRecoverOnlyTheExactJournalAndKeepsANewerWalletGeneration() {
        val p=prepareWalletInvestmentPrerequisite(source(true),id(1),null)
        val newer=p.preparedRecord.copy(updatedAt="2026-10-28T00:02:00Z",payload=JsonObject(p.preparedRecord.payload+buildJsonObject{put("name","Newer name");put("updated_at","2026-10-28T00:02:00Z")}))
        assertNull(planWalletInvestmentPrerequisiteRebase(p.preparedSource,id(1),p.proposal,withChange(p.preparedSource,newer)))
        val wrong=p.proposal.copy(payload=JsonObject(p.proposal.payload+("name" to JsonPrimitive("Other intent"))))
        assertTrue(runCatching{planWalletInvestmentPrerequisiteRebase(p.preparedSource,id(1),wrong,p.preparedSource)}.isFailure)
        assertNotNull(planWalletInvestmentPrerequisiteRebase(p.preparedSource,id(1),p.proposal,p.preparedSource))
    }
    @Test fun pendingFinancialGuardDoesNotDependOnWriteGateAndIgnoresOtherWallets() {
        val s=source();assertTrue(walletHasPendingInvestmentFinancialDependency(s,id(1)));assertTrue(walletHasPendingInvestmentFinancialDependency(s,id(2)))
        assertFalse(walletHasPendingInvestmentFinancialDependency(s,id(3)))
        val noFinancial=s.copy(pending=s.pending.filter{it.mutation.entity==CloudEntity.LEDGER_WALLET},dirtyKeys=setOf(CloudEntity.LEDGER_WALLET.table to id(1)))
        assertFalse(walletHasPendingInvestmentFinancialDependency(noFinancial,id(1)))
    }
    @Test fun malformedPrivateProofAndUnknownReservationNeverGrantFinancialReadiness() {
        val s=source();val row=s.rows.single{it.id==id(1)}
        assertNull(walletInvestmentActivePrerequisite(row))
        val bad=row.copy(payload=JsonObject(row.payload+(LOCAL_WALLET_INVESTMENT_PREREQUISITE_KEY to buildJsonObject{put("version",1)})))
        assertTrue(runCatching{walletInvestmentActivePrerequisite(bad)}.isFailure)
        val rows=s.rows.filter{it.entity!=CloudEntity.LEDGER_TRANSACTION.table}
        val q=s.pending.filter{it.mutation.entity!=CloudEntity.LEDGER_TRANSACTION}
        val unknown=s.copy(rows=rows,pending=q,dirtyKeys=q.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        assertTrue(walletHasPendingInvestmentFinancialDependency(unknown,id(1)))
        assertTrue(runCatching{prepareWalletInvestmentPrerequisite(unknown,id(1),active(s))}.isFailure)
    }    @Test fun observedLegacyBaseZeroIsNeverMistakenForAnUnpublishedIdentity() {
        val s=source(true);val observed=s.copy(pending=s.pending.map{q->if(q.mutation.entity==CloudEntity.LEDGER_WALLET)q.copy(remoteIdentityObserved=true) else q})
        assertTrue(runCatching{prepareWalletInvestmentPrerequisite(observed,id(1),null)}.isFailure)
    }

    @Test fun freshGenerationRecoversOwnHistoricalBirthReplyThenStagesTheNewerName() {
        val p=prepareWalletInvestmentPrerequisite(source(true),id(1),null)
        val newer=p.preparedRecord.copy(updatedAt="2026-10-28T00:02:00Z",payload=JsonObject(p.preparedRecord.payload+buildJsonObject{put("name","Newer name");put("updated_at","2026-10-28T00:02:00Z")}))
        val current=withChange(p.preparedSource,newer)
        assertNull(planWalletInvestmentPrerequisiteRebase(p.preparedSource,id(1),p.proposal,current))
        val change=planWalletInvestmentPrerequisiteRebase(current,id(1),p.proposal,current)!!
        assertEquals("Newer name",change.first.payload.financeRawString("name"));assertEquals(1L,change.first.syncVersion)
        assertEquals("2026-10-28T00:02:00Z",change.second.mutation.modifiedAt);assertNull(walletInvestmentActivePrerequisite(change.first))
        val rebased=withChange(current,change.first)
        val next=prepareWalletInvestmentPrerequisite(rebased,id(1),p.proposal)
        assertTrue(next.needsWrite);assertEquals(2L,next.proposal.syncVersion);assertEquals("Newer name",next.proposal.payload.financeRawString("name"))
        val final=planWalletInvestmentPrerequisiteRebase(next.preparedSource,id(1),next.proposal,next.preparedSource)!!
        assertEquals("Newer name",walletInvestmentActivePrerequisite(final.first)!!.payload.financeRawString("name"));assertEquals(true,final.first.payload.financeRawArchived())
    }
    @Test fun anOlderValidObservationSurvivesAsHistoryButCannotProveTheChangedWallet() {
        val s=source();val p=prepareWalletInvestmentPrerequisite(s,id(1),active(s))
        val newer=p.preparedRecord.copy(updatedAt="2026-10-28T00:02:00Z",payload=JsonObject(p.preparedRecord.payload+buildJsonObject{put("name","Newer name");put("updated_at","2026-10-28T00:02:00Z")}))
        assertNull(walletInvestmentActivePrerequisite(newer))
        val next=prepareWalletInvestmentPrerequisite(withChange(p.preparedSource,newer),id(1),active(s))
        assertTrue(next.needsWrite);assertEquals(2L,next.proposal.syncVersion)
    }

    @Test fun aKnownRemotePrerequisiteConflictRevokesItsCachedActivePermission() {
        val original=source();val p=prepareWalletInvestmentPrerequisite(original,id(1),active(original))
        val blocked=p.preparedSource.copy(pending=p.preparedSource.pending.map{q->if(q.mutation.entity==CloudEntity.LEDGER_WALLET)q.copy(attemptCount=1,nextAttemptAtEpochMillis=Long.MAX_VALUE,lastError="conflict_wallet_prerequisite_remote_changed") else q})
        assertTrue(walletInvestmentActivePrerequisites(blocked,setOf(id(1))).isEmpty())
        val uncertain=blocked.copy(pending=blocked.pending.map{q->if(q.mutation.entity==CloudEntity.LEDGER_WALLET)q.copy(lastError="network_io") else q})
        assertEquals(setOf(id(1)),walletInvestmentActivePrerequisites(uncertain,setOf(id(1))).keys)
    }


    @Test fun onlyTheLedgerQueueStillIdentifiesItsConfirmedPairAmongCleanHistory() {
        val original=source()
        val pending=original.pending.filter{it.mutation.entity!=CloudEntity.INVESTMENT_POSTING}
        val s=original.copy(pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        assertNotNull(prepareWalletInvestmentPrerequisite(s,id(1),active(s)))
    }
    @Test fun onlyThePostingQueuesStillIdentifyTheirCleanConfirmedLedger() {
        val original=source()
        val pending=original.pending.filter{it.mutation.entity!=CloudEntity.LEDGER_TRANSACTION}
        val s=original.copy(pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        assertNotNull(prepareWalletInvestmentPrerequisite(s,id(1),active(s)))
    }
    @Test fun unrelatedCleanHistoryCannotAuthorizeAnUnrecognizedDirtyReservation() {
        val original=source()
        val p=original.rows.single{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawLong("amount_minor")==-50L}
        val unknown=p.copy(id=id(999),payload=JsonObject(p.payload+buildJsonObject{put("id",id(999));put("event_id",id(998))}))
        val q=QueuedMutation(PendingMutation(CloudEntity.INVESTMENT_POSTING,unknown.id,owner.value,MutationKind.UPSERT,unknown.payload,unknown.updatedAt!!,unknown.syncVersion,device),0,0,null)
        val pending=original.pending.filter{it.mutation.entity==CloudEntity.LEDGER_WALLET}+q
        val s=original.copy(rows=original.rows+unknown,pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        assertTrue(walletHasPendingInvestmentFinancialDependency(s,id(1)))
        assertTrue(runCatching{prepareWalletInvestmentPrerequisite(s,id(1),active(s))}.isFailure)
    }

}
