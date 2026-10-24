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

data class QueuedMutation(
    val mutation: PendingMutation,
    val attemptCount: Int,
    val nextAttemptAtEpochMillis: Long,
    val lastError: String?,
    /** Local provenance only; zero is a valid observed remote version. */
    val remoteIdentityObserved: Boolean = false,
)

data class PendingCategoryTranslation(
    val ownerUserId: String,
    val categoryId: String,
    val inputName: String,
    val sourceLanguage: CategoryNameLanguage,
    val savedUpdatedAt: String,
    val deviceId: String,
)

data class QueuedCategoryTranslation(
    val translation: PendingCategoryTranslation,
    val attemptCount: Int,
    val nextAttemptAtEpochMillis: Long,
    val lastError: String?,
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
    data class Pushing(val entity: String) : SyncStatus
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

interface FinanceRepository : InstallmentPaymentRepository, InstallmentRepository, AppNotificationRepository, BillMaintenanceRepository, BudgetRepository, SavingsGoalRepository, RecurringBillRepository, SystemCategoryBootstrapRepository, BillPaymentRepository {
    suspend fun prepareTransactionLifecycle(owner:UserId,request:TransactionInvestmentLifecycleRequest,deviceId:String,now:String):Result<TransactionInvestmentSavePlan> =
        Result.failure(UnsupportedOperationException("Ordinary transaction lifecycle preparation unavailable"))
    suspend fun saveTransactionLifecycle(owner:UserId,request:TransactionInvestmentLifecycleRequest,deviceId:String,now:String):Result<LedgerTransactionRecord> =
        Result.failure(UnsupportedOperationException("Ordinary transaction lifecycle persistence unavailable"))
    fun observeOverviewFinancialReadSnapshot(owner:UserId):Flow<OverviewFinancialReadSnapshot> =
        throw UnsupportedOperationException("Consistent Overview financial snapshot unavailable")
    /** A consistent raw read set; implementations must not fabricate partial loaded snapshots. */
    fun observeUpcomingDueReadSnapshot(owner:UserId):Flow<UpcomingDueReadSnapshot> =
        throw UnsupportedOperationException("Consistent upcoming due snapshot unavailable")
    fun observe(entity: CloudEntity, ownerUserId: UserId): Flow<List<CloudRecord>>
    fun observeWallets(ownerUserId: UserId): Flow<List<LedgerWalletRecord>>
    fun observeCategories(ownerUserId: UserId): Flow<List<TransactionCategoryRecord>>
    fun observeCreditCardProfiles(ownerUserId: UserId): Flow<List<CreditCardProfileRecord>>
    fun observeTransactions(ownerUserId: UserId): Flow<List<LedgerTransactionRecord>>
    fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>>
    suspend fun saveWallet(
        ownerUserId: UserId,
        draft: WalletDraft,
        deviceId: String,
        now: String,
    ): Result<LedgerWalletRecord>
    suspend fun archiveWallet(
        ownerUserId: UserId,
        walletId: RecordId,
        deviceId: String,
        now: String,
    ): Result<Unit>
    suspend fun saveCreditCard(
        ownerUserId: UserId,
        draft: CreditCardDraft,
        deviceId: String,
        now: String,
    ): Result<CreditCardAccount>
    suspend fun saveTransaction(
        ownerUserId: UserId,
        draft: TransactionDraft,
        deviceId: String,
        now: String,
    ): Result<LedgerTransactionRecord>
    suspend fun prepareTransactionWithInvestmentFunds(owner:UserId,request:TransactionInvestmentSaveRequest,deviceId:String,now:String):Result<TransactionInvestmentSavePlan> =
        Result.failure(UnsupportedOperationException("Investment-aware transaction preparation unavailable"))
    suspend fun saveTransactionWithInvestmentFunds(owner:UserId,request:TransactionInvestmentSaveRequest,deviceId:String,now:String):Result<LedgerTransactionRecord> =
        Result.failure(UnsupportedOperationException("Investment-aware transaction save unavailable"))
    suspend fun saveCategory(
        ownerUserId: UserId,
        draft: CategoryDraft,
        deviceId: String,
        now: String,
    ): Result<TransactionCategoryRecord>
    suspend fun setCategoryFavorite(
        ownerUserId: UserId,
        categoryId: RecordId,
        isFavorite: Boolean,
        deviceId: String,
        now: String,
    ): Result<Unit>
    suspend fun archiveCategory(
        ownerUserId: UserId,
        categoryId: RecordId,
        deviceId: String,
        now: String,
    ): Result<Unit>
}

interface FamilyRepository {
    fun observeFamilyRows(ownerUserId: UserId): Flow<List<CloudRecord>>
}

interface InvestmentRepository {
    suspend fun stagedProductImageData(owner:UserId,candidate:InvestmentProductImageCandidate):Result<ByteArray> = Result.failure(UnsupportedOperationException("Staged product image read unavailable"))
    suspend fun productImageData(owner:UserId,assetId:String,path:String,thumbnail:Boolean=true):Result<ByteArray?> = Result.failure(UnsupportedOperationException("Product image read unavailable"))

    suspend fun stageProductImage(owner:UserId,assetId:String,image:PreparedInvestmentProductImage):Result<InvestmentProductImageCandidate> = Result.failure(UnsupportedOperationException("Product image staging unavailable"))
    suspend fun discardProductImage(owner:UserId,candidate:InvestmentProductImageCandidate):Result<Boolean> = Result.failure(UnsupportedOperationException("Product image discard unavailable"))
    suspend fun saveAssetImage(owner:UserId,draft:InvestmentAssetDraft,candidate:InvestmentProductImageCandidate?,revision:String,deviceId:String,now:String):Result<InvestmentAssetRecord> = Result.failure(UnsupportedOperationException("Asset image save unavailable"))

    suspend fun editTrade(owner:UserId,request:InvestmentTradeEditRequest,deviceId:String,now:String):Result<CloudRecord> = Result.failure(UnsupportedOperationException("Trade editing unavailable"))

    fun observeTradeDeletionSnapshot(owner:UserId):Flow<InvestmentTradeDeletionSnapshot> = observePurchaseSnapshot(owner)
    suspend fun deleteTrade(owner:UserId,request:InvestmentTradeDeletionRequest,deviceId:String,now:String):Result<CloudRecord> = Result.failure(UnsupportedOperationException("Trade deletion unavailable"))

    fun observeSaleSnapshot(owner:UserId):Flow<InvestmentSaleSnapshot> = observePurchaseSnapshot(owner)
    suspend fun saveSale(owner:UserId,request:InvestmentSaleRequest,deviceId:String,now:String):Result<CloudRecord> = Result.failure(UnsupportedOperationException("Sale unavailable"))

    fun observePurchaseSnapshot(owner:UserId):Flow<InvestmentPurchaseSnapshot> = throw UnsupportedOperationException("Consistent purchase read unavailable")
    suspend fun savePurchase(owner:UserId,request:InvestmentPurchaseRequest,deviceId:String,now:String):Result<CloudRecord> = Result.failure(UnsupportedOperationException("Purchase unavailable"))

    suspend fun reconcileCash(owner:UserId,request:InvestmentCashReconciliationRequest,deviceId:String,now:String):Result<Unit> =
        Result.failure(UnsupportedOperationException("Investment reconciliation unavailable"))
    /** Read-only historical comparison; never grants consent or writes derived financial rows. */
    suspend fun previewFundUsageTimeline(owner:UserId,accountingCurrency:String,replacingTransactionId:String?,proposed:CloudRecord?):InvestmentFundTimelineComparison =
        throw UnsupportedOperationException("Historical investment usage comparison unavailable")
    suspend fun saveCashTransfer(owner:UserId,request:InvestmentCashTransferRequest,deviceId:String,now:String):Result<Unit> = Result.failure(UnsupportedOperationException("Investment cash transfer unavailable"))
    suspend fun changeCashTransfer(owner:UserId,request:InvestmentCashTransferLifecycleRequest,deviceId:String,now:String):Result<Unit> = Result.failure(UnsupportedOperationException("Investment cash transfer lifecycle unavailable"))
    fun observeCashSnapshot(owner:UserId):Flow<InvestmentCashReadSnapshot> = throw UnsupportedOperationException("Consistent investment cash read unavailable")
    fun observeWalletSnapshot(owner:UserId):Flow<InvestmentWalletSnapshot> = throw UnsupportedOperationException("Consistent investment wallet snapshot unavailable")
    suspend fun changeLinkedWallet(owner:UserId,request:InvestmentWalletLinkRequest,deviceId:String,now:String):Result<Unit> = Result.failure(UnsupportedOperationException("Investment linked wallet change unavailable"))

    fun observeAssetSnapshot(owner:UserId):Flow<InvestmentAssetSnapshot> = throw UnsupportedOperationException("Consistent investment asset snapshot unavailable")
    suspend fun saveAsset(owner:UserId,draft:InvestmentAssetDraft,deviceId:String,now:String):Result<InvestmentAssetRecord> = Result.failure(UnsupportedOperationException("Investment asset save unavailable"))
    suspend fun archiveAsset(owner:UserId,expected:InvestmentAssetRecord,deviceId:String,now:String):Result<Unit> = Result.failure(UnsupportedOperationException("Investment asset archive unavailable"))
    suspend fun restoreAsset(owner:UserId,expected:InvestmentAssetRecord,deviceId:String,now:String):Result<Unit> = Result.failure(UnsupportedOperationException("Investment asset restore unavailable"))

    fun observeChannelSnapshot(owner:UserId):Flow<InvestmentChannelSnapshot> = throw UnsupportedOperationException("Consistent investment channel snapshot unavailable")
    suspend fun saveChannel(owner:UserId,draft:InvestmentChannelDraft,primaryCurrency:String,deviceId:String,now:String):Result<InvestmentChannelRecord> = Result.failure(UnsupportedOperationException("Investment channel save unavailable"))
    suspend fun archiveChannel(owner:UserId,expected:InvestmentChannelRecord,deviceId:String,now:String):Result<Unit> = Result.failure(UnsupportedOperationException("Investment channel archive unavailable"))
    suspend fun restoreChannel(owner:UserId,expected:InvestmentChannelRecord,deviceId:String,now:String):Result<Unit> = Result.failure(UnsupportedOperationException("Investment channel restore unavailable"))

    fun observeAssets(ownerUserId: UserId): Flow<List<CloudRecord>>
    fun observeTrades(ownerUserId: UserId): Flow<List<CloudRecord>>
}

interface LocalStore {
    suspend fun investmentChannelPublicationSnapshot(owner:UserId,id:String):InvestmentChannelPublicationSnapshot = throw UnsupportedOperationException("Atomic channel publication read unavailable")

    suspend fun acknowledgeInvestmentChannelMutation(mutation:QueuedMutation,remoteRecord:CloudRecord):Boolean = throw UnsupportedOperationException("Scoped channel acknowledgement unavailable")
    suspend fun recordInvestmentChannelMutationFailure(mutation:QueuedMutation,nextAttemptAtEpochMillis:Long,errorCode:String):Boolean = throw UnsupportedOperationException("Scoped channel failure recording unavailable")

    suspend fun commitInvestmentAssetImageMutation(expected:InvestmentAssetSnapshot,request:InvestmentAssetImageSaveRequest,deviceId:String,now:String):Boolean = throw UnsupportedOperationException("Conditional asset image save unavailable")

    suspend fun commitInvestmentTradeEdit(expected:InvestmentTradeCreationSnapshot,request:InvestmentTradeEditRequest,deviceId:String,now:String):Boolean = throw UnsupportedOperationException("Conditional trade editing unavailable")

    suspend fun commitInvestmentTradeDeletion(expected:InvestmentTradeDeletionSnapshot,request:InvestmentTradeDeletionRequest,deviceId:String,now:String):Boolean = throw UnsupportedOperationException("Conditional trade deletion unavailable")

    suspend fun commitInvestmentSale(expected:InvestmentSaleSnapshot,request:InvestmentSaleRequest,deviceId:String,now:String):Boolean = throw UnsupportedOperationException("Conditional sale unavailable")

    fun observeInvestmentPurchaseSnapshot(owner:UserId):Flow<InvestmentPurchaseSnapshot> = throw UnsupportedOperationException("Consistent purchase read unavailable")
    suspend fun investmentPurchaseSnapshot(owner:UserId):InvestmentPurchaseSnapshot = throw UnsupportedOperationException("Atomic purchase read unavailable")
    suspend fun commitInvestmentPurchase(expected:InvestmentPurchaseSnapshot,request:InvestmentPurchaseRequest,deviceId:String,now:String):Boolean = throw UnsupportedOperationException("Conditional purchase unavailable")

    suspend fun commitTransactionInvestmentLifecycle(expected:TransactionInvestmentSaveSnapshot,request:TransactionInvestmentLifecycleRequest,
        deviceId:String,now:String,statementZone:java.time.ZoneId=java.time.ZoneId.systemDefault()):LedgerTransactionRecord =
        throw UnsupportedOperationException("Conditional transaction lifecycle unavailable")
    suspend fun commitInvestmentCashTransfer(expected:InvestmentCashReadSnapshot,request:InvestmentCashTransferRequest,deviceId:String,now:String):Boolean = throw UnsupportedOperationException("Conditional investment cash transfer unavailable")
    suspend fun commitInvestmentCashReconciliation(expected:InvestmentCashReadSnapshot,request:InvestmentCashReconciliationRequest,deviceId:String,now:String):Boolean = throw UnsupportedOperationException("Conditional investment reconciliation unavailable")
    suspend fun commitInvestmentCashTransferLifecycle(expected:InvestmentCashReadSnapshot,request:InvestmentCashTransferLifecycleRequest,deviceId:String,now:String):Boolean = throw UnsupportedOperationException("Conditional investment cash transfer lifecycle unavailable")
    fun observeInvestmentCashSnapshot(owner:UserId):Flow<InvestmentCashReadSnapshot> = throw UnsupportedOperationException("Consistent investment cash read unavailable")
    suspend fun investmentCashSnapshot(owner:UserId):InvestmentCashReadSnapshot = throw UnsupportedOperationException("Atomic investment cash read unavailable")
    fun observeInvestmentWalletSnapshot(owner:UserId):Flow<InvestmentWalletSnapshot> = throw UnsupportedOperationException("Consistent investment wallet snapshot unavailable")
    suspend fun investmentWalletSnapshot(owner:UserId):InvestmentWalletSnapshot = throw UnsupportedOperationException("Atomic investment wallet snapshot unavailable")
    suspend fun commitInvestmentWalletLink(expected:InvestmentWalletSnapshot,request:InvestmentWalletLinkRequest,deviceId:String,now:String):Boolean = throw UnsupportedOperationException("Conditional investment wallet link unavailable")

    fun observeInvestmentAssetSnapshot(owner:UserId):Flow<InvestmentAssetSnapshot> = throw UnsupportedOperationException("Consistent investment asset snapshot unavailable")
    suspend fun investmentAssetSnapshot(owner:UserId):InvestmentAssetSnapshot = throw UnsupportedOperationException("Atomic investment asset snapshot unavailable")
    suspend fun commitInvestmentAssetMutation(expected:InvestmentAssetSnapshot,request:InvestmentAssetRequest,deviceId:String,now:String):Boolean = throw UnsupportedOperationException("Conditional investment asset mutation unavailable")

    fun observeInvestmentChannelSnapshot(owner:UserId):Flow<InvestmentChannelSnapshot> = throw UnsupportedOperationException("Consistent investment channel snapshot unavailable")
    suspend fun investmentChannelSnapshot(owner:UserId):InvestmentChannelSnapshot = throw UnsupportedOperationException("Atomic investment channel snapshot unavailable")
    suspend fun commitInvestmentChannels(expected:InvestmentChannelSnapshot,mutations:List<Pair<CloudRecord,PendingMutation>>):Boolean = throw UnsupportedOperationException("Conditional investment channel writes unavailable")

    fun observeOverviewFinancialReadSnapshot(owner:UserId):Flow<OverviewFinancialReadSnapshot> =
        throw UnsupportedOperationException("Consistent Overview financial snapshot unavailable")
    fun observeUpcomingDueReadSnapshot(owner:UserId):Flow<UpcomingDueReadSnapshot> =
        throw UnsupportedOperationException("Consistent upcoming due snapshot unavailable")
    suspend fun walletReminderSnapshot(owner:UserId):WalletReminderSnapshot =
        throw UnsupportedOperationException("Wallet reminder snapshot unavailable")
    suspend fun commitWalletReminders(expected:WalletReminderSnapshot,replacement:List<AppNotificationRecord>):Boolean =
        throw UnsupportedOperationException("Atomic wallet reminders unavailable")

    suspend fun billNotificationSnapshot(owner:UserId):BillNotificationSnapshot =
        throw UnsupportedOperationException("Bill notification snapshot unavailable")
    suspend fun commitBillNotifications(expected:BillNotificationSnapshot,replacement:List<AppNotificationRecord>):Boolean =
        throw UnsupportedOperationException("Atomic bill notification batch unavailable")

    fun observeLocalNotifications(owner:UserId):Flow<List<AppNotificationRecord>> =
        throw UnsupportedOperationException("Local notifications unavailable")
    suspend fun localNotifications(owner:UserId):List<AppNotificationRecord> =
        throw UnsupportedOperationException("Local notifications unavailable")
    suspend fun commitLocalNotifications(owner:UserId,expected:List<AppNotificationRecord>,replacement:List<AppNotificationRecord>):Boolean =
        throw UnsupportedOperationException("Atomic local notification batch unavailable")

    suspend fun commitObservedSystemCategoryMaintenance(expected:CategoryReferenceSnapshot,key:String,remote:List<CloudRecord>,catalog:SystemCategoryCatalog,deviceId:String,now:String):Boolean =
        throw UnsupportedOperationException("Atomic observed category maintenance unavailable")

    suspend fun commitSystemCategoryIdentityMigration(expected:CategoryReferenceSnapshot,queued:QueuedMutation,remote:List<CloudRecord>,catalog:SystemCategoryCatalog,deviceId:String,now:String):Boolean =
        throw UnsupportedOperationException("Atomic category identity migration unavailable")

    suspend fun categoryReferenceSnapshot(owner:UserId):CategoryReferenceSnapshot =
        throw UnsupportedOperationException("Complete category reference snapshot unavailable")
    /** Does not remove/reassign category identities; commits only validated FK/outbox/task repairs. */
    suspend fun commitCategoryReferenceRepairs(expected:CategoryReferenceSnapshot,oldId:String,newId:String,deviceId:String,now:String):Boolean =
        throw UnsupportedOperationException("Atomic category reference repairs unavailable")

    suspend fun installmentPaymentAcknowledgementSnapshot(owner: UserId, planId: String): InstallmentPaymentAcknowledgementSnapshot =
        throw UnsupportedOperationException("Complete installment payment acknowledgement snapshot unavailable")
    suspend fun commitInstallmentPaymentAcknowledgement(expected: InstallmentPaymentAcknowledgementSnapshot, queued: QueuedMutation,
        remotePlan: CloudRecord, remoteCycle: CloudRecord?, remoteLedger: Map<String, CloudRecord?>, remoteWallets: Map<String, CloudRecord?>): Boolean =
        throw UnsupportedOperationException("Atomic installment payment acknowledgement unavailable")
    suspend fun recordInstallmentPaymentAcknowledgementFailure(expected: InstallmentPaymentAcknowledgementSnapshot, queued: QueuedMutation,
        nextAttemptAtEpochMillis: Long, errorCode: String): Boolean =
        throw UnsupportedOperationException("Scoped installment payment acknowledgement failure unavailable")

    suspend fun commitInstallmentSkipAcknowledgement(expected: InstallmentAcknowledgementSnapshot, queued: QueuedMutation,
        remotePlan: CloudRecord, remoteCycle: CloudRecord, zone: java.time.ZoneId): Boolean =
        throw UnsupportedOperationException("Atomic installment skip acknowledgement unavailable")
    suspend fun recordInstallmentSkipFailure(expected: InstallmentAcknowledgementSnapshot, queued: QueuedMutation,
        nextAttemptAtEpochMillis: Long, errorCode: String): Boolean =
        throw UnsupportedOperationException("Scoped installment skip failure persistence unavailable")

    suspend fun installmentDeletionPlanIds(owner: UserId): Set<String> =
        throw UnsupportedOperationException("Owned installment deletion batches unavailable")
    suspend fun commitInstallmentDeletionCompletion(expected: InstallmentAcknowledgementSnapshot, requestBatchId: String,
        remoteSource: CloudRecord?, remoteCycles: Map<String, CloudRecord?>, nowEpochMillis: Long): Boolean =
        throw UnsupportedOperationException("Atomic installment deletion completion unavailable")
    suspend fun recordInstallmentDeletionFailure(expected: InstallmentAcknowledgementSnapshot, requestBatchId: String,
        queued: QueuedMutation, nextAttemptAtEpochMillis: Long, errorCode: String): Boolean =
        throw UnsupportedOperationException("Scoped installment deletion failure persistence unavailable")

    suspend fun recordInstallmentSourceFailure(queued: QueuedMutation, requestBatchId: String?, nextAttemptAtEpochMillis: Long, errorCode: String): Boolean =
        throw UnsupportedOperationException("Installment source failure fencing is unavailable")

    suspend fun installmentAcknowledgementSnapshot(owner: UserId, planId: String): InstallmentAcknowledgementSnapshot =
        throw UnsupportedOperationException("Complete installment acknowledgement snapshot unavailable")
    suspend fun commitInstallmentSourceAcknowledgement(expected: InstallmentAcknowledgementSnapshot, queued: QueuedMutation, requestBatchId: String?,
        remote: CloudRecord, remoteCycles: Map<String, CloudRecord?>, remoteLedger: Map<String, CloudRecord?>, now: String): Boolean =
        throw UnsupportedOperationException("Atomic installment source acknowledgement unavailable")

    suspend fun installmentDeletionBatch(owner: UserId, planId: String): InstallmentDeletionBatch? =
        throw UnsupportedOperationException("Durable installment deletion intent unavailable")

    suspend fun commitInstallmentCycleMutations(expected: InstallmentCycleSnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>): Boolean =
        throw UnsupportedOperationException("Conditional installment cycle writes unavailable")

    suspend fun installmentMutationSnapshot(owner: UserId, planId: String): InstallmentMutationSnapshot =
        throw UnsupportedOperationException("Complete installment mutation snapshots unavailable")
    suspend fun commitInstallmentMutations(expected: InstallmentMutationSnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>): Boolean =
        throw UnsupportedOperationException("Conditional installment writes unavailable")

    suspend fun installmentInvestmentMoneySnapshot(owner:UserId,planId:RecordId,month:java.time.YearMonth):BillMoneySnapshot =
        throw UnsupportedOperationException("Installment investment snapshot unavailable")
    suspend fun commitInstallmentInvestmentMoney(expected:BillMoneySnapshot,operation:InstallmentInvestmentMoneyOperation,catalog:SystemCategoryCatalog,
        deviceId:String,now:String,zone:java.time.ZoneId):InstallmentInvestmentMoneyPlan =
        throw UnsupportedOperationException("Installment investment commit unavailable")

    suspend fun billInvestmentMoneySnapshot(owner:UserId,billId:RecordId,month:java.time.YearMonth):BillMoneySnapshot =
        throw UnsupportedOperationException("Consistent bill investment snapshots unavailable")
    suspend fun commitBillInvestmentMoney(expected:BillMoneySnapshot,operation:BillInvestmentMoneyOperation,catalog:SystemCategoryCatalog,
        deviceId:String,now:String,zone:java.time.ZoneId):BillInvestmentMoneyPlan =
        throw UnsupportedOperationException("Atomic bill investment payment unavailable")

    suspend fun billMoneyReceiptTransactionIds(owner: UserId): Set<String> =
        throw UnsupportedOperationException("Bill receipt dependency snapshots unavailable")
    suspend fun commitBillMoneyMutations(snapshot: BillMoneySnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>) {
        throw UnsupportedOperationException("Conditional bill money writes unavailable")
    }
    /** Compare source and complete cycle snapshot inside the same transaction as occurrence/outbox writes. */
    suspend fun commitBillCycleMutations(bill:CloudRecord,monthKey:String,expectedOccurrences:List<CloudRecord>,mutations:List<Pair<CloudRecord,PendingMutation>>) {
        throw UnsupportedOperationException("Conditional bill cycle writes unavailable")
    }

    /** Insert-only category bootstrap: check missing IDs/system keys and write batch in one transaction. */
    suspend fun commitMissingSystemCategories(mutations: List<Pair<CloudRecord, PendingMutation>>) {
        throw UnsupportedOperationException("Conditional category bootstrap is unsupported")
    }
    /** Complete owner/entity snapshot; required for safe tombstone-aware reconciliation. */
    suspend fun recordsIncludingDeleted(ownerUserId: UserId, entity: String): List<CloudRecord> =
        throw UnsupportedOperationException("Complete local snapshots are unsupported")
    /** One consistent owner snapshot including historical metadata; unsupported stores fail explicitly. */
    fun observeBudgetReadSnapshot(owner:UserId):Flow<BudgetReadSnapshot> =
        throw UnsupportedOperationException("Consistent budget read snapshot unavailable")
    fun observe(entity: String, ownerUserId: UserId): Flow<List<CloudRecord>>
    fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>>
    suspend fun record(ownerUserId: UserId, entity: String, recordId: String): CloudRecord?
    suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation)
    suspend fun transactionSaveSnapshot(owner: UserId): TransactionSaveSnapshot =
        throw UnsupportedOperationException("Atomic transaction dependency snapshot unavailable")
    suspend fun transactionInvestmentSaveSnapshot(owner:UserId):TransactionInvestmentSaveSnapshot =
        throw UnsupportedOperationException("Atomic ordinary/investment dependency snapshot unavailable")
    suspend fun commitTransactionInvestmentSave(expected:TransactionInvestmentSaveSnapshot,request:TransactionInvestmentSaveRequest,
        deviceId:String,now:String,statementZone:java.time.ZoneId=java.time.ZoneId.systemDefault()):LedgerTransactionRecord =
        throw UnsupportedOperationException("Atomic ordinary/investment save unavailable")
    suspend fun commitTransactionMutation(expected: TransactionSaveSnapshot, record: CloudRecord, mutation: PendingMutation) {
        throw UnsupportedOperationException("Atomic validated transaction save unavailable")
    }
    /** Recheck the exact wallet and current ledger references atomically with the currency edit/outbox. */
    suspend fun commitWalletCurrencyMutation(expectedWallet: CloudRecord, record: CloudRecord, mutation: PendingMutation) {
        throw UnsupportedOperationException("Atomic wallet currency edits unavailable")
    }
    /** Implementations must commit the entire batch atomically or fail without writing. */
    suspend fun commitMutations(mutations: List<Pair<CloudRecord, PendingMutation>>) {
        require(mutations.size == 1) { "Atomic batch mutations are unsupported by this store" }
        commitMutation(mutations.single().first, mutations.single().second)
    }
    /** Create only: both identities and queues must be absent; commit the aggregate atomically or fail without writing. */
    suspend fun commitCreditCardMutation(
        walletRecord: CloudRecord,
        walletMutation: PendingMutation,
        profileRecord: CloudRecord,
        profileMutation: PendingMutation,
    ) {
        throw UnsupportedOperationException("Atomic guarded credit card creation unavailable")
    }
    /** Compare both existing card baselines and current dependencies in the same transaction as both outbox writes. */
    suspend fun commitCreditCardEdit(
        expectedWallet: CloudRecord, expectedProfile: CloudRecord,
        walletRecord: CloudRecord, walletMutation: PendingMutation,
        profileRecord: CloudRecord, profileMutation: PendingMutation,
    ) {
        throw UnsupportedOperationException("Atomic guarded credit card edits unavailable")
    }
    suspend fun commitCategoryMutation(
        record: CloudRecord,
        mutation: PendingMutation,
        translation: PendingCategoryTranslation,
    ) {
        commitMutation(record, mutation)
    }
    suspend fun pendingMutations(
        ownerUserId: UserId,
        entity: CloudEntity,
        dueAtEpochMillis: Long,
        limit: Int = 100,
    ): List<QueuedMutation>
    suspend fun acknowledgeMutation(mutation: QueuedMutation, remoteRecord: CloudRecord): Boolean
    suspend fun recordMutationFailure(
        mutation: QueuedMutation,
        nextAttemptAtEpochMillis: Long,
        errorCode: String,
    ): Boolean
    suspend fun pendingCategoryTranslations(
        ownerUserId: UserId,
        dueAtEpochMillis: Long,
        limit: Int = 16,
    ): List<QueuedCategoryTranslation> = emptyList()
    suspend fun enqueueMissingCategoryTranslations(
        ownerUserId: UserId,
        deviceId: String,
        limit: Int = 200,
    ): Int = 0
    suspend fun applyCategoryTranslation(
        task: QueuedCategoryTranslation,
        expectedRecord: CloudRecord,
        record: CloudRecord,
        mutation: PendingMutation,
    ): Boolean = false
    suspend fun discardCategoryTranslation(task: QueuedCategoryTranslation): Boolean = false
    suspend fun recordCategoryTranslationFailure(
        task: QueuedCategoryTranslation,
        nextAttemptAtEpochMillis: Long,
        errorCode: String,
    ): Boolean = false
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

data class SystemCategoryPage(val records: List<CloudRecord>, val nextOffset: Int?)
data class DueOccurrencePage(val records: List<CloudRecord>, val nextOffset: Int?)

interface RemoteMutationStore {
    suspend fun fetchInstallmentCyclePage(planId: String, month: String, accessToken: String, ownerUserId: UserId,
        offset: Int, limit: Int): DueOccurrencePage = throw UnsupportedOperationException("Complete installment cycle lookup unavailable")

    /** Includes legacy IDs and tombstones; consume nextOffset until null before reconciling. */
    suspend fun fetchSystemCategoryPage(
        systemKey: String,
        accessToken: String,
        ownerUserId: UserId,
        offset: Int,
        limit: Int,
    ): SystemCategoryPage = throw UnsupportedOperationException("System category key lookup is unavailable")

    suspend fun fetchRecord(
        entity: CloudEntity,
        recordId: String,
        accessToken: String,
        ownerUserId: UserId,
    ): CloudRecord?

    suspend fun createRecord(
        entity: CloudEntity,
        accessToken: String,
        ownerUserId: UserId,
        payload: JsonObject,
    ): CloudRecord

    suspend fun conditionalUpdate(
        entity: CloudEntity,
        recordId: String,
        accessToken: String,
        ownerUserId: UserId,
        expectedVersion: Long,
        payload: JsonObject,
    ): CloudRecord?
}

interface AssetStore {
    suspend fun uploadAvatar(userId: UserId, bytes: ByteArray): Result<String>
    suspend fun uploadInvestmentProductImage(userId: UserId, assetId: RecordId, bytes: ByteArray): Result<String>
    suspend fun download(path: String): Result<ByteArray>
}

interface SyncEngine {
    val status: StateFlow<SyncStatus>
    suspend fun syncNow(): Result<Int>
    suspend fun pullAll(): Result<Int>
    fun scheduleBackgroundSync()
}
