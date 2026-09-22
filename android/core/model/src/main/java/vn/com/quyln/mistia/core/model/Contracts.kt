package vn.com.quyln.mistia.core.model

import java.math.BigDecimal
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

@JvmInline
value class UserId(val value: String)

@JvmInline
value class RecordId(val value: String)

@JvmInline
value class DecimalString(val value: String) {
    init {
        require(runCatching { BigDecimal(value) }.isSuccess) { "Invalid base-10 decimal: $value" }
    }

    fun asBigDecimal(): BigDecimal = BigDecimal(value)
}

data class Money(val minor: Long, val currencyCode: String) {
    init {
        require(currencyCode.length == 3) { "Currency code must be ISO-4217 shaped" }
    }
}

enum class CloudEntity(
    val table: String,
    val pullOrder: Int,
    val pushPriority: Int,
) {
    TRANSACTION_CATEGORY("transaction_categories", 10, 10),
    LEDGER_WALLET("ledger_wallets", 20, 20),
    CREDIT_CARD_PROFILE("credit_card_profiles", 30, 30),
    SETTLEMENT_GROUP("settlement_groups", 35, 35),
    SETTLEMENT_PARTICIPANT("settlement_participants", 36, 36),
    LEDGER_TRANSACTION("ledger_transactions", 40, 40),
    BUDGET_PLAN("budget_plans", 50, 50),
    SAVINGS_GOAL("savings_goals", 60, 60),
    RECURRING_BILL_PLAN("recurring_bill_plans", 70, 70),
    INSTALLMENT_PLAN("installment_plans", 80, 80),
    DUE_OCCURRENCE_RECORD("due_occurrence_records", 90, 90),
    INVESTMENT_CHANNEL("investment_channels", 100, 100),
    INVESTMENT_ASSET("investment_assets", 110, 110),
    INVESTMENT_TRADE("investment_trades", 120, 120),
    INVESTMENT_POSTING("investment_wallet_postings", 140, 140),
    ;

    companion object {
        val pullOrder: List<CloudEntity> = entries.sortedBy(CloudEntity::pullOrder)

        fun fromTable(table: String): CloudEntity? = entries.firstOrNull { it.table == table }
    }
}

enum class ReadOnlyCloudCollection(val table: String) {
    USER_PROFILE("user_profiles"),
    ACCOUNT_DEVICE("account_devices"),
    FAMILY("families"),
    FAMILY_MEMBERSHIP("family_memberships"),
    FAMILY_INVITE("family_invites"),
    FAMILY_NOTIFICATION("family_notifications"),
    FAMILY_PERMISSION_REQUEST("family_permission_requests"),
    FAMILY_PERMISSION_GRANT("family_permission_grants"),
}

data class DeviceRegistration(
    val userId: UserId,
    val deviceId: String,
    val deviceName: String,
    val modelIdentifier: String,
    val modelDisplayName: String,
    val systemName: String,
    val systemVersion: String,
    val appVersion: String,
    val appBuild: String,
)

interface DeviceRegistry {
    suspend fun register(session: AuthSession, registration: DeviceRegistration): Result<Unit>
}

@Serializable
data class CloudRecord(
    val entity: String,
    val id: String,
    val ownerUserId: String,
    val payload: JsonObject,
    val updatedAt: String?,
    val deletedAt: String?,
    val syncVersion: Long,
)

@Serializable
data class RemotePage(
    val records: List<JsonObject>,
    val nextOffset: Int?,
)

enum class MutationKind { UPSERT, DELETE }

data class PendingMutation(
    val entity: CloudEntity,
    val recordId: String,
    val subjectUserId: String,
    val kind: MutationKind,
    val payload: JsonObject?,
    val modifiedAt: String,
    val baseVersion: Long,
    val deviceId: String,
)

data class AuthSession(
    val userId: UserId,
    val email: String?,
    val accessToken: String,
    val refreshToken: String,
    val expiresAtEpochSeconds: Long,
) {
    fun shouldRefresh(nowEpochSeconds: Long): Boolean = expiresAtEpochSeconds - nowEpochSeconds <= 60
    override fun toString(): String = "AuthSession(credentials=redacted)"
}

sealed interface AuthState {
    data object Restoring : AuthState
    data object SignedOut : AuthState
    data class SignedIn(val session: AuthSession) : AuthState
    data class Failure(val message: String) : AuthState
}

enum class InitialSyncChoice { MERGE_SAFELY, USE_DEVICE, USE_CLOUD }

sealed interface SyncStatus {
    data object Idle : SyncStatus
    data class Pulling(val entity: String, val completed: Int, val total: Int) : SyncStatus
    data class Success(val recordCount: Int, val completedAtEpochMillis: Long) : SyncStatus
    data class Failed(val message: String, val retryable: Boolean) : SyncStatus
}

data class EntityCount(val entity: String, val count: Int)

interface AuthRepository {
    val state: StateFlow<AuthState>
    suspend fun restore()
    suspend fun signIn(email: String, password: String): Result<AuthSession>
    suspend fun signUp(email: String, password: String, displayName: String = ""): Result<AuthSession?>
    suspend fun resendConfirmation(email: String): Result<Unit>
    suspend fun sendPasswordReset(email: String): Result<Unit>
    suspend fun exchangeGoogleIdToken(idToken: String, nonce: String?): Result<AuthSession>
    suspend fun refreshIfNeeded(): Result<AuthSession?>
    suspend fun signOut(clearLocalSession: Boolean = true)
}

interface FinanceRepository {
    fun observe(entity: CloudEntity, ownerUserId: UserId): Flow<List<CloudRecord>>
    fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>>
}

interface FamilyRepository {
    fun observeFamilyRows(ownerUserId: UserId): Flow<List<CloudRecord>>
}

interface InvestmentRepository {
    fun observeAssets(ownerUserId: UserId): Flow<List<CloudRecord>>
    fun observeTrades(ownerUserId: UserId): Flow<List<CloudRecord>>
}

interface LocalStore {
    fun observe(entity: String, ownerUserId: UserId): Flow<List<CloudRecord>>
    fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>>
    suspend fun replacePullSnapshot(ownerUserId: UserId, entity: String, records: List<CloudRecord>)
    suspend fun pendingMutationRecordIds(ownerUserId: UserId, entity: String): Set<String>
    suspend fun clearAccount(ownerUserId: UserId)
}

interface RemoteStore {
    suspend fun pullPage(
        table: String,
        accessToken: String,
        ownerUserId: UserId,
        offset: Int,
        limit: Int,
    ): RemotePage
}

interface AssetStore {
    suspend fun uploadAvatar(userId: UserId, bytes: ByteArray): Result<String>
    suspend fun uploadInvestmentProductImage(userId: UserId, assetId: RecordId, bytes: ByteArray): Result<String>
    suspend fun download(path: String): Result<ByteArray>
}

interface SyncEngine {
    val status: StateFlow<SyncStatus>
    suspend fun pullAll(): Result<Int>
    fun scheduleBackgroundSync()
}
