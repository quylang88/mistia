package vn.com.quyln.mistia.core.model

import kotlinx.coroutines.flow.Flow

interface SavingsGoalRepository {
    fun observeSavingsGoals(ownerUserId: UserId): Flow<List<SavingsGoalRecord>>
    suspend fun saveSavingsGoal(ownerUserId: UserId, draft: SavingsGoalDraft, deviceId: String, now: String): Result<SavingsGoalRecord>
    suspend fun deleteSavingsGoal(ownerUserId: UserId, goalId: RecordId, deviceId: String, now: String): Result<Unit>
}

data class SavingsGoalDraft(
    val name: String,
    val targetMinor: Long,
    val currentSavedMinor: Long,
    val targetDate: String,
    val currencyCode: String,
    val id: String? = null,
    val editingExisting: Boolean = false,
    val linkedWalletId: String? = null,
    val iconSymbolName: String = "mistia.goal.savings",
)

enum class SavingsGoalValidationError { NAME_REQUIRED, INVALID_TARGET, INVALID_CURRENCY, INVALID_WALLET, NOT_FOUND, ORDER_OVERFLOW }
class SavingsGoalValidationException(val reason: SavingsGoalValidationError): IllegalArgumentException(reason.name)

fun SavingsGoalRecord.pendingMutation(kind: MutationKind = MutationKind.UPSERT) = PendingMutation(
    CloudEntity.SAVINGS_GOAL,id,ownerUserId,kind,toPayload(),updatedAt,syncVersion,requireNotNull(lastModifiedByDeviceId),
)
