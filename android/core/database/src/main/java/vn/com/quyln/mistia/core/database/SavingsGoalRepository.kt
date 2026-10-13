package vn.com.quyln.mistia.core.database

import java.time.Instant
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import vn.com.quyln.mistia.core.model.*

internal class OfflineSavingsGoalRepository(private val store: LocalStore): SavingsGoalRepository {
    private val mutex=Mutex()
    override fun observeSavingsGoals(ownerUserId: UserId): Flow<List<SavingsGoalRecord>> =
        store.observe(CloudEntity.SAVINGS_GOAL.table,ownerUserId).map { records ->
            records.filter { it.ownerUserId==ownerUserId.value && it.deletedAt==null }.mapNotNull { row ->
                runCatching { SavingsGoalRecord.fromCloudRecord(row).takeIf { it.id==row.id && it.ownerUserId==ownerUserId.value } }.getOrNull()
            }.filter { !it.isArchived && it.deletedAt==null }
                .sortedWith(compareBy(SavingsGoalRecord::sortOrder,SavingsGoalRecord::createdAt,SavingsGoalRecord::id))
        }

    override suspend fun saveSavingsGoal(ownerUserId: UserId,draft: SavingsGoalDraft,deviceId: String,now: String): Result<SavingsGoalRecord> = result {
        mutex.withLock {
            val existing=draft.id?.let { find(ownerUserId,it) }
            if ((draft.editingExisting && existing==null) || existing?.isArchived==true || existing?.deletedAt!=null) fail(SavingsGoalValidationError.NOT_FOUND)
            val name=draft.name.trim().takeIf { it.isNotEmpty() } ?: fail(SavingsGoalValidationError.NAME_REQUIRED)
            if(draft.targetMinor<=0) fail(SavingsGoalValidationError.INVALID_TARGET)
            val currency=(existing?.currencyCode ?: draft.currencyCode).trim().uppercase(Locale.ROOT)
            if(!Regex("[A-Z]{3}").matches(currency)) fail(SavingsGoalValidationError.INVALID_CURRENCY)
            val walletId=draft.linkedWalletId?.let { UUID.fromString(it).toString() }
            if(walletId!=null) {
                val row=store.record(ownerUserId,CloudEntity.LEDGER_WALLET.table,walletId) ?: fail(SavingsGoalValidationError.INVALID_WALLET)
                val wallet=runCatching { LedgerWalletRecord.fromCloudRecord(row) }.getOrNull() ?: fail(SavingsGoalValidationError.INVALID_WALLET)
                if(row.ownerUserId!=ownerUserId.value || wallet.ownerUserId!=ownerUserId.value || wallet.id!=walletId || row.deletedAt!=null || wallet.deletedAt!=null ||
                    (wallet.isArchived && existing?.linkedWalletId!=walletId)) fail(SavingsGoalValidationError.INVALID_WALLET)
            }
            val order=existing?.sortOrder ?: run {
                val maximum=observeSavingsGoals(ownerUserId).first().maxOfOrNull { it.sortOrder } ?: -1
                if(maximum==Int.MAX_VALUE) fail(SavingsGoalValidationError.ORDER_OVERFLOW)
                maximum+1
            }
            val saved=SavingsGoalRecord(UUID.fromString(existing?.id ?: draft.id ?: UUID.randomUUID().toString()).toString(),ownerUserId.value,name,draft.iconSymbolName,
                draft.targetMinor,draft.currentSavedMinor,draft.targetDate,walletId,currency,order,false,existing?.createdAt ?: now,now,null,
                existing?.syncVersion ?: 0,UUID.fromString(deviceId).toString())
            SavingsGoalRecord.fromCloudRecord(saved.toCloudRecord()) // Validate all identities/timestamps before atomic commit.
            store.commitMutations(listOf(saved.toCloudRecord() to saved.pendingMutation()))
            saved
        }
    }

    override suspend fun deleteSavingsGoal(ownerUserId: UserId,goalId: RecordId,deviceId: String,now: String): Result<Unit> = result {
        mutex.withLock {
            val existing=find(ownerUserId,goalId.value)?.takeIf { it.deletedAt==null && !it.isArchived } ?: fail(SavingsGoalValidationError.NOT_FOUND)
            Instant.parse(now)
            val deleted=existing.copy(deletedAt=now,updatedAt=now,lastModifiedByDeviceId=UUID.fromString(deviceId).toString())
            store.commitMutations(listOf(deleted.toCloudRecord() to deleted.pendingMutation(MutationKind.DELETE)))
        }
    }

    private suspend fun find(owner: UserId,id: String): SavingsGoalRecord? {
        val canonicalId=UUID.fromString(id).toString()
        return store.record(owner,CloudEntity.SAVINGS_GOAL.table,canonicalId)?.let { row ->
            require(row.ownerUserId==owner.value && row.id==canonicalId)
            SavingsGoalRecord.fromCloudRecord(row).also { require(it.ownerUserId==owner.value && it.id==canonicalId) }
        }
    }
    private fun fail(reason:SavingsGoalValidationError):Nothing = throw SavingsGoalValidationException(reason)
    private suspend fun <T> result(block:suspend ()->T):Result<T> = try { Result.success(block()) }
        catch(cancelled:CancellationException) { throw cancelled }
        catch(error:Exception) { Result.failure(error) }
}
