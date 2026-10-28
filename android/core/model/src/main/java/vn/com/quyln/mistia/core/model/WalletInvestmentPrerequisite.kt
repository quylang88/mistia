package vn.com.quyln.mistia.core.model

import java.time.Instant
import kotlinx.serialization.json.*

const val LOCAL_WALLET_INVESTMENT_PREREQUISITE_KEY="_mistia_android_wallet_investment_prerequisite"

/** An active prerequisite never consumes or replaces the final archived wallet intent. */
data class WalletInvestmentPrerequisitePreparation(val source:InvestmentTradePublicationSnapshot,val id:String,val proposal:CloudRecord,val preparedRecord:CloudRecord,val needsWrite:Boolean) {
    val preparedSource:InvestmentTradePublicationSnapshot get()=source.copy(
        rows=source.rows.map{if(it.entity==CloudEntity.LEDGER_WALLET.table && it.id==id)preparedRecord else it},
        pending=source.pending.map{if(it.mutation.entity==CloudEntity.LEDGER_WALLET && it.mutation.recordId==id)it.copy(mutation=it.mutation.copy(payload=preparedRecord.payload)) else it})
}
interface WalletInvestmentPrerequisiteRemote {
    suspend fun fetchWallet(owner:UserId,id:String,accessToken:String):CloudRecord?
    suspend fun publishActive(owner:UserId,prepared:WalletInvestmentPrerequisitePreparation,accessToken:String):CloudRecord?
}
private data class WalletPrerequisiteJournal(val base:Long,val target:Long,val device:String,val fingerprint:String,val activeKind:String,val createdAt:String,val observed:CloudRecord?)
private fun walletPrerequisiteInstant(value:String):String {
    val i=Instant.parse(value)
    return Instant.ofEpochSecond(i.epochSecond,Math.rint(i.nano.toDouble()/1000).toLong()*1000).toString()
}
private fun requirePrerequisiteWallet(row:CloudRecord,owner:UserId,id:String,remote:Boolean):LedgerWalletRecord {
    require(financeRawUuid(id)==id && row.entity==CloudEntity.LEDGER_WALLET.table && row.id==id && row.ownerUserId==owner.value && row.financeRawIdentity(owner,CloudEntity.LEDGER_WALLET,true))
    require(row.payload.financeRawString("id")==id && row.payload.financeRawString("user_id")==owner.value && row.syncVersion>=0 &&
        row.payload.financeRawLong("sync_version")==row.syncVersion && row.updatedAt==row.payload.financeRawString("updated_at") &&
        row.deletedAt==null && row.financeRawDeleted(true)==false)
    require(row.payload.keys.none{it.startsWith("_mistia_android_") && (remote || it!=LOCAL_WALLET_INVESTMENT_PREREQUISITE_KEY)})
    val wallet=LedgerWalletRecord.fromCloudRecord(row)
    require(wallet.kind !in setOf(null,WalletKind.INVESTMENT,WalletKind.CREDIT_CARD) && wallet.systemPurposeRawValue==null && wallet.investmentLinkedWalletId==null)
    require(wallet.currencyCode.financeReportingCode()==wallet.currencyCode && java.util.Currency.getInstance(wallet.currencyCode).defaultFractionDigits>=0)
    for(key in listOf("created_at","updated_at"))walletPrerequisiteInstant(requireNotNull(row.payload.financeRawString(key)))
    require(row.payload.financeRawArchived()!=null && row.payload.financeRawReference("last_modified_by_device_id").readable)
    if(remote)require(row.syncVersion>0 && !wallet.isArchived && row.payload["archived_at"]==JsonNull)
    return wallet
}
/** Strip this one validated local key only at the wallet publisher boundary. */
fun walletInvestmentPayloadForCloud(payload:JsonObject)=JsonObject(payload-LOCAL_WALLET_INVESTMENT_PREREQUISITE_KEY)
private fun walletPrerequisiteBusiness(payload:JsonObject,kind:String?=null):String {
    val business=(walletInvestmentPayloadForCloud(payload)-setOf("is_archived","archived_at","updated_at","sync_version","last_modified_by_device_id")).toMutableMap()
    kind?.let{business["kind_raw_value"]=JsonPrimitive(it)}
    business["created_at"]=JsonPrimitive(walletPrerequisiteInstant(requireNotNull(payload.financeRawString("created_at"))))
    return RecordConflictResolver.semanticFingerprint(JsonObject(business))
}
private fun observedWallet(row:CloudRecord,payload:JsonObject)=CloudRecord(row.entity,row.id,row.ownerUserId,payload,payload.financeRawString("updated_at"),payload.financeRawString("deleted_at"),requireNotNull(payload.financeRawLong("sync_version")))
private fun journal(row:CloudRecord):WalletPrerequisiteJournal? {
    val raw=row.payload[LOCAL_WALLET_INVESTMENT_PREREQUISITE_KEY] ?: return null
    requirePrerequisiteWallet(row,UserId(row.ownerUserId),row.id,false)
    val p=raw as? JsonObject ?: error("Invalid wallet prerequisite journal")
    require(p.keys==setOf("version","owner_user_id","record_id","base_version","target_version","device_id","fingerprint","active_kind","created_at","observation") && p["version"]==JsonPrimitive(1))
    require(p.financeRawString("owner_user_id")==row.ownerUserId && p.financeRawString("record_id")==row.id)
    val base=requireNotNull(p.financeRawLong("base_version"));val target=requireNotNull(p.financeRawLong("target_version"))
    require(base>=0 && base<Long.MAX_VALUE && (target==base || target==base+1) && target>0)
    val device=requireNotNull(p.financeRawString("device_id"));require(financeRawUuid(device)==device)
    val fingerprint=requireNotNull(p.financeRawString("fingerprint"));require(Regex("[0-9a-f]{64}").matches(fingerprint))
    val kind=requireNotNull(p.financeRawString("active_kind"));require(WalletKind.entries.any{it.wireValue==kind && it !in setOf(WalletKind.INVESTMENT,WalletKind.CREDIT_CARD)})
    val createdAt=requireNotNull(p.financeRawString("created_at"))
    require(walletPrerequisiteInstant(createdAt)==createdAt && walletPrerequisiteInstant(requireNotNull(row.payload.financeRawString("created_at")))==createdAt)
    val observed=if(p["observation"]==JsonNull)null else observedWallet(row,p["observation"] as? JsonObject ?: error("Invalid wallet observation"))
    if(observed==null)require(target==base+1 && row.syncVersion==base)
    else {
        requirePrerequisiteWallet(observed,UserId(row.ownerUserId),row.id,true)
        require(observed.syncVersion==target && row.syncVersion==target && walletPrerequisiteBusiness(observed.payload)==fingerprint)
        if(target!=base)require(observed.payload.financeRawString("last_modified_by_device_id")==device)
    }
    return WalletPrerequisiteJournal(base,target,device,fingerprint,kind,createdAt,observed)
}
private fun withJournal(row:CloudRecord,j:WalletPrerequisiteJournal)=row.copy(payload=JsonObject(row.payload+(LOCAL_WALLET_INVESTMENT_PREREQUISITE_KEY to buildJsonObject {
    put("version",1);put("owner_user_id",row.ownerUserId);put("record_id",row.id);put("base_version",j.base);put("target_version",j.target)
    put("device_id",j.device);put("fingerprint",j.fingerprint);put("active_kind",j.activeKind);put("created_at",j.createdAt);put("observation",j.observed?.payload ?: JsonNull)
})))
/** Structural history can survive edits; only the current matching archive may use it. */
fun validateWalletInvestmentPrerequisiteJournal(row:CloudRecord) {journal(row)}
fun walletInvestmentActivePrerequisite(row:CloudRecord):CloudRecord? {
    val j=journal(row) ?: return null
    if(row.payload.financeRawArchived()!=true || walletPrerequisiteBusiness(row.payload,j.activeKind)!=j.fingerprint)return null
    return j.observed
}
fun retainWalletInvestmentPrerequisite(previous:CloudRecord,next:CloudRecord):CloudRecord {
    journal(previous) ?: return next
    require(previous.entity==next.entity && previous.id==next.id && previous.ownerUserId==next.ownerUserId && previous.syncVersion==next.syncVersion)
    requirePrerequisiteWallet(next,UserId(previous.ownerUserId),previous.id,false)
    val old=requireNotNull(previous.payload[LOCAL_WALLET_INVESTMENT_PREREQUISITE_KEY])
    require(next.payload[LOCAL_WALLET_INVESTMENT_PREREQUISITE_KEY]?.let{it==old}!=false)
    return next.copy(payload=JsonObject(next.payload+(LOCAL_WALLET_INVESTMENT_PREREQUISITE_KEY to old))).also{journal(it)}
}

/** All pending investment references hold retirement, including an unrecognized reservation. */
fun walletHasPendingInvestmentFinancialDependency(source:InvestmentTradePublicationSnapshot,id:String):Boolean {
    source.requireCoherent();require(financeRawUuid(id)==id)
    val rows=source.rows.associateBy{it.entity to it.id}
    fun references(row:CloudRecord)=listOf("wallet_id","source_wallet_id","destination_wallet_id","funding_wallet_id","capital_return_wallet_id").any{row.payload.financeRawString(it)==id}
    for(q in source.pending) {
        val row=rows.getValue(q.mutation.entity.table to q.mutation.recordId)
        when(q.mutation.entity) {
            CloudEntity.INVESTMENT_TRADE->if(references(row))return true
            CloudEntity.INVESTMENT_POSTING->{
                val ref=row.payload.financeRawReference("wallet_id");if(!ref.readable || ref.id==null || references(row))return true
                val ledger=row.payload.financeRawReference("ledger_transaction_id");if(!ledger.readable)return true
                rows[CloudEntity.LEDGER_TRANSACTION.table to ledger.id]?.let{if(references(it))return true}
            }
            CloudEntity.LEDGER_TRANSACTION->if(references(row)) {
                if(row.payload.financeRawString("settlement_role_raw_value")?.startsWith("investment")==true)return true
                // Clean allocation history still reserves an edited ordinary
                // parent, even when none of its posting payloads changed.
                val canonical=listOf("cash-consumption-booked","cash-consumption-unreconciled","cash-destination-booked","cash-destination-unreconciled")
                    .map{investmentLedgerIdentity(row.id,it)}.toSet()
                if(localOrdinaryPublicationHistory(row).any{it.rows.size>1} ||
                    rows.containsKey(CloudEntity.LEDGER_TRANSACTION.table to investmentLedgerIdentity(row.id,"cash-unreconciled-adjustment")) ||
                    source.rows.any{it.entity==CloudEntity.INVESTMENT_POSTING.table && (it.id in canonical ||
                        it.payload.financeRawString("event_id")==row.id && it.payload.financeRawString("role_raw_value") in setOf("cashConsumption","cashTransfer"))})return true
            }
            else->Unit
        }
    }
    return false
}
private fun knownWalletReservation(source:InvestmentTradePublicationSnapshot,id:String):Boolean {
    val cashRows=source.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentCashEventPublicationSnapshot.entities}
    val pending=source.pending.filter{it.mutation.entity in InvestmentCashEventPublicationSnapshot.entities}
    val rowsByKey=source.rows.associateBy{it.entity to it.id}
    val dirtyLedgers=pending.filter{it.mutation.entity==CloudEntity.LEDGER_TRANSACTION}.map{it.mutation.recordId}.toSet()
    fun cash(event:String)=InvestmentCashEventPublicationSnapshot(source.owner,event,cashRows,pending,pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
    fun touches(rows:List<CloudRecord>)=rows.any{r->listOf("wallet_id","source_wallet_id","destination_wallet_id").any{r.payload.financeRawString(it)==id}} && rows.any{it.entity to it.id in source.dirtyKeys}
    // Clean history alone cannot reserve retirement. A clean posting still
    // supplies its event when only the corresponding real ledger is queued.
    val events=linkedSetOf<String>()
    for(row in cashRows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table}) {
        if(row.entity to row.id !in source.dirtyKeys && row.payload.financeRawString("ledger_transaction_id") !in dirtyLedgers)continue
        val event=row.payload.financeRawString("event_id") ?: continue
        if(financeRawUuid(event)!=event)continue
        events+=event
    }
    for(event in events) {
        val s=cash(event)
        if(runCatching{investmentLinkedWalletMoveGroup(s).rows}.getOrNull()?.let(::touches)==true)return true
        if(runCatching{investmentCashReconciliationGroup(s).rows}.getOrNull()?.let(::touches)==true)return true
    }
    for(row in cashRows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table}) {
        if(row.payload.financeRawString("settlement_role_raw_value") !in setOf("investmentCashDeposit","investmentCashWithdrawal"))continue
        val postingKey=CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(row.id,"cash-transfer-posting")
        if(row.entity to row.id !in source.dirtyKeys && postingKey !in source.dirtyKeys)continue
        val post=rowsByKey[postingKey] ?: continue
        if(runCatching{requireCashEventCanonical(source.owner,row.id,row,post,false)}.isSuccess && touches(listOf(row,post)))return true
    }
    for(q in source.pending.filter{it.mutation.entity==CloudEntity.INVESTMENT_TRADE}) {
        val row=rowsByKey.getValue(q.mutation.entity.table to q.mutation.recordId)
        if(listOf("funding_wallet_id","capital_return_wallet_id").any{row.payload.financeRawString(it)==id} &&
            runCatching{requireInvestmentTradeForPublication(source.owner,row,forWrite=false)}.isSuccess)return true
    }
    // This grants an active metadata prerequisite only. The ordinary
    // publisher independently proves the full timeline and all prerequisites
    // from its expanded snapshot before any financial write.
    val ordinaryRows=source.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentOrdinaryPublicationSnapshot.entities}
    val ordinaryPending=source.pending.filter{it.mutation.entity in InvestmentOrdinaryPublicationSnapshot.entities}
    val ordinary=InvestmentOrdinaryPublicationSnapshot(source.owner,source.tradeId,ordinaryRows,ordinaryPending,
        ordinaryPending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
    for(event in investmentOrdinaryPublicationCandidates(ordinary)) {
        if(runCatching{investmentOrdinaryPublicationGroup(ordinary.copy(eventId=event)).rows}.getOrNull()?.let(::touches)==true)return true
    }
    return false
}
fun prepareWalletInvestmentPrerequisite(source:InvestmentTradePublicationSnapshot,id:String,compared:CloudRecord?):WalletInvestmentPrerequisitePreparation {
    source.requireCoherent()
    val row=source.rows.single{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==id}
    val wallet=requirePrerequisiteWallet(row,source.owner,id,false);journal(row)
    val q=source.pending.single{it.mutation.entity==CloudEntity.LEDGER_WALLET && it.mutation.recordId==id}
    require(wallet.isArchived && q.mutation.kind==MutationKind.UPSERT && row.syncVersion<Long.MAX_VALUE)
    require(walletHasPendingInvestmentFinancialDependency(source,id) && knownWalletReservation(source,id))
    val rootId=investmentSystemWalletId(source.owner)
    require(CloudEntity.LEDGER_WALLET.table to rootId !in source.dirtyKeys)
    canonicalInvestmentWalletForPublication(source.owner,source.rows.single{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==rootId},forWrite=true)
    val observed=compared?.also{
        val remote=requirePrerequisiteWallet(it,source.owner,id,true)
        require(it.syncVersion==row.syncVersion && remote.currencyCode==wallet.currencyCode &&
            walletPrerequisiteInstant(remote.createdAt!!)==walletPrerequisiteInstant(wallet.createdAt!!))
    }
    if(observed==null)require(row.syncVersion==0L && !q.remoteIdentityObserved)
    val kind=observed?.payload?.financeRawString("kind_raw_value") ?: requireNotNull(row.payload.financeRawString("kind_raw_value"))
    val fingerprint=walletPrerequisiteBusiness(row.payload,kind)
    val write=observed==null || walletPrerequisiteBusiness(observed.payload)!=fingerprint
    val target=row.syncVersion+if(write)1 else 0
    val proposal=if(!write)requireNotNull(observed) else row.copy(syncVersion=target,payload=JsonObject(walletInvestmentPayloadForCloud(row.payload)+buildJsonObject {
        put("kind_raw_value",kind);put("is_archived",false);put("archived_at",JsonNull);put("sync_version",target)
    }))
    val prepared=withJournal(row,WalletPrerequisiteJournal(row.syncVersion,target,q.mutation.deviceId,fingerprint,kind,walletPrerequisiteInstant(requireNotNull(row.payload.financeRawString("created_at"))),if(write)null else observed))
    return WalletInvestmentPrerequisitePreparation(source,id,proposal,prepared,write).also{it.preparedSource.requireCoherent();journal(it.preparedRecord)}
}
fun planWalletInvestmentPrerequisiteRebase(prepared:InvestmentTradePublicationSnapshot,id:String,remote:CloudRecord,current:InvestmentTradePublicationSnapshot):Pair<CloudRecord,QueuedMutation>? {
    prepared.requireCoherent();current.requireCoherent()
    val prior=prepared.rows.single{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==id}
    val j=requireNotNull(journal(prior));require(j.observed==null)
    requirePrerequisiteWallet(remote,prepared.owner,id,true)
    require(remote.syncVersion==j.target && remote.payload.financeRawString("last_modified_by_device_id")==j.device && walletPrerequisiteBusiness(remote.payload)==j.fingerprint)
    if(runCatching{prepared.requireUnchanged(current)}.isFailure)return null
    val q=current.pending.single{it.mutation.entity==CloudEntity.LEDGER_WALLET && it.mutation.recordId==id}
    val row=prior.copy(syncVersion=remote.syncVersion,payload=JsonObject(prior.payload+("sync_version" to JsonPrimitive(remote.syncVersion))))
    val changed=withJournal(row,j.copy(observed=remote));journal(changed)
    return changed to q.copy(mutation=q.mutation.copy(baseVersion=remote.syncVersion,payload=changed.payload),remoteIdentityObserved=true)
}

/** Validate the exact causal proposal again at the closed network boundary. */
fun walletInvestmentPrerequisiteWriteBase(prepared:WalletInvestmentPrerequisitePreparation):Long {
    prepared.source.requireCoherent();prepared.preparedSource.requireCoherent();require(prepared.needsWrite)
    val row=prepared.source.rows.single{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==prepared.id}
    require(row.copy(payload=walletInvestmentPayloadForCloud(row.payload))==prepared.preparedRecord.copy(payload=walletInvestmentPayloadForCloud(prepared.preparedRecord.payload)))
    val j=requireNotNull(journal(prepared.preparedRecord));require(j.observed==null && j.base==row.syncVersion)
    val q=prepared.source.pending.single{it.mutation.entity==CloudEntity.LEDGER_WALLET && it.mutation.recordId==prepared.id}
    require(j.device==q.mutation.deviceId && q.mutation.kind==MutationKind.UPSERT && (j.base!=0L || !q.remoteIdentityObserved))
    require(walletHasPendingInvestmentFinancialDependency(prepared.source,prepared.id) && knownWalletReservation(prepared.source,prepared.id))
    val rootId=investmentSystemWalletId(prepared.source.owner)
    require(CloudEntity.LEDGER_WALLET.table to rootId !in prepared.source.dirtyKeys)
    canonicalInvestmentWalletForPublication(prepared.source.owner,prepared.source.rows.single{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==rootId},forWrite=true)
    requireNotNull(planWalletInvestmentPrerequisiteRebase(prepared.preparedSource,prepared.id,prepared.proposal,prepared.preparedSource))
    return j.base
}

private fun activeWalletPrerequisites(owner:UserId,rows:List<CloudRecord>,pending:List<QueuedMutation>,dirtyKeys:Set<Pair<String,String>>,ids:Set<String>):Map<String,CloudRecord> {
    val result=linkedMapOf<String,CloudRecord>()
    for(id in ids-investmentSystemWalletId(owner)) {
        if(CloudEntity.LEDGER_WALLET.table to id !in dirtyKeys)continue
        val q=pending.single{it.mutation.entity==CloudEntity.LEDGER_WALLET && it.mutation.recordId==id}
        if(q.mutation.kind!=MutationKind.UPSERT)continue
        if(q.lastError?.startsWith("conflict_wallet_prerequisite_")==true)continue
        val row=rows.single{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==id}
        require(row.ownerUserId==owner.value && row.payload==q.mutation.payload)
        walletInvestmentActivePrerequisite(row)?.let{result[id]=it}
    }
    return result
}
fun walletInvestmentActivePrerequisites(source:InvestmentTradePublicationSnapshot,ids:Set<String>):Map<String,CloudRecord> {
    source.requireCoherent();return activeWalletPrerequisites(source.owner,source.rows,source.pending,source.dirtyKeys,ids)
}
fun walletInvestmentActivePrerequisites(source:InvestmentCashEventPublicationSnapshot,ids:Set<String>):Map<String,CloudRecord> {
    source.requireCoherent();return activeWalletPrerequisites(source.owner,source.rows,source.pending,source.dirtyKeys,ids)
}
fun walletInvestmentActivePrerequisites(source:InvestmentOrdinaryPublicationSnapshot,ids:Set<String>):Map<String,CloudRecord> {
    source.requireCoherent();return activeWalletPrerequisites(source.owner,source.rows,source.pending,source.dirtyKeys,ids)
}
