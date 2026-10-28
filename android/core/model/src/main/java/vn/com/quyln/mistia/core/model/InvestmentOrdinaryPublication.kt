package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.time.Instant
import kotlinx.serialization.json.*

/** One owned generation including ordinary prerequisites and all cash inputs. */
data class InvestmentOrdinaryPublicationSnapshot(val owner:UserId,val eventId:String,val rows:List<CloudRecord>,
    val pending:List<QueuedMutation>,val dirtyKeys:Set<Pair<String,String>>) {
    fun requireCoherent() {
        require(financeRawUuid(owner.value)==owner.value && financeRawUuid(eventId)==eventId)
        val byKey=rows.associateBy{it.entity to it.id};require(byKey.size==rows.size)
        for(row in rows) {
            val entity=requireNotNull(CloudEntity.fromTable(row.entity));require(entity in entities && financeRawUuid(row.id)==row.id &&
                row.financeRawIdentity(owner,entity,true) && row.payload.financeRawString("id")==row.id && row.payload.financeRawString("user_id")==owner.value &&
                row.syncVersion>=0 && row.payload.financeRawLong("sync_version")==row.syncVersion && row.updatedAt==row.payload.financeRawString("updated_at") &&
                row.financeRawDeleted(true)!=null && row.deletedAt==row.payload.financeRawString("deleted_at"))
            for(key in listOf("created_at","updated_at"))Instant.parse(requireNotNull(row.payload.financeRawString(key)))
        }
        val keys=pending.map{it.mutation.entity.table to it.mutation.recordId}
        require(keys.distinct().size==keys.size && dirtyKeys==keys.toSet())
        for(q in pending) {
            val m=q.mutation;val row=requireNotNull(byKey[m.entity.table to m.recordId])
            require(m.entity in entities && m.subjectUserId==owner.value && financeRawUuid(m.deviceId)==m.deviceId &&
                m.payload==row.payload && m.baseVersion==row.syncVersion && m.modifiedAt==row.updatedAt &&
                row.payload.financeRawString("last_modified_by_device_id")==m.deviceId && m.kind==if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE)
            Instant.parse(m.modifiedAt)
        }
    }
    fun requireUnchanged(current:InvestmentOrdinaryPublicationSnapshot) {
        requireCoherent();current.requireCoherent()
        require(owner==current.owner && eventId==current.eventId && dirtyKeys==current.dirtyKeys &&
            rows.sortedWith(compareBy(CloudRecord::entity,CloudRecord::id))==current.rows.sortedWith(compareBy(CloudRecord::entity,CloudRecord::id)) &&
            pending.sortedWith(compareBy<QueuedMutation>{it.mutation.entity.table}.thenBy{it.mutation.recordId})==
                current.pending.sortedWith(compareBy<QueuedMutation>{it.mutation.entity.table}.thenBy{it.mutation.recordId}))
    }
    companion object {val entities=TransactionInvestmentSaveSnapshot.entities}
}
data class InvestmentOrdinaryPublicationGroup(val eventId:String,val primary:CloudRecord,val adjustment:CloudRecord?,
    val postings:List<CloudRecord>,val queues:List<QueuedMutation>) {
    val rows:List<CloudRecord> get()=listOfNotNull(primary,adjustment)+postings
}
private val ordinaryFundComponents=listOf("cash-consumption-booked","cash-consumption-unreconciled","cash-destination-booked","cash-destination-unreconciled")
private fun ordinaryFundReference(p:JsonObject,key:String):String?=p.financeRawReference(key).let{require(it.readable);it.id}
private fun ordinaryFundAmount(p:JsonObject,key:String)=requireNotNull(p.financeRawLong(key))
private fun ordinaryFundInstant(p:JsonObject,key:String)=Instant.parse(requireNotNull(p.financeRawString(key)))

/** Structural complete-group proof; it does not itself grant a remote write or ACK. */
fun investmentOrdinaryPublicationGroup(source:InvestmentOrdinaryPublicationSnapshot):InvestmentOrdinaryPublicationGroup {
    source.requireCoherent()
    val byKey=source.rows.associateBy{it.entity to it.id};val owner=source.owner;val event=source.eventId
    val storedPrimary=requireNotNull(byKey[CloudEntity.LEDGER_TRANSACTION.table to event])
    val primary=storedPrimary.copy(payload=ordinaryPublicationPayloadForCloud(storedPrimary));val t=primary.payload
    require(!requiresInvestmentLedgerDomain(t) && t.keys.none{it.startsWith("_mistia_android_")})
    val transaction=LedgerTransactionRecord.fromCloudRecord(primary)
    require(transaction.supportsOrdinaryTransactionLifecycle() && ordinaryFundAmount(t,"amount_minor")>0)
    val occurred=ordinaryFundInstant(t,"occurred_at")
    require(t.financeRawArchived()!=null)
    val rootId=investmentSystemWalletId(owner)
    val root=canonicalInvestmentWalletForPublication(owner,requireNotNull(byKey[CloudEntity.LEDGER_WALLET.table to rootId]),forWrite=true)
    val code=root.currencyCode
    require(investmentAssetCurrency(code)==code && java.util.Currency.getInstance(code).defaultFractionDigits>=0)
    fun wallet(id:String):LedgerWalletRecord {
        val raw=requireNotNull(byKey[CloudEntity.LEDGER_WALLET.table to id]);val w=investmentLinkedWalletRecord(raw)
        require(w.ownerUserId==owner.value && w.deletedAt==null)
        return w
    }
    val ids=ordinaryFundComponents.associateBy{investmentLedgerIdentity(event,it)}
    val postings=source.rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table && (it.id in ids || it.payload.financeRawString("event_id")==event)}.sortedBy{it.id}
    require(postings.isNotEmpty() && postings.size<=4)
    val components=linkedMapOf<String,CloudRecord>()
    for(row in postings) {
        val component=requireNotNull(ids[row.id]);val p=row.payload
        require(components.put(component,row)==null && p.keys.none{it.startsWith("_mistia_android_")})
        require(ordinaryFundReference(p,"event_id")==event && ordinaryFundReference(p,"ledger_transaction_id")==event &&
            ordinaryFundReference(p,"trade_id")==null && ordinaryFundReference(p,"asset_id")==null && p.financeRawString("cash_origin_raw_value")=="derived")
        val value=ordinaryFundAmount(p,"amount_minor")
        require(value==ordinaryFundAmount(p,"accounting_amount_minor") && value!=Long.MIN_VALUE &&
            p.financeRawString("currency_code")==code && p.financeRawString("accounting_currency_code")==code)
        val w=wallet(requireNotNull(ordinaryFundReference(p,"wallet_id")))
        require(w.kind !in setOf(null,WalletKind.INVESTMENT,WalletKind.CREDIT_CARD) && w.systemPurposeRawValue==null && w.currencyCode==code)
        val consumption=component.startsWith("cash-consumption-")
        require(if(consumption)value<0 else value>0)
        require(p.financeRawString("cash_bucket_raw_value")==if(component=="cash-consumption-unreconciled")"unreconciled" else "booked")
        require(p.financeRawString("role_raw_value") in if(consumption)setOf("cashConsumption","cashTransfer")else setOf("cashTransfer"))
        ordinaryFundInstant(p,"occurred_at")
    }
    val active=components.filterValues{it.deletedAt==null}
    val parentActive=primary.deletedAt==null && !transaction.isArchived && transaction.entryStatus==TransactionEntryStatus.POSTED && transaction.primaryKind!=TransactionPrimaryKind.INCOME
    if(!parentActive)require(active.isEmpty())
    val negative=active.filterKeys{it.startsWith("cash-consumption-")}
    val positive=active.filterKeys{it.startsWith("cash-destination-")}
    var destination:String?=null
    if(negative.isNotEmpty()) {
        require(parentActive)
        val sourceId=requireNotNull(ordinaryFundReference(t,"source_wallet_id"));val sourceWallet=wallet(sourceId)
        require(sourceWallet.kind !in setOf(null,WalletKind.INVESTMENT,WalletKind.CREDIT_CARD) && sourceWallet.systemPurposeRawValue==null && sourceWallet.currencyCode==code && t.financeRawString("source_currency_code")==code)
        if(transaction.transferSubtype==TransactionTransferSubtype.INTERNAL_TRANSFER) {
            val target=requireNotNull(ordinaryFundReference(t,"destination_wallet_id"));require(target!=sourceId)
            val w=wallet(target)
            if(w.kind!=WalletKind.CREDIT_CARD) {
                require(w.kind !in setOf(null,WalletKind.INVESTMENT) && w.systemPurposeRawValue==null && w.currencyCode==code && t.financeRawString("destination_currency_code")==code)
                destination=target
            }
        }
        for(row in negative.values)require(row.payload.financeRawString("wallet_id")==sourceId && row.payload.financeRawString("role_raw_value")==if(destination==null)"cashConsumption" else "cashTransfer")
        require(negative.values.fold(BigInteger.ZERO){sum,row->sum+BigInteger.valueOf(ordinaryFundAmount(row.payload,"amount_minor")).negate()}<=BigInteger.valueOf(transaction.amountMinor))
    }
    if(destination==null)require(positive.isEmpty())
    else {
        require(positive.size==negative.size)
        for((component,row) in negative) {
            val paired=requireNotNull(positive[component.replace("cash-consumption-","cash-destination-")])
            require(paired.payload.financeRawString("wallet_id")==destination && ordinaryFundAmount(paired.payload,"amount_minor")==-ordinaryFundAmount(row.payload,"amount_minor"))
        }
    }
    for(row in active.values)require(ordinaryFundInstant(row.payload,"occurred_at")==occurred)
    val adjustment=byKey[CloudEntity.LEDGER_TRANSACTION.table to investmentLedgerIdentity(event,"cash-unreconciled-adjustment")]
    val unreconciled=negative["cash-consumption-unreconciled"]
    if(adjustment!=null) {
        val p=adjustment.payload
        require(p.keys.none{it.startsWith("_mistia_android_")} && p.financeRawString("settlement_role_raw_value")=="investmentReserveUse" &&
            p.financeRawString("primary_kind_raw_value")=="transfer" && p.financeRawString("transfer_subtype_raw_value")=="internalTransfer" && p.financeRawString("entry_status_raw_value")=="posted" &&
            ordinaryFundReference(p,"source_wallet_id")==rootId && p.financeRawArchived()==false && ordinaryFundAmount(p,"amount_minor")>0)
        val amount=ordinaryFundAmount(p,"amount_minor")
        require(ordinaryFundAmount(p,"destination_amount_minor")==amount && ordinaryFundAmount(p,"reporting_amount_minor")==amount &&
            ordinaryFundAmount(p,"reporting_expense_minor")==0L && ordinaryFundAmount(p,"reporting_income_minor")==0L &&
            listOf("source_currency_code","destination_currency_code","reporting_currency_code").all{p.financeRawString(it)==code})
        for(key in listOf("category_id","debt_intent_raw_value","settlement_group_id","settlement_obligation_id","conversion_mode_raw_value","exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","counterparty_name","normalized_counterparty_key"))require(p[key]==null || p[key]==JsonNull)
        val recipient=wallet(requireNotNull(ordinaryFundReference(p,"destination_wallet_id")))
        require(recipient.kind !in setOf(null,WalletKind.INVESTMENT,WalletKind.CREDIT_CARD) && recipient.systemPurposeRawValue==null && recipient.currencyCode==code)
        ordinaryFundInstant(p,"occurred_at")
        if(adjustment.deletedAt==null) {
            require(unreconciled!=null && amount==-ordinaryFundAmount(unreconciled.payload,"amount_minor") && recipient.id==t.financeRawString("source_wallet_id") && ordinaryFundInstant(p,"occurred_at")==occurred)
        } else require(unreconciled==null)
    } else require(unreconciled==null)
    val rows=listOfNotNull(primary,adjustment)+postings;val keys=rows.map{it.entity to it.id}.toSet()
    return InvestmentOrdinaryPublicationGroup(event,primary,adjustment,postings,source.pending.filter{it.mutation.entity.table to it.mutation.recordId in keys})
}

/** Index dirty financial facts once; clean history only supplies known ancestry. */
fun investmentOrdinaryPublicationCandidates(source:InvestmentOrdinaryPublicationSnapshot):List<String> {
    source.requireCoherent()
    val ledgers=source.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table}
    val ordinary=ledgers.filter{!requiresInvestmentLedgerDomain(it.payload) && runCatching{LedgerTransactionRecord.fromCloudRecord(it).supportsOrdinaryTransactionLifecycle()}.getOrDefault(false)}.associateBy{it.id}
    val adjustments=ordinary.keys.associateBy{investmentLedgerIdentity(it,"cash-unreconciled-adjustment")}
    val canonicalOwners=buildMap<String,String> {
        for(event in ordinary.keys)for(component in ordinaryFundComponents)
            require(put(investmentLedgerIdentity(event,component),event)==null)
    }
    fun postingEvent(row:CloudRecord):String?=canonicalOwners[row.id] ?: row.payload.financeRawString("event_id")?.takeIf {
        it in ordinary && row.payload.financeRawString("cash_origin_raw_value")=="derived" &&
            row.payload.financeRawString("role_raw_value") in setOf("cashConsumption","cashTransfer")
    }
    val rowIndex=source.rows.associateBy{it.entity to it.id}
    val financialEvents=source.rows.asSequence().filter{it.entity==CloudEntity.INVESTMENT_POSTING.table}
        .mapNotNull(::postingEvent).toMutableSet()
    for(id in adjustments.keys)if(CloudEntity.LEDGER_TRANSACTION.table to id in rowIndex)financialEvents+=adjustments.getValue(id)
    val result=linkedSetOf<String>()
    for(q in source.pending) {
        val m=q.mutation;val row=rowIndex.getValue(m.entity.table to m.recordId)
        when(m.entity) {
            CloudEntity.LEDGER_TRANSACTION->{
                if(m.recordId in ordinary && m.recordId in financialEvents)result+=m.recordId
                adjustments[m.recordId]?.let(result::add)
            }
            CloudEntity.INVESTMENT_POSTING->postingEvent(row)?.let(result::add)
            else->Unit
        }
    }
    return result.sortedWith(compareBy<String>{ordinaryFundInstant(ordinary.getValue(it).payload,"occurred_at")}
        .thenBy{ordinaryFundInstant(ordinary.getValue(it).payload,"created_at")}.thenBy{it})
}
