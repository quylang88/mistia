package vn.com.quyln.mistia.core.model

import java.time.*
import java.util.UUID
import java.math.BigInteger
import kotlinx.serialization.json.*

internal class BillInvestmentPlanner(private val source:BillMoneySnapshot,private val catalog:SystemCategoryCatalog,
    private val device:String,private val now:String,private val zone:ZoneId) {
    private val owner=source.owner
    private val records=source.recordsByEntity
    private val bill:RecurringBillPlanRecord
    private val occurrences:List<DueOccurrenceRecord>
    private val cycle:List<DueOccurrenceRecord>
    private val wallets:List<LedgerWalletRecord>
    private val categories:List<TransactionCategoryRecord>
    private val profiles:List<CreditCardProfileRecord>
    private val transactions:List<LedgerTransactionRecord>
    init {
        require(records.keys==CloudEntity.entries.toSet() && source.sourceKind==DueSourceKind.RECURRING_BILL)
        require(financeRawUuid(device)==device);Instant.parse(now)
        records.forEach{(entity,rows)->
            require(rows.map{it.id}.distinct().size==rows.size)
            rows.forEach{row->
                require(row.financeRawIdentity(owner,entity,true) && row.financeRawDeleted(true)!=null)
                val body=row.payload["deleted_at"]?.takeUnless{it==JsonNull}?.let{
                    if(it !is JsonPrimitive || !it.isString)conflict()
                    Instant.parse(it.content).toString()
                }
                if(body!=row.deletedAt?.let{Instant.parse(it).toString()})conflict()
            }
        }
        require(records.getValue(CloudEntity.RECURRING_BILL_PLAN).singleOrNull{it.id==source.bill.id}==source.bill)
        bill=RecurringBillPlanRecord.fromCloudRecord(source.bill)
        if(bill.ownerUserId!=owner.value || bill.deletedAt!=null || bill.isArchived)fail(BillPaymentError.NOT_FOUND)
        occurrences=rows(CloudEntity.DUE_OCCURRENCE_RECORD).map(DueOccurrenceRecord::fromCloudRecord)
        occurrences.filter{it.deletedAt==null && it.sourceId==bill.id && (it.sourceKindWireValue=="recurringBill" || it.sourceKindWireValue !in DueSourceKind.entries.map{kind->kind.wireValue})}.forEach{
            if(it.sourceKindWireValue!="recurringBill" || runCatching{java.time.YearMonth.parse(it.selectedMonthKey)}.isFailure || it.statusWireValue !in DueStatus.entries.map{status->status.wireValue})
                fail(BillPaymentError.UNSUPPORTED_LINKED_STATE)
        }
        cycle=occurrences.filter{it.sourceKind==DueSourceKind.RECURRING_BILL && it.sourceId==bill.id && it.selectedMonthKey==source.month.toString()}
        wallets=rows(CloudEntity.LEDGER_WALLET).map(LedgerWalletRecord::fromCloudRecord).filter{it.deletedAt==null}
        categories=rows(CloudEntity.TRANSACTION_CATEGORY).map(TransactionCategoryRecord::fromCloudRecord)
        profiles=rows(CloudEntity.CREDIT_CARD_PROFILE).map(CreditCardProfileRecord::fromCloudRecord).filter{it.deletedAt==null}
        transactions=rows(CloudEntity.LEDGER_TRANSACTION).map(LedgerTransactionRecord::fromCloudRecord)
        moneySnapshot().requireValid()
    }
    private fun rows(entity:CloudEntity)=records.getValue(entity)
    private fun moneySnapshot()=TransactionInvestmentSaveSnapshot(owner,records.filterKeys{it in TransactionInvestmentSaveSnapshot.entities})
    private fun fail(reason:BillPaymentError):Nothing=throw BillPaymentException(reason)
    private fun conflict():Nothing=throw InvestmentFundUsageException(InvestmentFundUsageError.EVENT_CONFLICT)
    private fun context(context:BillInvestmentOperationContext):String {
        val creation=context.creation
        if(financeRawUuid(creation.id)!=creation.id || context.adjustmentTitle.isBlank() || context.accountingCurrency.financeReportingCode()==null)conflict()
        return runCatching{Instant.parse(creation.createdAt).also{require(it<=Instant.parse(now))}.toString()}.getOrElse{conflict()}
    }
    private fun expected(expected:RecurringBillPlanRecord?) {
        if(expected==null || !bill.matchesBillPaymentSource(expected))fail(BillPaymentError.SOURCE_CHANGED)
    }
    fun plan(operation:BillInvestmentMoneyOperation):BillInvestmentMoneyPlan {
        require(source.automaticPaymentNotification==null || (operation is BillInvestmentMoneyOperation.Pay && operation.request.automatic)) {
            "Automatic bill notification requires an automatic payment"
        }
        return when(operation) {
            is BillInvestmentMoneyOperation.Pay->pay(operation.request,operation.presentation)
            is BillInvestmentMoneyOperation.Undo->undo(operation.request)
        }
    }
    private fun pay(request:BillPaymentRequest,presentation:BillAutomaticPaymentText?):BillInvestmentMoneyPlan {
        if(presentation!=null && !request.automatic)fail(BillPaymentError.INVALID_AUTO_PAY_OVERRIDE)
        presentation?.let{require(it.transactionTitle.isNotBlank() && it.successTitle.isNotBlank())}
        if(request.billId.value!=bill.id || request.month!=source.month)fail(BillPaymentError.SOURCE_CHANGED)
        if(!request.automatic)expected(request.expectedBill)
        val context=requireNotNull(request.investment){"Bill payment requires a frozen investment operation"};val at=context(context)
        if(request.automatic) {
            if(request.walletId!=null || request.amountMinorOverride!=null || context.consent!=null)fail(BillPaymentError.INVALID_AUTO_PAY_OVERRIDE)
            if(bill.autoPayEnabled!=true || bill.isPaused)fail(BillPaymentError.AUTO_PAY_NOT_DUE)
        }
        val due=recurringBillDueRows(owner,listOf(bill),occurrences.filter{it.deletedAt==null},source.month,zone).singleOrNull() ?: fail(BillPaymentError.NOT_SCHEDULED)
        if(request.automatic && due.autoPayDate?.atZone(zone)?.toLocalDate()!=Instant.parse(now).atZone(zone).toLocalDate())fail(BillPaymentError.AUTO_PAY_NOT_DUE)
        if(!request.automatic && due.amountMinor!=request.expectedDueAmountMinor)fail(BillPaymentError.SOURCE_CHANGED)
        val wallet=wallets.singleOrNull{it.id==(request.walletId?.value ?: bill.paymentWalletId) && !it.isArchived && it.kind!=null && it.kind!=WalletKind.INVESTMENT}
            ?: fail(BillPaymentError.INVALID_WALLET)
        if(!billPaymentCurrenciesMatch(bill.currencyCode,wallet.currencyCode))fail(BillPaymentError.WALLET_CURRENCY_MISMATCH)
        val amount=(request.amountMinorOverride ?: due.amountMinor)?.takeIf{it>0} ?: fail(BillPaymentError.MISSING_AMOUNT)
        val live=cycle.filter{it.deletedAt==null}
        val oldIds=cycle.filter{it.deletedAt!=null && it.status==DueStatus.PAID}.mapNotNull{it.linkedTransactionId}.toSet()
        if(oldIds.size>1)fail(BillPaymentError.UNSUPPORTED_LINKED_STATE)
        val known=live.isNotEmpty() && live.all{it.status==DueStatus.PAID && it.linkedTransactionId!=null}
        if(!known && live.any{it.status!=DueStatus.PENDING || it.linkedTransactionId!=null || it.paidAt!=null})fail(BillPaymentError.CYCLE_NOT_PENDING)
        val targetId=if(known)live.mapNotNull{it.linkedTransactionId}.distinct().singleOrNull() ?: conflict() else oldIds.singleOrNull() ?: context.creation.id
        val raw=rows(CloudEntity.LEDGER_TRANSACTION).singleOrNull{it.id==targetId}
        val previous=raw?.let(LedgerTransactionRecord::fromCloudRecord)
        if(!known && ((oldIds.isEmpty() && raw!=null) || (oldIds.isNotEmpty() && (previous==null || previous.deletedAt==null))))conflict()
        previous?.let{requireOrdinaryPayment(it)}
        if(previous?.deletedAt!=null) {
            val lastUndo=(cycle.filter{it.linkedTransactionId==targetId}.mapNotNull{it.deletedAt}+previous.deletedAt).map{Instant.parse(it)}.maxOrNull()
            if(lastUndo!=null && !Instant.parse(at).isAfter(lastUndo))fail(BillPaymentError.SOURCE_CHANGED)
        }
        val categoryWrites=mutableListOf<TransactionCategoryRecord>()
        val category=category(categoryWrites,at)
        val priorClock=(cycle.filter{it.deletedAt!=null}.map{Instant.parse(it.updatedAt)}+listOfNotNull(previous?.takeIf{it.deletedAt!=null}?.updatedAt?.let(Instant::parse))).maxOrNull()
        val timestamp=if(priorClock!=null && !Instant.parse(at).isAfter(priorClock))priorClock.plusMillis(1).toString() else at
        val mutation=TransactionDraft(id=targetId,primaryKind=TransactionPrimaryKind.EXPENSE,title=presentation?.transactionTitle ?: bill.name,amountMinor=amount,occurredAt=at,
            sourceWalletId=wallet.id,categoryId=category.id).toMutation(owner,previous,wallet,null,category.copy(isArchived=false),device,timestamp)
        val primary=mutation.record.let{if(previous==null)it.copy(createdAt=at)else it}.toCloudRecord().let{r->r.copy(payload=JsonObject(raw?.payload.orEmpty()+r.payload))}
        if(known) {
            if(raw==null || previous==null || previous.deletedAt!=null || !sameBillFinancial(primary.payload,raw.payload) ||
                live.any{it.linkedTransactionId!=targetId || it.amountMinorSnapshot!=amount || it.paidAt==null || Instant.parse(it.scheduledDate)!=due.dueDate} ||
                occurrences.any{it.deletedAt==null && it.linkedTransactionId==targetId && it.id !in live.map{c->c.id}})conflict()
            if(targetId==context.creation.id && Instant.parse(previous.createdAt)!=Instant.parse(at))conflict()
            requireCompleteDerived(listOf(raw),context)
            return BillInvestmentMoneyPlan(SavedBillPayment(previous,live),emptyList())
        }
        val active=transactions.filter{it.deletedAt==null}
        if(previous?.isLockedByPaidCreditCardStatement(wallets,profiles,categories,active,rows(CloudEntity.DUE_OCCURRENCE_RECORD).filter{it.deletedAt==null},zone,Instant.parse(now))==true ||
            mutation.record.isLockedByPaidCreditCardStatement(wallets,profiles,categories,active.filterNot{it.id==targetId},rows(CloudEntity.DUE_OCCURRENCE_RECORD).filter{it.deletedAt==null},zone,Instant.parse(now)))
            throw TransactionValidationException(TransactionValidationError.PAID_CREDIT_CARD_STATEMENT)
        requireExactOrdinaryAffordability(moneySnapshot(),LedgerTransactionRecord.fromCloudRecord(primary),profiles,null)
        val reused=cycle.filter{it.deletedAt==null || (it.status==DueStatus.PAID && it.linkedTransactionId==targetId)}
        val paid=if(reused.isEmpty())listOf(DueOccurrenceRecord(UUID.nameUUIDFromBytes("vn.com.quyln.mistia.bill-cycle.${owner.value}.${bill.id}.${source.month}.${context.creation.id}".toByteArray(Charsets.UTF_8)).toString(),owner.value,
            "recurringBill",bill.id,source.month.toString(),due.dueDate.toString(),amount,"paid",timestamp,targetId,timestamp,timestamp,null,0,device)) else reused.map{
            it.copy(scheduledDate=due.dueDate.toString(),amountMinorSnapshot=amount,statusWireValue="paid",paidAt=timestamp,linkedTransactionId=targetId,updatedAt=timestamp,deletedAt=null,lastModifiedByDeviceId=device)
        }
        val base=categoryWrites.map{it.toCloudRecord() to it.bootstrapMutation()}+listOf(primary to mutation.pending.copy(payload=primary.payload))+
            paid.map{preserve(it.toCloudRecord() to it.pendingMutation())}
        val notification=if(request.automatic && presentation?.emitNotification==true)
            billInvestmentSuccessNotification(owner,bill,source.month,amount,wallet.id,due.dueDate.toString(),presentation,now)else null
        require(source.automaticPaymentNotification==notification){"Bill automatic success notification does not match its payment"}
        source.requireValidMutations(base);source.requireInstallmentMoneyCoherence(base)
        val effects=effects(base,context,request.automatic)
        return BillInvestmentMoneyPlan(SavedBillPayment(LedgerTransactionRecord.fromCloudRecord(primary),paid),base+effects)
    }
    private fun category(created:MutableList<TransactionCategoryRecord>,at:String):TransactionCategoryRecord {
        val definitions=catalog.definitions
        val selected=categories.firstOrNull{it.id==bill.categoryId && it.deletedAt==null}
        val key=selected?.systemKey?.takeIf{candidate->definitions.any{it.key==candidate}} ?: definitions.firstOrNull{it.isActive && it.iconSymbolName==bill.iconSymbolName}?.key ?: "billing"
        fun ensure(key:String):TransactionCategoryRecord {
            val candidates=categories.filter{it.systemKey==key}
            candidates.filter{it.deletedAt==null}.maxWithOrNull(compareBy<TransactionCategoryRecord>({it.id==SystemCategoryIdentity.cloudId(key,owner)},{it.syncVersion},{Instant.parse(it.updatedAt)},{it.id}))?.let{return it}
            if(candidates.isNotEmpty())fail(BillPaymentError.INVALID_CATEGORY)
            val definition=definitions.singleOrNull{it.key==key} ?: fail(BillPaymentError.INVALID_CATEGORY)
            val parent=definition.parentKey?.let(::ensure)
            val id=SystemCategoryIdentity.cloudId(key,owner)
            if(categories.any{it.id==id})fail(BillPaymentError.INVALID_CATEGORY)
            val sort=(categories+created).filter{it.parentCategoryId==parent?.id && it.kind==definition.kind}.maxOfOrNull{it.sortOrder}?.let{Math.addExact(it,1)} ?: 0
            return definition.copy(isActive=true,sortOrder=sort).seedRecord(owner,parent?.id,device,at).copy(isArchived=!definition.isActive).also{created+=it}
        }
        val child=ensure(key)
        if(child.kind!=TransactionCategoryKind.EXPENSE || child.hierarchyRole!=CategoryHierarchyRole.CHILD ||
            (categories+created).none{it.id==child.parentCategoryId && it.kind==TransactionCategoryKind.EXPENSE && it.hierarchyRole==CategoryHierarchyRole.PARENT && it.deletedAt==null})fail(BillPaymentError.INVALID_CATEGORY)
        return child
    }
    private fun requireOrdinaryPayment(tx:LedgerTransactionRecord) {
        if(tx.ownerUserId!=owner.value || tx.primaryKind!=TransactionPrimaryKind.EXPENSE || tx.transferSubtype!=null || tx.debtIntent!=null || tx.entryStatus!=TransactionEntryStatus.POSTED ||
            tx.settlementGroupId!=null || tx.settlementObligationId!=null || tx.settlementRoleWireValue!=null || tx.reportingExpenseMinor!=null || tx.reportingIncomeMinor!=null || tx.id in source.receiptTransactionIds)
            fail(BillPaymentError.UNSUPPORTED_LINKED_STATE)
        rows(CloudEntity.INVESTMENT_POSTING).filter{it.deletedAt==null && (it.payload.financeRawReference("event_id").id==tx.id || it.payload.financeRawReference("ledger_transaction_id").id==tx.id)}.forEach{
            if(it.payload.financeRawString("cash_origin_raw_value")!="derived" || it.payload.financeRawString("role_raw_value") !in setOf("cashConsumption","cashTransfer"))fail(BillPaymentError.UNSUPPORTED_LINKED_STATE)
        }
    }
    private fun undo(request:BillInvestmentUndoRequest):BillInvestmentMoneyPlan {
        expected(request.expected)
        if(request.month!=source.month)fail(BillPaymentError.SOURCE_CHANGED)
        val context=request.investment;val at=context(context)
        val paid=cycle.filter{it.deletedAt==null && it.status==DueStatus.PAID}
        if(paid.isEmpty()) {
            val done=cycle.filter{it.status==DueStatus.PAID && it.deletedAt?.let{t->Instant.parse(t)==Instant.parse(at)}==true}
            if(done.isEmpty() || cycle.any{it.deletedAt==null})conflict()
            // The visible marker binds the request; legacy compound markers bind their own expenses.
            if(done.none{it.linkedTransactionId==request.expectedLinkedTransactionId &&
                    (it.amountMinorSnapshot ?: bill.amountMinor)==request.expectedAmountMinor})conflict()
            val ids=done.mapNotNull{it.linkedTransactionId}.toSet()
            if(cycle.any{it.linkedTransactionId in ids && it !in done} || occurrences.any{it.deletedAt==null && it.linkedTransactionId in ids})conflict()
            val deleted=ids.map{id->rows(CloudEntity.LEDGER_TRANSACTION).singleOrNull{it.id==id} ?: conflict()}
            deleted.forEach{row->
                if(row.deletedAt?.let{t->Instant.parse(t)<=Instant.parse(at)}!=true)conflict()
                val tx=LedgerTransactionRecord.fromCloudRecord(row);requireOrdinaryPayment(tx)
                if(done.any{it.linkedTransactionId==tx.id && it.amountMinorSnapshot!=null && it.amountMinorSnapshot!=tx.amountMinor})conflict()
            }
            requireCompleteDerived(deleted,context)
            return BillInvestmentMoneyPlan(null,emptyList())
        }
        if(cycle.any{it.deletedAt==null && it.status!=DueStatus.PAID})fail(BillPaymentError.UNSUPPORTED_LINKED_STATE)
        val due=recurringBillDueRows(owner,listOf(bill),occurrences.filter{it.deletedAt==null},source.month,zone).singleOrNull() ?: fail(BillPaymentError.NOT_SCHEDULED)
        if(due.amountMinor!=request.expectedAmountMinor || due.linkedTransactionId!=request.expectedLinkedTransactionId)fail(BillPaymentError.SOURCE_CHANGED)
        val ids=paid.mapNotNull{it.linkedTransactionId}.toSet()
        if(occurrences.any{it.deletedAt==null && it.id !in paid.map{c->c.id} && it.linkedTransactionId in ids})fail(BillPaymentError.UNSUPPORTED_LINKED_STATE)
        val expenses=ids.map{id->transactions.singleOrNull{it.id==id} ?: fail(BillPaymentError.UNSUPPORTED_LINKED_STATE)}
        expenses.forEach{tx->
            if(tx.deletedAt?.let{Instant.parse(it)>Instant.parse(at)}==true)conflict()
            requireOrdinaryPayment(tx)
            if(paid.any{it.linkedTransactionId==tx.id && it.amountMinorSnapshot!=null && it.amountMinorSnapshot!=tx.amountMinor})fail(BillPaymentError.UNSUPPORTED_LINKED_STATE)
            if(tx.deletedAt==null && tx.isLockedByPaidCreditCardStatement(wallets,profiles,categories,transactions.filter{it.deletedAt==null},rows(CloudEntity.DUE_OCCURRENCE_RECORD).filter{it.deletedAt==null},zone,Instant.parse(now)))
                throw TransactionValidationException(TransactionValidationError.PAID_CREDIT_CARD_STATEMENT)
        }
        val base=expenses.filter{it.deletedAt==null}.map{old->
            val tx=old.copy(deletedAt=at,updatedAt=at,lastModifiedByUserId=owner.value,lastModifiedByDeviceId=device)
            preserve(tx.toCloudRecord() to PendingMutation(CloudEntity.LEDGER_TRANSACTION,tx.id,owner.value,MutationKind.DELETE,tx.toPayload(),at,tx.syncVersion,device))
        }+paid.map{old->val deleted=old.copy(deletedAt=at,updatedAt=at,lastModifiedByDeviceId=device);preserve(deleted.toCloudRecord() to deleted.pendingMutation(MutationKind.DELETE))}
        source.requireValidMutations(base);source.requireInstallmentMoneyCoherence(base)
        return BillInvestmentMoneyPlan(null,base+effects(base,context,false))
    }
    private fun preserve(write:Pair<CloudRecord,PendingMutation>):Pair<CloudRecord,PendingMutation> {
        val old=records.getValue(requireNotNull(CloudEntity.fromTable(write.first.entity))).singleOrNull{it.id==write.first.id} ?: return write
        val payload=JsonObject(old.payload+write.first.payload);return write.first.copy(payload=payload) to write.second.copy(payload=payload)
    }
    private fun fundSnapshot(primary:List<CloudRecord> = emptyList()):InvestmentCashReadSnapshot {
        val old=moneySnapshot().investmentSnapshot()
        return old.copy(rows=old.rows.filter{row->primary.none{it.entity==row.entity && it.id==row.id}}+primary)
    }
    private fun derived(finalPrimary:List<CloudRecord>,context:BillInvestmentOperationContext):List<Pair<CloudRecord,PendingMutation>> {
        if(finalPrimary.isEmpty())return emptyList()
        val chosen=finalPrimary.sortedBy{it.id}.first()
        var final=fundSnapshot(finalPrimary)
        if(chosen.deletedAt!=null)final=final.copy(rows=final.rows.map{row->if(row.entity==chosen.entity && row.id==chosen.id)
            row.copy(deletedAt=null,payload=JsonObject(row.payload+buildJsonObject{put("deleted_at",JsonNull);put("is_archived",true)}))else row})
        // Read-only final-state derivation. The public operation still requires its own full-source consent.
        val proof=reviewInvestmentFundUsage(final,context.accountingCurrency,chosen)
        return planInvestmentFundUsage(final,context.accountingCurrency,chosen,proof.consent,context.adjustmentTitle,device,now).mutations
    }
    private fun requireCompleteDerived(primary:List<CloudRecord>,context:BillInvestmentOperationContext) {
        if(derived(primary,context).isNotEmpty())conflict()
    }
    private fun requireCurrentCanonicalMoney(context:BillInvestmentOperationContext) {
        val markerId=UUID.nameUUIDFromBytes("vn.com.quyln.mistia.bill-read-proof.${owner.value}.${context.creation.id}".toByteArray(Charsets.UTF_8)).toString()
        if(records.values.flatten().any{it.id==markerId} || rows(CloudEntity.INVESTMENT_POSTING).any{
                it.payload.financeRawReference("event_id").id==markerId || it.payload.financeRawReference("ledger_transaction_id").id==markerId})conflict()
        // An archived, zero-effect read marker proves the existing allocation without changing a real event.
        // It is never persisted or included in the user's proposal/mutations.
        val marker=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,markerId,owner.value,buildJsonObject {
            put("id",markerId);put("user_id",owner.value);put("sync_version",0L);put("created_at",context.creation.createdAt);put("updated_at",now)
            put("occurred_at",context.creation.createdAt);put("deleted_at",JsonNull);put("is_archived",true);put("archived_at",context.creation.createdAt)
            put("entry_status_raw_value","posted");put("primary_kind_raw_value","expense");put("amount_minor",1L);put("settlement_role_raw_value",JsonNull)
        },now,null,0)
        for((record,_) in derived(listOf(marker),context)) {
            val old=records.getValue(requireNotNull(CloudEntity.fromTable(record.entity))).singleOrNull{it.id==record.id} ?: conflict()
            // A locale-only generated title refresh has no monetary effect; preserve the normal presentation behavior.
            val body=if(record.entity==CloudEntity.LEDGER_TRANSACTION.table && old.payload.financeRawString("settlement_role_raw_value")=="investmentReserveUse")
                JsonObject(record.payload.filterKeys{it!="title"})else record.payload
            if(!sameBillFinancial(body,old.payload))conflict()
        }
    }
    private fun effects(base:List<Pair<CloudRecord,PendingMutation>>,context:BillInvestmentOperationContext,automatic:Boolean):List<Pair<CloudRecord,PendingMutation>> {
        requireCurrentCanonicalMoney(context)
        val primary=base.map{it.first}.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table}
        val old=fundSnapshot();val next=fundSnapshot(primary)
        fun timeline(snapshot:InvestmentCashReadSnapshot)=try{investmentFundUsageTimeline(snapshot,context.accountingCurrency)}
            catch(error:InvestmentFundTimelineException){throw InvestmentFundUsageException(if(error.reason==InvestmentFundTimelineError.UNSUPPORTED_CURRENCY_CONVERSION)InvestmentFundUsageError.CURRENCY_MISMATCH else InvestmentFundUsageError.UNREADABLE_SOURCE)}
        val before=timeline(old);val after=timeline(next)
        val affected=(before.usages.keys+after.usages.keys).flatMap{id->
            val a=before.usages[id];val b=after.usages[id]
            if(a?.investmentToUseMinor==b?.investmentToUseMinor || ((a?.investmentToUseMinor ?: BigInteger.ZERO)==BigInteger.ZERO && (b?.investmentToUseMinor ?: BigInteger.ZERO)==BigInteger.ZERO))emptyList()
            else listOfNotNull(a?.walletId,b?.walletId)
        }.toSet()
        fun total(t:InvestmentFundTimeline,id:String)=t.usages.values.filter{it.walletId==id}.fold(BigInteger.ZERO){sum,it->sum+it.investmentToUseMinor}
        val changes=affected.map{id->InvestmentFundTimelineWalletChange(id,wallets.single{it.id==id}.currencyCode,total(before,id),total(after,id),after.availableByWalletId[id] ?: BigInteger.ZERO)}
            .sortedWith(compareByDescending<InvestmentFundTimelineWalletChange>{(it.proposedMinor-it.previousMinor).abs()}.thenBy{it.walletId})
        val sourceToken=RecordConflictResolver.semanticFingerprint(buildJsonObject {
            put("owner",owner.value);put("bill",bill.id);put("month",source.month.toString())
            put("rows",JsonArray(records.values.flatten().sortedWith(compareBy(CloudRecord::entity,CloudRecord::id)).map{row->buildJsonObject{put("entity",row.entity);put("body",billSemantic(row.payload))}}))
            put("receipts",JsonArray(source.receiptTransactionIds.sorted().map(::JsonPrimitive)))
        })
        val proposalToken=RecordConflictResolver.semanticFingerprint(buildJsonObject{put("rows",JsonArray(base.map{it.first}.sortedWith(compareBy(CloudRecord::entity,CloudRecord::id)).map{row->buildJsonObject{put("entity",row.entity);put("body",billSemantic(row.payload).let{body->if(row.entity==CloudEntity.DUE_OCCURRENCE_RECORD.table)JsonObject(body.filterKeys{it!="paid_at"})else body})}}))})
        val review=InvestmentFundUsageReview(InvestmentFundUsageConsent(owner.value,context.creation.id,proposalToken,sourceToken),InvestmentFundTimelineComparison(before,after,changes),changes.isNotEmpty())
        val planned=derived(primary,context)
        if(automatic && review.requiresConfirmation)fail(BillPaymentError.INVESTMENT_USAGE_UNAVAILABLE)
        if(context.consent==null && review.requiresConfirmation)throw InvestmentFundUsageConfirmationRequired(review)
        if(context.consent!=null && context.consent!=review.consent)throw InvestmentFundUsageException(InvestmentFundUsageError.STALE_CONSENT)
        return planned
    }
}

private fun billSemantic(payload:JsonObject):JsonObject=buildJsonObject {
    payload.filterKeys{it !in setOf("sync_version","updated_at","last_modified_by_device_id","last_modified_by_user_id")}.forEach{(key,value)->
        put(key,if(key in setOf("created_at","occurred_at","deleted_at","archived_at","scheduled_date","paid_at") && value is JsonPrimitive && value.isString)
            runCatching{JsonPrimitive(Instant.parse(value.content).toString())}.getOrDefault(value)else value)
    }
}
private fun sameBillFinancial(expected:JsonObject,actual:JsonObject)=billSemantic(expected).all{(key,value)->value==(billSemantic(actual)[key] ?: JsonNull)}
