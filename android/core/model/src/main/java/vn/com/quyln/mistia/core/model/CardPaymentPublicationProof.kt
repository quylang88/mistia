package vn.com.quyln.mistia.core.model

import java.time.YearMonth
import java.util.Currency
import kotlinx.serialization.json.*

internal fun cardPublicationIdentity(row:CloudRecord,owner:UserId,entity:CloudEntity,id:String) {
    ackIdentity(row,entity,owner,id)
    require(row.updatedAt==row.payload.financeRawString("updated_at") && row.deletedAt==row.payload.financeRawString("deleted_at") && row.financeRawDeleted(true)!=null)
    cashEventInstant(row.payload.financeRawString("created_at"));cashEventInstant(row.updatedAt)
}
internal fun cardPublicationCycle(row:CloudRecord,owner:UserId,cardId:String):DueOccurrenceRecord {
    cardPublicationIdentity(row,owner,CloudEntity.DUE_OCCURRENCE_RECORD,row.id)
    return DueOccurrenceRecord.fromCloudRecord(row).also{c->
        require(row.payload==c.toPayload() && c.sourceKindWireValue=="creditCard" && c.sourceId==cardId &&
            YearMonth.parse(c.selectedMonthKey).toString()==c.selectedMonthKey && c.statusWireValue in setOf("pending","paid","skipped"))
    }
}
internal fun cardPublicationLedger(row:CloudRecord,owner:UserId,id:String,remote:Boolean):LedgerTransactionRecord {
    cardPublicationIdentity(row,owner,CloudEntity.LEDGER_TRANSACTION,id)
    val wire=if(remote)row.payload else ordinaryPublicationPayloadForCloud(row)
    require(wire.keys.none{it.startsWith("_mistia_android_")}){"Remote or unknown local private evidence"}
    val tx=ackLedger(row.copy(payload=wire),owner,id)
    require(wire.financeRawLong("amount_minor")!=null && tx.toPayload().keys.containsAll(wire.keys))
    return tx
}
internal fun cardPublicationWallet(row:CloudRecord,owner:UserId,id:String):LedgerWalletRecord {
    cardPublicationIdentity(row,owner,CloudEntity.LEDGER_WALLET,id)
    require(row.payload.keys.none{it.startsWith("_mistia_android_")})
    return LedgerWalletRecord.fromCloudRecord(row)
}
internal fun cardPublicationNormalize(p:JsonObject)=JsonObject(p.mapValues{(key,value)->
    if(value!=JsonNull && key in setOf("created_at","updated_at","scheduled_date","paid_at","deleted_at","occurred_at","archived_at"))
        JsonPrimitive(cashEventInstant(value.jsonPrimitive.content).toString()) else value
})
internal fun cardPublicationBusiness(row:CloudRecord,withoutDeletion:Boolean=false)=cardPublicationNormalize(JsonObject(row.payload-
    setOf("sync_version","updated_at","last_modified_by_device_id")-(if(withoutDeletion)setOf("deleted_at")else emptySet())))
private fun financial(tx:LedgerTransactionRecord)=cardPublicationNormalize(tx.financialAckPayload())
private fun walletFacts(w:LedgerWalletRecord)=cardPublicationNormalize(JsonObject(w.toPayload().filterKeys{
    it in setOf("id","user_id","created_at","currency_code","kind_raw_value","deleted_at","is_archived","archived_at","system_purpose_raw_value")
}))
private fun currency(value:String?):String?=value?.financeReportingCode()?.takeIf{code->runCatching{Currency.getInstance(code).defaultFractionDigits>=0}.getOrDefault(false)}
private fun validTransfer(tx:LedgerTransactionRecord,c:DueOccurrenceRecord)=tx.supportsOrdinaryTransactionLifecycle() &&
    tx.primaryKind==TransactionPrimaryKind.TRANSFER && tx.transferSubtype==TransactionTransferSubtype.INTERNAL_TRANSFER &&
    tx.entryStatus==TransactionEntryStatus.POSTED && tx.sourceWalletId!=null && tx.sourceWalletId!=tx.destinationWalletId &&
    tx.destinationWalletId==c.sourceId && tx.amountMinor>0 && (tx.destinationAmountMinor ?: tx.amountMinor)==tx.amountMinor &&
    c.amountMinorSnapshot!=null && c.amountMinorSnapshot>0 && c.amountMinorSnapshot<=tx.amountMinor &&
    c.paidAt!=null && cashEventInstant(c.paidAt)==cashEventInstant(tx.occurredAt) &&
    currency(tx.sourceCurrencyCode)!=null && currency(tx.sourceCurrencyCode)==currency(tx.destinationCurrencyCode ?: tx.sourceCurrencyCode)
internal fun cardPublicationPending(source:CardPaymentPublicationSnapshot,id:String):CardPaymentPublicationDecision? {
    if(source.queues.any{it.mutation.entity==CloudEntity.LEDGER_TRANSACTION && it.mutation.recordId==id})
        return CardPaymentPublicationDecision.Deferred("ledger_pending")
    val canonical=listOf("cash-consumption-booked","cash-consumption-unreconciled","cash-destination-booked","cash-destination-unreconciled").map{investmentLedgerIdentity(id,it)}
    if(source.queues.any{q->q.mutation.entity==CloudEntity.INVESTMENT_POSTING &&
            (q.mutation.recordId in canonical || q.mutation.payload?.financeRawString("event_id")==id || q.mutation.payload?.financeRawString("ledger_transaction_id")==id)})
        return CardPaymentPublicationDecision.Deferred("investment_allocation_pending")
    return null
}
/** Financial authority only. Returning null is a proof, never an ACK by itself. */
internal fun cardPublicationFinancialProof(source:CardPaymentPublicationSnapshot,c:DueOccurrenceRecord,
    observed:CardPaymentPublicationObservation,deleting:Boolean):CardPaymentPublicationDecision? {
    val id=requireNotNull(c.linkedTransactionId)
    cardPublicationPending(source,id)?.let{return it}
    val local=source.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).single{it.id==id}
    val tx=cardPublicationLedger(local,source.owner,id,remote=false)
    if(!validTransfer(tx,c))return CardPaymentPublicationDecision.Conflict("invalid_paid_financial_footprint")
    if(!observed.ledger.containsKey(id))return CardPaymentPublicationDecision.NeedLedger(id)
    val remote=observed.ledger[id]?.let{cardPublicationLedger(it,source.owner,id,remote=true)}
    if(remote!=null)require(cashEventInstant(tx.createdAt)==cashEventInstant(remote.createdAt)){"Ledger birth changed"}
    if(deleting) {
        if(tx.deletedAt==null || remote!=null && remote.deletedAt==null)return CardPaymentPublicationDecision.Deferred("deleted_cycle_ledger_still_live")
        if(remote!=null && financial(tx)!=financial(remote))return CardPaymentPublicationDecision.Deferred("ledger_not_pulled")
        return null
    }
    if(tx.deletedAt!=null || tx.isArchived || remote==null)return CardPaymentPublicationDecision.Conflict("paid_ledger_unavailable")
    if(financial(tx)!=financial(remote))return CardPaymentPublicationDecision.Deferred("ledger_not_pulled")
    if(remote.isArchived || !validTransfer(remote,c))return CardPaymentPublicationDecision.Conflict("invalid_paid_financial_footprint")
    for(idWallet in listOf(requireNotNull(tx.sourceWalletId),source.cardId)) {
        if(source.queues.any{it.mutation.entity==CloudEntity.LEDGER_WALLET && it.mutation.recordId==idWallet})return CardPaymentPublicationDecision.Deferred("wallet_pending")
        if(!observed.wallets.containsKey(idWallet))return CardPaymentPublicationDecision.NeedWallet(idWallet)
        val localRow=source.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).singleOrNull{it.id==idWallet}
        val actualRow=observed.wallets[idWallet]
        if(localRow==null || actualRow==null)return CardPaymentPublicationDecision.Conflict("paid_wallet_missing")
        val w=cardPublicationWallet(localRow,source.owner,idWallet);val r=cardPublicationWallet(actualRow,source.owner,idWallet)
        require(cashEventInstant(w.createdAt)==cashEventInstant(r.createdAt)){"Wallet birth changed"}
        if(walletFacts(w)!=walletFacts(r))return CardPaymentPublicationDecision.Deferred("wallet_not_pulled")
        if(w.deletedAt!=null || currency(w.currencyCode)!=currency(tx.sourceCurrencyCode) || w.systemPurposeRawValue!=null ||
            if(idWallet==source.cardId)w.kind!=WalletKind.CREDIT_CARD else w.kind==null || w.kind in setOf(WalletKind.CREDIT_CARD,WalletKind.INVESTMENT))
            return CardPaymentPublicationDecision.Conflict("paid_wallet_currency_or_kind")
    }
    return null
}
/** A later payment cannot steal the identity of another still-live transfer. */
internal fun cardPublicationPredecessor(source:CardPaymentPublicationSnapshot,desired:DueOccurrenceRecord,old:DueOccurrenceRecord,
    observed:CardPaymentPublicationObservation):CardPaymentPublicationDecision? {
    val oldId=old.linkedTransactionId ?: return CardPaymentPublicationDecision.Conflict("paid_predecessor_link_missing")
    if(old.statusWireValue!="paid" || old.paidAt==null || desired.paidAt==null ||
        !cashEventInstant(desired.paidAt).isAfter(cashEventInstant(old.paidAt)) ||
        old.deletedAt!=null && !cashEventInstant(desired.paidAt).isAfter(cashEventInstant(old.deletedAt)))
        return CardPaymentPublicationDecision.Conflict("paid_predecessor_not_earlier")
    cardPublicationPending(source,oldId)?.let{return it}
    val localRow=source.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).singleOrNull{it.id==oldId}
        ?: return CardPaymentPublicationDecision.Conflict("paid_predecessor_identity_missing")
    val local=cardPublicationLedger(localRow,source.owner,oldId,remote=false)
    if(oldId==desired.linkedTransactionId) {
        // The ordinary publisher may reuse one ledger identity after undo. Its
        // actual newer occurredAt and the cycle's strict later date are causal.
        if(local.deletedAt!=null || local.isArchived || !validTransfer(local,desired))return CardPaymentPublicationDecision.Conflict("paid_predecessor_not_replaced")
        return null
    }
    if(local.deletedAt==null || !validTransfer(local,old) || !cashEventInstant(desired.paidAt).isAfter(cashEventInstant(local.deletedAt)))
        return CardPaymentPublicationDecision.Conflict("paid_predecessor_still_live")
    if(!observed.ledger.containsKey(oldId))return CardPaymentPublicationDecision.NeedLedger(oldId)
    val remote=observed.ledger[oldId]?.let{cardPublicationLedger(it,source.owner,oldId,remote=true)}
    if(remote!=null) {
        require(cashEventInstant(local.createdAt)==cashEventInstant(remote.createdAt)){"Predecessor birth changed"}
        if(remote.deletedAt==null)return CardPaymentPublicationDecision.Conflict("paid_predecessor_still_live")
        if(financial(local)!=financial(remote))return CardPaymentPublicationDecision.Deferred("predecessor_not_pulled")
    }
    return null
}
