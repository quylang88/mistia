package vn.com.quyln.mistia.core.database

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import vn.com.quyln.mistia.core.model.*

internal class OfflineRecurringBillRepository(private val store:LocalStore,private val zone:ZoneId):RecurringBillRepository {
    private val mutex=Mutex()
    override fun observeRecurringBills(ownerUserId:UserId):Flow<List<RecurringBillPlanRecord>> =
        store.observe(CloudEntity.RECURRING_BILL_PLAN.table,ownerUserId).map { rows ->
            rows.filter { it.ownerUserId==ownerUserId.value && it.deletedAt==null }.mapNotNull { row ->
                runCatching { RecurringBillPlanRecord.fromCloudRecord(row).takeIf { it.id==row.id && it.ownerUserId==ownerUserId.value && it.deletedAt==null } }.getOrNull()
            }.sortedWith(compareBy(RecurringBillPlanRecord::createdAt,RecurringBillPlanRecord::id))
        }
    override fun observeDueOccurrences(ownerUserId:UserId):Flow<List<DueOccurrenceRecord>> =
        store.observe(CloudEntity.DUE_OCCURRENCE_RECORD.table,ownerUserId).map { rows ->
            rows.filter { it.ownerUserId==ownerUserId.value && it.deletedAt==null }.mapNotNull { row ->
                runCatching { DueOccurrenceRecord.fromCloudRecord(row).takeIf { it.id==row.id && it.ownerUserId==ownerUserId.value && it.deletedAt==null } }.getOrNull()
            }.sortedWith(compareBy(DueOccurrenceRecord::createdAt,DueOccurrenceRecord::id))
        }
    override suspend fun saveRecurringBill(ownerUserId:UserId,draft:RecurringBillDraft,deviceId:String,now:String):Result<RecurringBillPlanRecord> = result {
        mutex.withLock {
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
            val bill=active(ownerUserId,id)
            if(bill.scheduleKind==BillScheduleKind.RECURRING) {
                val month=YearMonth.from(Instant.parse(now).atZone(zone)).atDay(1).atStartOfDay(zone).toInstant().toString()
                commit(bill.copy(isPaused=false,pausedAt=null,resumeStartMonth=month,updatedAt=now,lastModifiedByDeviceId=UUID.fromString(deviceId).toString()))
            }
        }
    }
    override suspend fun archiveRecurringBill(ownerUserId:UserId,id:RecordId,deviceId:String,now:String):Result<Unit> = result {
        mutex.withLock {
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
