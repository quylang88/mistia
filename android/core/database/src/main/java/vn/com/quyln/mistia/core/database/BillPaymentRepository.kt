package vn.com.quyln.mistia.core.database

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import vn.com.quyln.mistia.core.model.*

internal class OfflineBillPaymentRepository(
    private val store: LocalStore,
    private val zone: ZoneId,
    private val catalog: SystemCategoryCatalog?,
    private val automaticText: ((RecurringBillPlanRecord,Long)->BillAutomaticPaymentText)? = null,
) : BillPaymentRepository {
    override suspend fun payRecurringBill(owner: UserId, request: BillPaymentRequest, deviceId: String, now: String): Result<SavedBillPayment> = result {
        val snapshot = snapshot(owner, request.billId, request.month)
        val bill = RecurringBillPlanRecord.fromCloudRecord(snapshot.bill)
        if(request.automatic) {
            if(request.walletId!=null || request.amountMinorOverride!=null) fail(BillPaymentError.INVALID_AUTO_PAY_OVERRIDE)
            if(bill.autoPayEnabled!=true || bill.isPaused) fail(BillPaymentError.AUTO_PAY_NOT_DUE)
        }
        val occurrences = owned(snapshot, CloudEntity.DUE_OCCURRENCE_RECORD).map(DueOccurrenceRecord::fromCloudRecord)
        val cycle = occurrences.filter { it.deletedAt==null && it.sourceKindWireValue=="recurringBill" && it.sourceId==bill.id && it.selectedMonthKey==request.month.toString() }
        if (cycle.any { it.status!=DueStatus.PENDING || it.linkedTransactionId!=null }) fail(BillPaymentError.CYCLE_NOT_PENDING)
        // Reuse the prior payment identity when undo is followed by repayment.
        // An in-flight DELETE can then conflict with one UPSERT, never a second expense ID.
        val undone = occurrences.filter { it.deletedAt!=null && it.sourceKindWireValue=="recurringBill" &&
            it.sourceId==bill.id && it.selectedMonthKey==request.month.toString() && it.status==DueStatus.PAID && it.linkedTransactionId!=null }
        val oldLinked = undone.mapNotNull { it.linkedTransactionId }.toSet()
        if (oldLinked.size>1) fail(BillPaymentError.UNSUPPORTED_LINKED_STATE)
        val allTransactions = owned(snapshot, CloudEntity.LEDGER_TRANSACTION).map(LedgerTransactionRecord::fromCloudRecord)
        val previous = oldLinked.singleOrNull()?.let { id ->
            val tx = allTransactions.singleOrNull { it.id==id } ?: fail(BillPaymentError.UNSUPPORTED_LINKED_STATE)
            if (tx.deletedAt==null) fail(BillPaymentError.CYCLE_NOT_PENDING)
            if (tx.primaryKind!=TransactionPrimaryKind.EXPENSE || tx.isArchived || tx.settlementGroupId!=null ||
                tx.settlementObligationId!=null || tx.settlementRoleWireValue!=null || tx.id in snapshot.receiptTransactionIds ||
                tx.reportingAmountMinor!=null || tx.reportingExpenseMinor!=null || tx.reportingIncomeMinor!=null ||
                !billPaymentCurrenciesMatch(tx.sourceCurrencyCode.orEmpty(),bill.currencyCode) ||
                occurrences.any { it.deletedAt==null && it.linkedTransactionId==id } ||
                owned(snapshot,CloudEntity.INVESTMENT_POSTING).any { it.deletedAt==null && (it.payload["ledger_transaction_id"] as? JsonPrimitive)?.content==id })
                fail(BillPaymentError.UNSUPPORTED_LINKED_STATE)
            tx
        }
        val due = recurringBillDueRows(owner, listOf(bill), occurrences.filter { it.deletedAt==null }, request.month, zone).singleOrNull()
            ?: fail(BillPaymentError.NOT_SCHEDULED)
        if(request.automatic && due.autoPayDate?.atZone(zone)?.toLocalDate()!=Instant.parse(now).atZone(zone).toLocalDate())
            fail(BillPaymentError.AUTO_PAY_NOT_DUE)
        val wallets = owned(snapshot, CloudEntity.LEDGER_WALLET).map(LedgerWalletRecord::fromCloudRecord).filter { it.deletedAt==null }
        val walletID = request.walletId?.value ?: bill.paymentWalletId
        val wallet = wallets.singleOrNull { it.id==walletID && !it.isArchived && it.kind!=null }
            ?: fail(BillPaymentError.INVALID_WALLET)
        if (!billPaymentCurrenciesMatch(bill.currencyCode, wallet.currencyCode)) fail(BillPaymentError.WALLET_CURRENCY_MISMATCH)
        val amount = (request.amountMinorOverride ?: due.amountMinor)?.takeIf { it>0 } ?: fail(BillPaymentError.MISSING_AMOUNT)
        val activePostings = owned(snapshot, CloudEntity.INVESTMENT_POSTING).filter { it.deletedAt==null }
        if (wallet.kind==WalletKind.INVESTMENT || activePostings.any { (it.payload["wallet_id"] as? JsonPrimitive)?.content==wallet.id })
            fail(BillPaymentError.INVESTMENT_USAGE_UNAVAILABLE)
        val categories = owned(snapshot, CloudEntity.TRANSACTION_CATEGORY).map(TransactionCategoryRecord::fromCloudRecord).filter { it.deletedAt==null }
        val definitions = requireNotNull(catalog) { "System category catalog unavailable" }.definitions
        val selected = categories.firstOrNull { it.id==bill.categoryId }
        val key = selected?.systemKey?.takeIf { candidate -> definitions.any { it.key==candidate } }
            ?: definitions.firstOrNull { it.isActive && it.iconSymbolName==bill.iconSymbolName }?.key ?: "billing"
        val categoryWrites = mutableListOf<TransactionCategoryRecord>()
        val allCategories = owned(snapshot, CloudEntity.TRANSACTION_CATEGORY).map(TransactionCategoryRecord::fromCloudRecord)
        fun ensureCategory(systemKey: String): TransactionCategoryRecord {
            val candidates = allCategories.filter { it.systemKey==systemKey }
            candidates.filter { it.deletedAt==null }.maxWithOrNull(compareBy<TransactionCategoryRecord>(
                {it.id==SystemCategoryIdentity.cloudId(systemKey,owner)}, {it.syncVersion}, {Instant.parse(it.updatedAt)}, {it.id}))?.let { return it }
            if (candidates.isNotEmpty()) fail(BillPaymentError.INVALID_CATEGORY) // Preserve user tombstones.
            val definition = definitions.singleOrNull { it.key==systemKey } ?: fail(BillPaymentError.INVALID_CATEGORY)
            val parent = definition.parentKey?.let(::ensureCategory)
            val id = SystemCategoryIdentity.cloudId(systemKey,owner)
            if (snapshot.recordsByEntity.getValue(CloudEntity.TRANSACTION_CATEGORY).any { it.id==id }) fail(BillPaymentError.INVALID_CATEGORY)
            val sort = (categories+categoryWrites).filter { it.parentCategoryId==parent?.id && it.kind==definition.kind }
                .maxOfOrNull { it.sortOrder }?.let { Math.addExact(it,1) } ?: 0
            return definition.copy(isActive=true,sortOrder=sort).seedRecord(owner,parent?.id,deviceId,now)
                .copy(isArchived=!definition.isActive).also { categoryWrites+=it }
        }
        val category = ensureCategory(key)
        if (category.kind!=TransactionCategoryKind.EXPENSE || category.hierarchyRole!=CategoryHierarchyRole.CHILD)
            fail(BillPaymentError.INVALID_CATEGORY)
        val parent = (categories+categoryWrites).firstOrNull { it.id==category.parentCategoryId && it.kind==TransactionCategoryKind.EXPENSE && it.hierarchyRole==CategoryHierarchyRole.PARENT }
            ?: fail(BillPaymentError.INVALID_CATEGORY)
        require(parent.ownerUserId==owner.value)
        val occurredAt = Instant.parse(now)
        val priorClock = (undone.map { Instant.parse(it.updatedAt) }+listOfNotNull(previous?.updatedAt?.let(Instant::parse))).maxOrNull()
        val timestamp = if (priorClock!=null && !occurredAt.isAfter(priorClock)) priorClock.plusMillis(1).toString() else occurredAt.toString()
        val device = UUID.fromString(deviceId).toString()
        // Swift's ensureSystemCategory also permits retained archived system categories.
        val presentation=if(request.automatic) automaticText?.invoke(bill,amount) else null
        presentation?.let {require(it.transactionTitle.isNotBlank() && it.successTitle.isNotBlank())}
        val mutation = TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE, title=presentation?.transactionTitle ?: bill.name,
            amountMinor=amount, occurredAt=occurredAt.toString(), sourceWalletId=wallet.id, categoryId=category.id)
            .toMutation(owner, previous, wallet, null, category.copy(isArchived=false), device, timestamp)
        val transactions = owned(snapshot, CloudEntity.LEDGER_TRANSACTION).map(LedgerTransactionRecord::fromCloudRecord).filter { it.deletedAt==null }
        val profiles = owned(snapshot, CloudEntity.CREDIT_CARD_PROFILE).map(CreditCardProfileRecord::fromCloudRecord).filter { it.deletedAt==null }
        if (previous?.isLockedByPaidCreditCardStatement(wallets, profiles, categories, transactions,
                owned(snapshot, CloudEntity.DUE_OCCURRENCE_RECORD).filter { it.deletedAt==null }, zone)==true)
            throw TransactionValidationException(TransactionValidationError.PAID_CREDIT_CARD_STATEMENT)
        if (mutation.record.isLockedByPaidCreditCardStatement(wallets, profiles, categories, transactions+mutation.record,
                owned(snapshot, CloudEntity.DUE_OCCURRENCE_RECORD).filter { it.deletedAt==null }, zone))
            throw TransactionValidationException(TransactionValidationError.PAID_CREDIT_CARD_STATEMENT)
        mutation.record.requireAffordable(wallets, transactions, profiles, null)
        val paymentOccurrences = cycle+undone
        val paid = if (paymentOccurrences.isEmpty()) listOf(DueOccurrenceRecord(UUID.randomUUID().toString(), owner.value,
            "recurringBill", bill.id, request.month.toString(), due.dueDate.toString(), amount, "paid", timestamp,
            mutation.record.id, timestamp, timestamp, null, 0, device)) else paymentOccurrences.map {
            it.copy(scheduledDate=due.dueDate.toString(), amountMinorSnapshot=amount, statusWireValue="paid", paidAt=timestamp,
                linkedTransactionId=mutation.record.id, updatedAt=timestamp, deletedAt=null, lastModifiedByDeviceId=device)
        }
        val writes = categoryWrites.map { it.toCloudRecord() to it.bootstrapMutation() }+listOf(mutation.record.toCloudRecord() to mutation.pending)+paid.map { it.toCloudRecord() to it.pendingMutation() }
        val notification=presentation?.takeIf {it.emitNotification}?.let {text -> AppNotificationRecord(owner.value,
            "mistia.bill.autopay.success.${bill.id.lowercase()}.${request.month}",text.successTitle,text.successBody,"billAutoPaymentSucceeded",
            resourceType="bill",resourceId=bill.id,createdAt=occurredAt.toString(),updatedAt=occurredAt.toString(),metadata=buildJsonObject {
                put("sourceKind","recurringBill");put("sourceId",bill.id);put("dueMonthKey",request.month.toString());put("dueDate",due.dueDate.toString())
                put("requiresAmountInput",false);put("currencyCode",bill.currencyCode);put("billName",bill.name);put("linkedPaymentWalletId",wallet.id)
            })}
        store.commitBillMoneyMutations(snapshot.copy(automaticPaymentNotification=notification), writes.map { preservePayloadExtensions(snapshot, it) })
        SavedBillPayment(mutation.record, paid)
    }

    override suspend fun undoRecurringBillPayment(owner: UserId, billId: RecordId, month: YearMonth, deviceId: String, now: String): Result<Unit> = result {
        val snapshot = snapshot(owner, billId, month)
        val occurrences = owned(snapshot, CloudEntity.DUE_OCCURRENCE_RECORD).map(DueOccurrenceRecord::fromCloudRecord)
        val cycle = occurrences.filter { it.deletedAt==null && it.sourceKindWireValue=="recurringBill" && it.sourceId==billId.value && it.selectedMonthKey==month.toString() && it.status==DueStatus.PAID }
        if (cycle.isEmpty()) return@result
        val linked = cycle.mapNotNull { it.linkedTransactionId }.toSet()
        val allTransactions = owned(snapshot, CloudEntity.LEDGER_TRANSACTION).map(LedgerTransactionRecord::fromCloudRecord)
        val transactions = linked.map { id -> allTransactions.firstOrNull { it.id==id } ?: fail(BillPaymentError.UNSUPPORTED_LINKED_STATE) }
        val otherOccurrences = occurrences.filter { it.deletedAt==null && it !in cycle }
        if (otherOccurrences.any { it.linkedTransactionId in linked }) fail(BillPaymentError.UNSUPPORTED_LINKED_STATE)
        val wallets = owned(snapshot, CloudEntity.LEDGER_WALLET).map(LedgerWalletRecord::fromCloudRecord).filter { it.deletedAt==null }
        val profiles = owned(snapshot, CloudEntity.CREDIT_CARD_PROFILE).map(CreditCardProfileRecord::fromCloudRecord).filter { it.deletedAt==null }
        val categories = owned(snapshot, CloudEntity.TRANSACTION_CATEGORY).map(TransactionCategoryRecord::fromCloudRecord).filter { it.deletedAt==null }
        transactions.filter { it.deletedAt==null }.forEach { tx ->
            if (tx.id in snapshot.receiptTransactionIds || tx.primaryKind!=TransactionPrimaryKind.EXPENSE || tx.settlementGroupId!=null || tx.settlementObligationId!=null || tx.settlementRoleWireValue!=null ||
                owned(snapshot, CloudEntity.INVESTMENT_POSTING).any { it.deletedAt==null && (it.payload["ledger_transaction_id"] as? JsonPrimitive)?.content==tx.id })
                fail(BillPaymentError.UNSUPPORTED_LINKED_STATE)
            if (tx.isLockedByPaidCreditCardStatement(wallets, profiles, categories, allTransactions.filter { it.deletedAt==null },
                    owned(snapshot, CloudEntity.DUE_OCCURRENCE_RECORD).filter { it.deletedAt==null }, zone))
                throw TransactionValidationException(TransactionValidationError.PAID_CREDIT_CARD_STATEMENT)
        }
        val timestamp = Instant.parse(now).toString()
        val device = UUID.fromString(deviceId).toString()
        val deletedTransactions = transactions.filter { it.deletedAt==null }.map { it.copy(deletedAt=timestamp, updatedAt=timestamp,
            lastModifiedByUserId=owner.value, lastModifiedByDeviceId=device) }
        val deletedOccurrences = cycle.map { it.copy(deletedAt=timestamp, updatedAt=timestamp, lastModifiedByDeviceId=device) }
        val mutations = deletedTransactions.map { tx -> tx.toCloudRecord() to PendingMutation(CloudEntity.LEDGER_TRANSACTION,
            tx.id, owner.value, MutationKind.DELETE, tx.toPayload(), timestamp, tx.syncVersion, device) } +
            deletedOccurrences.map { it.toCloudRecord() to it.pendingMutation(MutationKind.DELETE) }
        store.commitBillMoneyMutations(snapshot, mutations.map { preservePayloadExtensions(snapshot, it) })
    }

    private fun preservePayloadExtensions(snapshot: BillMoneySnapshot, write: Pair<CloudRecord, PendingMutation>): Pair<CloudRecord, PendingMutation> {
        val (record, pending) = write
        val original = snapshot.recordsByEntity.getValue(requireNotNull(CloudEntity.fromTable(record.entity))).firstOrNull { it.id==record.id }
            ?: return write
        val payload = JsonObject(original.payload+record.payload)
        return record.copy(payload=payload) to pending.copy(payload=payload)
    }

    private suspend fun snapshot(owner: UserId, billId: RecordId, month: YearMonth): BillMoneySnapshot {
        val records = CloudEntity.entries.associateWith { store.recordsIncludingDeleted(owner, it.table) }
        val billRow = records.getValue(CloudEntity.RECURRING_BILL_PLAN).firstOrNull {
            it.id==billId.value && it.ownerUserId==owner.value && (it.payload["user_id"] as? JsonPrimitive)?.content==owner.value && it.deletedAt==null
        } ?: fail(BillPaymentError.NOT_FOUND)
        val bill = RecurringBillPlanRecord.fromCloudRecord(billRow)
        if (bill.id!=billRow.id || bill.ownerUserId!=owner.value || bill.deletedAt!=null || bill.isArchived) fail(BillPaymentError.NOT_FOUND)
        return BillMoneySnapshot(owner, billRow, month, records, store.billMoneyReceiptTransactionIds(owner))
    }
    private fun owned(snapshot: BillMoneySnapshot, entity: CloudEntity) = snapshot.recordsByEntity.getValue(entity).filter { row ->
        require(row.ownerUserId==snapshot.owner.value && row.entity==entity.table)
        (row.payload["user_id"] as? JsonPrimitive)?.content==snapshot.owner.value
    }.onEach { require((it.payload["id"] as? JsonPrimitive)?.content==it.id) }
    private fun fail(reason: BillPaymentError): Nothing = throw BillPaymentException(reason)
    private suspend fun <T> result(block: suspend () -> T): Result<T> = try { Result.success(block()) }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) { Result.failure(error) }
}
