package vn.com.quyln.mistia.core.model

import java.time.YearMonth
import kotlinx.serialization.json.JsonPrimitive

data class BillPaymentRequest(
    val billId: RecordId,
    val month: YearMonth,
    val walletId: RecordId? = null,
    val amountMinorOverride: Long? = null,
    val automatic: Boolean = false,
)

data class BillAutomaticPaymentText(val transactionTitle:String,val successTitle:String,val successBody:String,val emitNotification:Boolean=true)

data class SavedBillPayment(
    val transaction: LedgerTransactionRecord,
    val occurrences: List<DueOccurrenceRecord>,
)

enum class BillPaymentError {
    AUTO_PAY_NOT_DUE, INVALID_AUTO_PAY_OVERRIDE,
    SOURCE_CHANGED, NOT_FOUND, NOT_SCHEDULED, CYCLE_NOT_PENDING, WALLET_CURRENCY_MISMATCH,
    INVALID_WALLET, INVALID_CATEGORY, MISSING_AMOUNT, INVESTMENT_USAGE_UNAVAILABLE,
    UNSUPPORTED_LINKED_STATE,
}

class BillPaymentException(val reason: BillPaymentError) : IllegalArgumentException(reason.name)

interface BillPaymentRepository {
    suspend fun payRecurringBill(owner: UserId, request: BillPaymentRequest, deviceId: String, now: String): Result<SavedBillPayment>
    suspend fun undoRecurringBillPayment(owner: UserId, billId: RecordId, month: YearMonth, deviceId: String, now: String): Result<Unit>
}

/** Complete owner snapshots rechecked atomically before any ledger or occurrence write. */
data class BillMoneySnapshot(
    val owner: UserId,
    val bill: CloudRecord,
    val month: YearMonth,
    val recordsByEntity: Map<CloudEntity, List<CloudRecord>>,
    val receiptTransactionIds: Set<String> = emptySet(),
    val automaticPaymentNotification: AppNotificationRecord? = null,
    val sourceKind: DueSourceKind = DueSourceKind.RECURRING_BILL,
)

fun BillMoneySnapshot.requireValidMutations(mutations: List<Pair<CloudRecord, PendingMutation>>) {
    require(recordsByEntity.keys == CloudEntity.entries.toSet()) { "Incomplete money dependency snapshot" }
    recordsByEntity.forEach { (entity, rows) ->
        require(rows.all { it.entity==entity.table && it.ownerUserId==owner.value })
        require(rows.map { it.id }.distinct().size==rows.size)
    }
    require(sourceKind == DueSourceKind.RECURRING_BILL || sourceKind == DueSourceKind.INSTALLMENT)
    val sourceEntity = if (sourceKind == DueSourceKind.RECURRING_BILL) CloudEntity.RECURRING_BILL_PLAN else CloudEntity.INSTALLMENT_PLAN
    require(bill.entity == sourceEntity.table && bill.ownerUserId == owner.value)
    val source = if (sourceKind == DueSourceKind.RECURRING_BILL) RecurringBillPlanRecord.fromCloudRecord(bill) else null
    if (source != null) require(source.id==bill.id && source.ownerUserId==owner.value && source.deletedAt==null && !source.isArchived)
    else InstallmentPlanRecord.fromCloudRecord(bill).also {
        require(it.id == bill.id && it.ownerUserId == owner.value && it.deletedAt == null && !it.isArchived && it.syncVersion == bill.syncVersion)
    }
    require(recordsByEntity.getValue(sourceEntity).singleOrNull { it.id==bill.id }==bill)
    require(mutations.isNotEmpty() && mutations.map { it.first.entity to it.first.id }.distinct().size==mutations.size)
    val cycle = billCycleRecords(recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD), bill, month.toString(), sourceKind)
    val occurrenceWrites = mutations.filter { it.first.entity==CloudEntity.DUE_OCCURRENCE_RECORD.table }
    require(occurrenceWrites.isNotEmpty())
    automaticPaymentNotification?.let {notification ->
        notification.requireValidLocalNotification()
        require(sourceKind == DueSourceKind.RECURRING_BILL && source != null)
        require(source.autoPayEnabled==true && !source.isPaused)
        require(notification.metadata?.get("linkedPaymentWalletId")==JsonPrimitive(requireNotNull(source.paymentWalletId)))
        require(notification.ownerUserId==owner.value && notification.source=="system" && notification.kind=="billAutoPaymentSucceeded" &&
            notification.resourceType=="bill" && notification.resourceId==bill.id && notification.key=="mistia.bill.autopay.success.${bill.id.lowercase()}.$month")
        require(notification.metadata?.get("sourceKind")==JsonPrimitive("recurringBill") &&
            notification.metadata["sourceId"]==JsonPrimitive(bill.id) && notification.metadata["dueMonthKey"]==JsonPrimitive(month.toString()) &&
            notification.metadata["currencyCode"]==JsonPrimitive(source.currencyCode))
        require(occurrenceWrites.all {it.first.deletedAt==null && it.first.payload["status_raw_value"]==JsonPrimitive("paid")})
    }
    val linkedIDs = (cycle+occurrenceWrites.map { it.first }).mapNotNull {
        (it.payload["linked_transaction_id"] as? JsonPrimitive)?.takeIf { value -> value.isString }?.content
    }.toSet()
    mutations.forEach { (record, mutation) ->
        val entity = CloudEntity.fromTable(record.entity)
        require(entity in setOf(CloudEntity.LEDGER_TRANSACTION, CloudEntity.DUE_OCCURRENCE_RECORD, CloudEntity.TRANSACTION_CATEGORY))
        require(record.ownerUserId==owner.value && (record.payload["user_id"] as? JsonPrimitive)?.content==owner.value)
        require((record.payload["id"] as? JsonPrimitive)?.content==record.id)
        require(mutation.entity==entity && mutation.recordId==record.id && mutation.subjectUserId==owner.value && mutation.payload==record.payload)
        if (entity==CloudEntity.DUE_OCCURRENCE_RECORD) require(billCycleRecords(listOf(record), bill, month.toString(), sourceKind).size==1)
        else if (entity==CloudEntity.LEDGER_TRANSACTION) {
            require(record.id in linkedIDs)
            if (sourceKind == DueSourceKind.INSTALLMENT && mutation.kind == MutationKind.UPSERT) {
                val payment = LedgerTransactionRecord.fromCloudRecord(record)
                val wallet = recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).single { it.id == payment.sourceWalletId }.let(LedgerWalletRecord::fromCloudRecord)
                val plan = InstallmentPlanRecord.fromCloudRecord(bill)
                require(payment.primaryKind == TransactionPrimaryKind.EXPENSE && payment.entryStatus == TransactionEntryStatus.POSTED && payment.amountMinor > 0)
                require(wallet.ownerUserId == owner.value && wallet.deletedAt == null && !wallet.isArchived && wallet.kind != null && wallet.kind != WalletKind.CREDIT_CARD)
                require(installmentPaymentCurrenciesMatch(plan.currencyCode, wallet.currencyCode) && installmentPaymentCurrenciesMatch(plan.currencyCode, payment.sourceCurrencyCode.orEmpty()))
            }
        }
        else {
            val category = TransactionCategoryRecord.fromCloudRecord(record)
            require(category.isSystem && category.systemKey!=null && category.deletedAt==null)
            require(recordsByEntity.getValue(CloudEntity.TRANSACTION_CATEGORY).none { it.id==record.id })
            require(mutation.kind==MutationKind.UPSERT)
        }
        val existing = recordsByEntity.getValue(requireNotNull(entity)).firstOrNull { it.id==record.id }
        require(mutation.baseVersion==(existing?.syncVersion ?: 0L) && record.syncVersion==mutation.baseVersion)
        require(existing==null || (existing.payload["user_id"] as? JsonPrimitive)?.content==owner.value) { "Money identity occupied by another owner" }
    }
}

fun BillMoneySnapshot.requireUnchanged(current: Map<CloudEntity, List<CloudRecord>>) {
    require(current.keys==recordsByEntity.keys)
    require(recordsByEntity.all { (entity, expected) -> expected.sortedBy { it.id }==current.getValue(entity).sortedBy { it.id } }) {
        "Bill money dependencies changed during operation"
    }
}
