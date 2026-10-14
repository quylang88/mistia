package vn.com.quyln.mistia

import android.content.Context
import java.io.File
import java.time.Instant
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import vn.com.quyln.mistia.core.auth.KeystoreSessionStore
import vn.com.quyln.mistia.core.auth.KeystoreDeviceIdStore
import vn.com.quyln.mistia.core.auth.SecureSessionStore
import vn.com.quyln.mistia.core.auth.SecureDeviceIdStore
import vn.com.quyln.mistia.core.auth.SupabaseAuthRepository
import vn.com.quyln.mistia.core.auth.SupabaseDeviceRegistry
import vn.com.quyln.mistia.core.auth.GoogleSignInBridge
import vn.com.quyln.mistia.core.auth.GoogleSignInProvider
import vn.com.quyln.mistia.core.auth.AuthDiagnostics
import vn.com.quyln.mistia.core.database.MistiaDatabase
import vn.com.quyln.mistia.core.database.LocalTransactionReceiptImageRepository
import vn.com.quyln.mistia.core.database.OfflineFirstFamilyRepository
import vn.com.quyln.mistia.core.database.OfflineFirstFinanceRepository
import vn.com.quyln.mistia.core.database.OfflineFirstInvestmentRepository
import vn.com.quyln.mistia.core.database.LocalNotificationPreferencesStore
import vn.com.quyln.mistia.core.model.NotificationPreferencesStore
import vn.com.quyln.mistia.core.model.ReminderKind
import vn.com.quyln.mistia.core.database.RoomLocalStore
import vn.com.quyln.mistia.core.model.AuthRepository
import vn.com.quyln.mistia.core.model.DeviceRegistry
import vn.com.quyln.mistia.core.model.FamilyRepository
import vn.com.quyln.mistia.core.model.FinanceRepository
import vn.com.quyln.mistia.core.model.InvestmentRepository
import vn.com.quyln.mistia.core.model.ExchangeRateRepository
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.SystemCategoryCatalog
import vn.com.quyln.mistia.core.model.RemoteStore
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.ReceiptAnalysisClient
import vn.com.quyln.mistia.core.model.SyncEngine
import vn.com.quyln.mistia.core.model.TransactionReceiptImageRepository
import vn.com.quyln.mistia.core.network.SupabaseConfig
import vn.com.quyln.mistia.core.network.MistiaWireFormat
import vn.com.quyln.mistia.core.network.SupabasePostgrestRemoteStore
import vn.com.quyln.mistia.core.sync.PullOnlySyncEngine
import vn.com.quyln.mistia.core.sync.BudgetPushCoordinator
import vn.com.quyln.mistia.core.sync.SavingsGoalPushCoordinator
import vn.com.quyln.mistia.core.sync.DueOccurrencePushCoordinator
import vn.com.quyln.mistia.core.sync.RecurringBillPushCoordinator
import vn.com.quyln.mistia.core.sync.CategoryPushCoordinator
import vn.com.quyln.mistia.core.sync.CreditCardPushCoordinator
import vn.com.quyln.mistia.core.sync.TransactionPushCoordinator
import vn.com.quyln.mistia.core.sync.WalletPushCoordinator
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CategoryNameTranslator
import vn.com.quyln.mistia.core.network.SupabaseCategoryNameTranslator
import vn.com.quyln.mistia.core.network.FrankfurterExchangeRateRepository
import vn.com.quyln.mistia.core.network.SupabaseReceiptAnalysisClient
import vn.com.quyln.mistia.core.sync.CategoryMaintenanceCoordinator
import vn.com.quyln.mistia.core.sync.CategoryTranslationCoordinator

@Module
@InstallIn(SingletonComponent::class)
object AppModule {
    @Provides
    @Singleton
    fun provideJson(): Json = MistiaWireFormat.json

    @Provides
    @Singleton
    fun provideHttpClient(): OkHttpClient = OkHttpClient.Builder().build()

    @Provides
    @Singleton
    fun provideExchangeRateRepository(
        @ApplicationContext context: Context,
        client: OkHttpClient,
        json: Json,
    ): ExchangeRateRepository = FrankfurterExchangeRateRepository(context, client, json)

    @Provides
    @Singleton
    fun provideSupabaseConfig(): SupabaseConfig = SupabaseConfig(
        projectUrl = BuildConfig.SUPABASE_URL,
        anonKey = BuildConfig.SUPABASE_ANON_KEY,
    )

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): MistiaDatabase = MistiaDatabase.create(context)

    @Provides
    @Singleton
    fun provideTransactionReceiptImageRepository(
        @ApplicationContext context: Context,
        database: MistiaDatabase,
    ): TransactionReceiptImageRepository = LocalTransactionReceiptImageRepository(
        database = database,
        baseDirectory = File(context.filesDir, "ReceiptImages"),
    )

    @Provides
    @Singleton
    fun provideLocalStore(database: MistiaDatabase, json: Json,preferences:NotificationPreferencesStore,auth:AuthRepository): LocalStore =
        RoomLocalStore(database,json,billRemindersEnabled={preferences.state.value.reminderEnabled(ReminderKind.BILLS)},
            currentBillOwner={(auth.state.value as? vn.com.quyln.mistia.core.model.AuthState.SignedIn)?.session?.userId})

    @Provides
    @Singleton
    fun provideNotificationPreferences(@ApplicationContext context:Context):NotificationPreferencesStore = LocalNotificationPreferencesStore(context)

    @Provides
    @Singleton
    fun provideSecureSessionStore(@ApplicationContext context: Context): SecureSessionStore =
        KeystoreSessionStore(context)

    @Provides
    @Singleton
    fun provideSecureDeviceIdStore(@ApplicationContext context: Context): SecureDeviceIdStore =
        KeystoreDeviceIdStore(context)

    @Provides
    @Singleton
    fun provideDeviceRegistry(config: SupabaseConfig, client: OkHttpClient): DeviceRegistry =
        SupabaseDeviceRegistry(config, client)

    @Provides
    @Singleton
    fun provideAuthRepository(
        @ApplicationContext context: Context,
        config: SupabaseConfig,
        client: OkHttpClient,
        secureSessionStore: SecureSessionStore,
        json: Json,
    ): AuthRepository = SupabaseAuthRepository(config, client, secureSessionStore, json,
        clearCredentialState = { GoogleSignInBridge.clear(context) })

    @Provides
    @Singleton
    fun provideGoogleSignInBridge(diagnostics: AuthDiagnostics): GoogleSignInProvider =
        GoogleSignInBridge(BuildConfig.GOOGLE_WEB_CLIENT_ID, diagnostics)

    @Provides
    @Singleton
    fun provideAuthDiagnostics(): AuthDiagnostics = AuthDiagnostics { event ->
        if (BuildConfig.DEBUG) android.util.Log.i("MistiaAuth", event.name)
    }

    @Provides
    @Singleton
    fun providePostgrestStore(
        config: SupabaseConfig,
        client: OkHttpClient,
        json: Json,
    ): SupabasePostgrestRemoteStore = SupabasePostgrestRemoteStore(
        config = config,
        client = client,
        json = json,
        writableEntities = buildSet {
            if (BuildConfig.ALLOW_CLOUD_WRITES && BuildConfig.ALLOW_DUE_OCCURRENCE_CLOUD_WRITES && BuildConfig.ALLOW_TRANSACTION_CLOUD_WRITES && BuildConfig.ALLOW_RECURRING_BILL_CLOUD_WRITES && BuildConfig.ALLOW_WALLET_CLOUD_WRITES && BuildConfig.ALLOW_CATEGORY_CLOUD_WRITES) add(CloudEntity.DUE_OCCURRENCE_RECORD)
            if (BuildConfig.ALLOW_RECURRING_BILL_CLOUD_WRITES && BuildConfig.ALLOW_WALLET_CLOUD_WRITES && BuildConfig.ALLOW_CATEGORY_CLOUD_WRITES) {
                add(CloudEntity.RECURRING_BILL_PLAN)
            }
            if (BuildConfig.ALLOW_SAVINGS_GOAL_CLOUD_WRITES && BuildConfig.ALLOW_WALLET_CLOUD_WRITES) {
                add(CloudEntity.SAVINGS_GOAL)
            }
            if (BuildConfig.ALLOW_BUDGET_CLOUD_WRITES && BuildConfig.ALLOW_CATEGORY_CLOUD_WRITES) {
                add(CloudEntity.BUDGET_PLAN)
            }
            if (BuildConfig.ALLOW_CATEGORY_CLOUD_WRITES) add(CloudEntity.TRANSACTION_CATEGORY)
            if (BuildConfig.ALLOW_WALLET_CLOUD_WRITES) add(CloudEntity.LEDGER_WALLET)
            if (BuildConfig.ALLOW_CREDIT_CARD_CLOUD_WRITES) add(CloudEntity.CREDIT_CARD_PROFILE)
            if (BuildConfig.ALLOW_TRANSACTION_CLOUD_WRITES &&
                BuildConfig.ALLOW_WALLET_CLOUD_WRITES &&
                BuildConfig.ALLOW_CATEGORY_CLOUD_WRITES
            ) {
                add(CloudEntity.LEDGER_TRANSACTION)
            }
        },
    )

    @Provides
    @Singleton
    fun provideRemoteStore(store: SupabasePostgrestRemoteStore): RemoteStore = store

    @Provides
    @Singleton
    fun provideRemoteMutationStore(store: SupabasePostgrestRemoteStore): RemoteMutationStore = store

    @Provides
    @Singleton
    fun provideCategoryNameTranslator(
        config: SupabaseConfig,
        client: OkHttpClient,
        json: Json,
    ): CategoryNameTranslator = SupabaseCategoryNameTranslator(config, client, json)

    @Provides
    @Singleton
    fun provideReceiptAnalysisClient(
        config: SupabaseConfig,
        client: OkHttpClient,
        json: Json,
    ): ReceiptAnalysisClient = SupabaseReceiptAnalysisClient(config, client, json)

    @Provides
    @Singleton
    fun provideCategoryTranslationCoordinator(
        localStore: LocalStore,
        translator: CategoryNameTranslator,
        deviceIdStore: SecureDeviceIdStore,
    ): CategoryTranslationCoordinator = CategoryTranslationCoordinator(
        localStore = localStore,
        translator = translator,
        deviceIdProvider = deviceIdStore::getOrCreate,
    )

    @Provides
    @Singleton
    fun provideWalletPushCoordinator(
        localStore: LocalStore,
        remoteStore: RemoteMutationStore,
    ): WalletPushCoordinator = WalletPushCoordinator(
        localStore = localStore,
        remoteStore = remoteStore,
        writesEnabled = BuildConfig.ALLOW_WALLET_CLOUD_WRITES,
    )

    @Provides
    @Singleton
    fun provideSystemCategoryCatalog(@ApplicationContext context: Context): SystemCategoryCatalog =
        context.assets.open("MistiaSystemCategories.json").bufferedReader().use { SystemCategoryCatalog.parse(it.readText()) }

    @Provides
    @Singleton
    fun provideCategoryMaintenanceCoordinator(localStore:LocalStore,catalog:SystemCategoryCatalog,deviceIdStore:SecureDeviceIdStore):CategoryMaintenanceCoordinator =
        CategoryMaintenanceCoordinator(localStore,catalog,deviceIdStore::getOrCreate)

    @Provides
    @Singleton
    fun provideCategoryPushCoordinator(
        localStore: LocalStore,
        remoteStore: RemoteMutationStore,
        catalog: SystemCategoryCatalog,
    ): CategoryPushCoordinator = CategoryPushCoordinator(
        localStore = localStore,
        remoteStore = remoteStore,
        writesEnabled = BuildConfig.ALLOW_CATEGORY_CLOUD_WRITES,
        catalog = catalog,
    )

    @Provides
    @Singleton
    fun provideCreditCardPushCoordinator(
        localStore: LocalStore,
        remoteStore: RemoteMutationStore,
    ): CreditCardPushCoordinator = CreditCardPushCoordinator(
        localStore = localStore,
        remoteStore = remoteStore,
        writesEnabled = BuildConfig.ALLOW_CREDIT_CARD_CLOUD_WRITES &&
            BuildConfig.ALLOW_WALLET_CLOUD_WRITES,
    )

    @Provides
    @Singleton
    fun provideTransactionPushCoordinator(
        localStore: LocalStore,
        remoteStore: RemoteMutationStore,
    ): TransactionPushCoordinator = TransactionPushCoordinator(
        localStore = localStore,
        remoteStore = remoteStore,
        writesEnabled = BuildConfig.ALLOW_TRANSACTION_CLOUD_WRITES &&
            BuildConfig.ALLOW_WALLET_CLOUD_WRITES &&
            BuildConfig.ALLOW_CATEGORY_CLOUD_WRITES,
    )

    @Provides
    @Singleton
    fun provideBudgetPushCoordinator(
        localStore: LocalStore,
        remoteStore: RemoteMutationStore,
    ): BudgetPushCoordinator = BudgetPushCoordinator(
        localStore = localStore,
        remoteStore = remoteStore,
        writesEnabled = BuildConfig.ALLOW_BUDGET_CLOUD_WRITES && BuildConfig.ALLOW_CATEGORY_CLOUD_WRITES,
    )

    @Provides
    @Singleton
    fun provideSavingsGoalPushCoordinator(
        localStore: LocalStore,
        remoteStore: RemoteMutationStore,
    ): SavingsGoalPushCoordinator = SavingsGoalPushCoordinator(
        localStore = localStore,
        remoteStore = remoteStore,
        writesEnabled = BuildConfig.ALLOW_SAVINGS_GOAL_CLOUD_WRITES && BuildConfig.ALLOW_WALLET_CLOUD_WRITES,
    )

    @Provides
    @Singleton
    fun provideDueOccurrencePushCoordinator(localStore:LocalStore,remoteStore:RemoteMutationStore):DueOccurrencePushCoordinator =
        DueOccurrencePushCoordinator(localStore,remoteStore,writesEnabled=BuildConfig.ALLOW_CLOUD_WRITES && BuildConfig.ALLOW_DUE_OCCURRENCE_CLOUD_WRITES && BuildConfig.ALLOW_TRANSACTION_CLOUD_WRITES && BuildConfig.ALLOW_RECURRING_BILL_CLOUD_WRITES && BuildConfig.ALLOW_WALLET_CLOUD_WRITES && BuildConfig.ALLOW_CATEGORY_CLOUD_WRITES)

    @Provides
    @Singleton
    fun provideRecurringBillPushCoordinator(
        localStore: LocalStore,
        remoteStore: RemoteMutationStore,
    ): RecurringBillPushCoordinator = RecurringBillPushCoordinator(
        localStore = localStore,
        remoteStore = remoteStore,
        writesEnabled = BuildConfig.ALLOW_RECURRING_BILL_CLOUD_WRITES && BuildConfig.ALLOW_WALLET_CLOUD_WRITES && BuildConfig.ALLOW_CATEGORY_CLOUD_WRITES,
    )

    @Provides
    @Singleton
    fun provideFinanceRepository(@ApplicationContext context:Context,localStore: LocalStore, catalog: SystemCategoryCatalog): FinanceRepository =
        OfflineFirstFinanceRepository(localStore, systemCategoryCatalog=catalog,billNotificationText={formatBillNotification(context,it)},automaticBillText={bill,amount ->
            vn.com.quyln.mistia.core.model.BillAutomaticPaymentText(
                context.getString(vn.com.quyln.mistia.core.designsystem.R.string.shared_notifications_mistiarecurringbillmaintenance_auto_paid_value,bill.name),
                context.getString(vn.com.quyln.mistia.core.designsystem.R.string.shared_notifications_mistiarecurringbillmaintenance_auto_payment_complete),
                context.getString(vn.com.quyln.mistia.core.designsystem.R.string.shared_notifications_mistiarecurringbillmaintenance_mistia_paid_value_for_value,
                    vn.com.quyln.mistia.core.designsystem.formatMinorUnits(amount,bill.currencyCode),bill.name))
        })

    @Provides
    @Singleton
    fun provideSessionRestoration(auth:AuthRepository)=
        vn.com.quyln.mistia.core.sync.SessionRestorationCoordinator(auth.state) {auth.restore()}

    @Provides
    @Singleton
    fun provideBillMaintenanceCoordinator(auth:AuthRepository,finance:FinanceRepository,device:SecureDeviceIdStore)=
        vn.com.quyln.mistia.core.sync.BillMaintenanceCoordinator(auth.state,finance,{device.getOrCreate()},{Instant.now().toString()})

    @Provides
    @Singleton
    fun provideBackgroundBillMaintenance(restoration:vn.com.quyln.mistia.core.sync.SessionRestorationCoordinator,
        maintenance:vn.com.quyln.mistia.core.sync.BillMaintenanceCoordinator)=
        vn.com.quyln.mistia.core.sync.BackgroundBillMaintenanceTask(restoration,maintenance)

    @Provides
    @Singleton
    fun provideFamilyRepository(localStore: LocalStore): FamilyRepository =
        OfflineFirstFamilyRepository(localStore)

    @Provides
    @Singleton
    fun provideInvestmentRepository(localStore: LocalStore): InvestmentRepository =
        OfflineFirstInvestmentRepository(localStore)

    @Provides
    @Singleton
    fun provideSyncEngine(
        @ApplicationContext context: Context,
        authRepository: AuthRepository,
        localStore: LocalStore,
        remoteStore: RemoteStore,
        categoryPushCoordinator: CategoryPushCoordinator,
        walletPushCoordinator: WalletPushCoordinator,
        creditCardPushCoordinator: CreditCardPushCoordinator,
        transactionPushCoordinator: TransactionPushCoordinator,
        budgetPushCoordinator: BudgetPushCoordinator,
        savingsGoalPushCoordinator: SavingsGoalPushCoordinator,
        recurringBillPushCoordinator: RecurringBillPushCoordinator,
        dueOccurrencePushCoordinator: DueOccurrencePushCoordinator,
        categoryTranslationCoordinator: CategoryTranslationCoordinator,
        categoryMaintenanceCoordinator: CategoryMaintenanceCoordinator,
        financeRepository: FinanceRepository,
        catalog: SystemCategoryCatalog,
        deviceIdStore: SecureDeviceIdStore,
        preferences:NotificationPreferencesStore,
    ): SyncEngine = PullOnlySyncEngine(
        context,
        authRepository,
        localStore,
        remoteStore,
        listOf(
            categoryPushCoordinator,
            walletPushCoordinator,
            creditCardPushCoordinator,
            transactionPushCoordinator,
            budgetPushCoordinator,
            savingsGoalPushCoordinator,
            recurringBillPushCoordinator,
            dueOccurrencePushCoordinator,
        ),
        categoryTranslationCoordinator,
        categoryMaintenanceCoordinator,
        ensureDefaultCategories={owner ->
            financeRepository.ensureDefaultSystemCategories(owner,catalog,deviceIdStore.getOrCreate(),Instant.now().toString()).getOrThrow()
            Unit
        },
        familyNotificationsEnabled={preferences.state.value.familyEnabled},
    )
}
