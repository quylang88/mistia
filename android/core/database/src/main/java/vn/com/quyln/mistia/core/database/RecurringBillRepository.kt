package vn.com.quyln.mistia.core.database

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.util.UUID
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import vn.com.quyln.mistia.core.model.*

internal class OfflineRecurringBillRepository(private val store:LocalStore,private val currentZone:()->ZoneId):RecurringBillRepository {
    constructor(store:LocalStore,zone:ZoneId):this(store,{zone})
    private val mutex=Mutex()
    override fun observeRecurringBills(ownerUserId:UserId):Flow<List<RecurringBillPlanRecord>> =
        store.observeOwnedFinanceRows(CloudEntity.RECURRING_BILL_PLAN,ownerUserId).map { rows ->
            rows.filter { it.ownerUserId==ownerUserId.value && it.deletedAt==null }.mapNotNull { row ->
                runCatching { RecurringBillPlanRecord.fromCloudRecord(row).takeIf { it.id==row.id && it.ownerUserId==ownerUserId.value && it.deletedAt==null } }.getOrNull()
            }.sortedWith(compareBy(RecurringBillPlanRecord::createdAt,RecurringBillPlanRecord::id))
        }
    override fun observeDueOccurrences(ownerUserId:UserId):Flow<List<DueOccurrenceRecord>> =
        store.observeOwnedFinanceRows(CloudEntity.DUE_OCCURRENCE_RECORD,ownerUserId).map { rows ->
            rows.filter { it.ownerUserId==ownerUserId.value && it.deletedAt==null }.mapNotNull { row ->
                runCatching { DueOccurrenceRecord.fromCloudRecord(row).takeIf { it.id==row.id && it.ownerUserId==ownerUserId.value && it.deletedAt==null } }.getOrNull()
            }.sortedWith(compareBy(DueOccurrenceRecord::createdAt,DueOccurrenceRecord::id))
        }
    override suspend fun skipRecurringBill(ownerUserId:UserId,id:RecordId,month:YearMonth,deviceId:String,now:String):Result<DueOccurrenceRecord> = result {
        mutex.withLock {
            val zone=currentZone()
            val bill=active(ownerUserId,id)
            val cloud=requireNotNull(store.record(ownerUserId,CloudEntity.RECURRING_BILL_PLAN.table,bill.id))
            require(RecurringBillPlanRecord.fromCloudRecord(cloud)==bill) {"Bill changed before cycle snapshot"}
            val cycle=billCycleRecords(store.recordsIncludingDeleted(ownerUserId,CloudEntity.DUE_OCCURRENCE_RECORD.table),cloud,month.toString())
            val owned=cycle.filter {(it.payload["user_id"] as? JsonPrimitive)?.content==ownerUserId.value}.map {record -> DueOccurrenceRecord.fromCloudRecord(record).also {require(it.id==record.id && it.ownerUserId==ownerUserId.value)}}.filter {it.deletedAt==null}
            require(owned.none {it.status==DueStatus.PAID || it.linkedTransactionId!=null}) {"Paid cycle cannot be skipped"}
            val row=recurringBillDueRows(ownerUserId,listOf(bill),owned,month,zone).singleOrNull() ?: error("Bill cycle is not scheduled")
            owned.firstOrNull {it.status==DueStatus.SKIPPED}?.let {return@withLock it}
            val timestamp=Instant.parse(now).toString()
            val device=UUID.fromString(deviceId).toString()
            val pending=owned.filter {it.status==DueStatus.PENDING}
            val saved=if(pending.isEmpty()) listOf(DueOccurrenceRecord(UUID.randomUUID().toString(),ownerUserId.value,"recurringBill",bill.id,
                month.toString(),row.dueDate.toString(),null,"skipped",null,null,timestamp,timestamp,null,0,device)) else pending.map {
                it.copy(scheduledDate=row.dueDate.toString(),amountMinorSnapshot=null,statusWireValue="skipped",paidAt=null,linkedTransactionId=null,updatedAt=timestamp,lastModifiedByDeviceId=device)
            }
            store.commitBillCycleMutations(cloud,month.toString(),cycle,saved.map {it.toCloudRecord() to it.pendingMutation()})
            saved.first()
        }
    }
    override suspend fun undoRecurringBillSkip(ownerUserId:UserId,id:RecordId,month:YearMonth,deviceId:String,now:String):Result<Unit> = result {
        mutex.withLock {
            val zone=currentZone()
            val bill=active(ownerUserId,id)
            val cloud=requireNotNull(store.record(ownerUserId,CloudEntity.RECURRING_BILL_PLAN.table,bill.id))
            require(RecurringBillPlanRecord.fromCloudRecord(cloud)==bill)
            val cycle=billCycleRecords(store.recordsIncludingDeleted(ownerUserId,CloudEntity.DUE_OCCURRENCE_RECORD.table),cloud,month.toString())
            val timestamp=Instant.parse(now).toString()
            val device=UUID.fromString(deviceId).toString()
            val owned=cycle.filter {(it.payload["user_id"] as? JsonPrimitive)?.content==ownerUserId.value}.map {record -> DueOccurrenceRecord.fromCloudRecord(record).also {require(it.id==record.id && it.ownerUserId==ownerUserId.value)}}
            require(recurringBillDueRows(ownerUserId,listOf(bill),owned.filter {it.deletedAt==null},month,zone).isNotEmpty()) {"Bill cycle is not scheduled"}
            val deleted=owned.filter {it.deletedAt==null && it.status==DueStatus.SKIPPED}.map {it.copy(deletedAt=timestamp,updatedAt=timestamp,lastModifiedByDeviceId=device)}
            if(deleted.isNotEmpty()) store.commitBillCycleMutations(cloud,month.toString(),cycle,deleted.map {it.toCloudRecord() to it.pendingMutation(MutationKind.DELETE)})
        }
    }
    override suspend fun saveRecurringBill(ownerUserId:UserId,draft:RecurringBillDraft,deviceId:String,now:String):Result<RecurringBillPlanRecord> = result {
        mutex.withLock {
            val zone=currentZone()
            require(draft.zoneId==zone) { "Bill draft must use the repository calendar zone" }
            val existing=draft.id?.let { find(ownerUserId,it) }
            if((draft.editingExisting && existing==null) || existing?.isArchived==true || existing?.deletedAt!=null) fail(RecurringBillValidationError.NOT_FOUND)
            val categoryId=draft.categoryId ?: fail(RecurringBillValidationError.CATEGORY_REQUIRED)
            val categoryRow=store.record(ownerUserId,CloudEntity.TRANSACTION_CATEGORY.table,categoryId) ?: fail(RecurringBillValidationError.INVALID_CATEGORY)
            val category=TransactionCategoryRecord.fromCloudRecord(categoryRow)
            if(categoryRow.ownerUserId!=ownerUserId.value || categoryRow.id!=category.id || category.ownerUserId!=ownerUserId.value || category.deletedAt!=null || categoryRow.deletedAt!=null ||
                category.kind!=TransactionCategoryKind.EXPENSE || category.hierarchyRole!=CategoryHierarchyRole.CHILD || category.isBalanceAdjustmentSystemCategory ||
                (category.isArchived && existing?.categoryId!=category.id)) fail(RecurringBillValidationError.INVALID_CATEGORY)
            val parentId=category.parentCategoryId ?: fail(RecurringBillValidationError.INVALID_CATEGORY)
            val parentRow=store.record(ownerUserId,CloudEntity.TRANSACTION_CATEGORY.table,parentId) ?: fail(RecurringBillValidationError.INVALID_CATEGORY)
            val parent=TransactionCategoryRecord.fromCloudRecord(parentRow)
            if(parentRow.ownerUserId!=ownerUserId.value || parentRow.id!=parentId || parent.ownerUserId!=ownerUserId.value || parent.id!=parentId || parent.deletedAt!=null || parentRow.deletedAt!=null ||
                parent.kind!=TransactionCategoryKind.EXPENSE || parent.hierarchyRole!=CategoryHierarchyRole.PARENT) fail(RecurringBillValidationError.INVALID_CATEGORY)
            val walletId=draft.paymentWalletId ?: fail(RecurringBillValidationError.WALLET_REQUIRED)
            val walletRow=store.record(ownerUserId,CloudEntity.LEDGER_WALLET.table,walletId) ?: fail(RecurringBillValidationError.INVALID_WALLET)
            val wallet=LedgerWalletRecord.fromCloudRecord(walletRow)
            if(walletRow.ownerUserId!=ownerUserId.value || walletRow.id!=walletId || wallet.ownerUserId!=ownerUserId.value || wallet.id!=walletId || walletRow.deletedAt!=null || wallet.deletedAt!=null ||
                (wallet.isArchived && existing?.paymentWalletId!=walletId)) fail(RecurringBillValidationError.INVALID_WALLET)
            if(!billPaymentCurrenciesMatch(existing?.currencyCode ?: draft.currencyCode,wallet.currencyCode))
                fail(RecurringBillValidationError.WALLET_CURRENCY_MISMATCH)
            val saved=draft.toBillRecord(ownerUserId,category,existing,deviceId,now)
            RecurringBillPlanRecord.fromCloudRecord(saved.toCloudRecord())
            commit(saved)
            saved
        }
    }
    override suspend fun pauseRecurringBill(ownerUserId:UserId,id:RecordId,deviceId:String,now:String):Result<Unit> = result {
        mutex.withLock {
            val bill=active(ownerUserId,id)
            if(bill.scheduleKind==BillScheduleKind.RECURRING) commit(bill.copy(isPaused=true,pausedAt=now,resumeStartMonth=null,updatedAt=now,lastModifiedByDeviceId=UUID.fromString(deviceId).toString()))
        }
    }
    override suspend fun resumeRecurringBill(ownerUserId:UserId,id:RecordId,deviceId:String,now:String):Result<Unit> = result {
        mutex.withLock {
            val zone=currentZone()
            val bill=active(ownerUserId,id)
            if(bill.scheduleKind==BillScheduleKind.RECURRING) {
                val month=YearMonth.from(Instant.parse(now).atZone(zone)).atDay(1).atStartOfDay(zone).toInstant().toString()
                commit(bill.copy(isPaused=false,pausedAt=null,resumeStartMonth=month,updatedAt=now,lastModifiedByDeviceId=UUID.fromString(deviceId).toString()))
            }
        }
    }
    override suspend fun archiveRecurringBill(ownerUserId:UserId,id:RecordId,deviceId:String,now:String):Result<Unit> = result {
        mutex.withLock {
            val zone=currentZone()
            val bill=active(ownerUserId,id)
            if(hasUnpaidBillCycles(ownerUserId,bill,observeDueOccurrences(ownerUserId).first(),Instant.parse(now),zone)) fail(RecurringBillValidationError.UNPAID_CYCLES)
            commit(bill.copy(isArchived=true,updatedAt=now,lastModifiedByDeviceId=UUID.fromString(deviceId).toString()))
        }
    }
    private suspend fun commit(bill:RecurringBillPlanRecord) {
        RecurringBillPlanRecord.fromCloudRecord(bill.toCloudRecord())
        store.commitMutations(listOf(bill.toCloudRecord() to bill.pendingMutation()))
    }
    private suspend fun find(owner:UserId,id:String):RecurringBillPlanRecord? {
        val canonical=UUID.fromString(id).toString()
        return store.record(owner,CloudEntity.RECURRING_BILL_PLAN.table,canonical)?.let { row ->
            require(row.ownerUserId==owner.value && row.id==canonical)
            RecurringBillPlanRecord.fromCloudRecord(row).also { require(it.ownerUserId==owner.value && it.id==canonical) }
        }
    }
    private suspend fun active(owner:UserId,id:RecordId)=find(owner,id.value)?.takeIf { !it.isArchived && it.deletedAt==null } ?: fail(RecurringBillValidationError.NOT_FOUND)
    private fun fail(reason:RecurringBillValidationError):Nothing=throw RecurringBillValidationException(reason)
    private suspend fun <T> result(block:suspend ()->T):Result<T> = try { Result.success(block()) }
        catch(cancelled:CancellationException) { throw cancelled }
        catch(error:Exception) { Result.failure(error) }
}
