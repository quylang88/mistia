package vn.com.quyln.mistia

import android.content.Context
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
import vn.com.quyln.mistia.core.database.OfflineFirstFamilyRepository
import vn.com.quyln.mistia.core.database.OfflineFirstFinanceRepository
import vn.com.quyln.mistia.core.database.OfflineFirstInvestmentRepository
import vn.com.quyln.mistia.core.database.RoomLocalStore
import vn.com.quyln.mistia.core.model.AuthRepository
import vn.com.quyln.mistia.core.model.DeviceRegistry
import vn.com.quyln.mistia.core.model.FamilyRepository
import vn.com.quyln.mistia.core.model.FinanceRepository
import vn.com.quyln.mistia.core.model.InvestmentRepository
import vn.com.quyln.mistia.core.model.ExchangeRateRepository
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.RemoteStore
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.ReceiptAnalysisClient
import vn.com.quyln.mistia.core.model.SyncEngine
import vn.com.quyln.mistia.core.network.SupabaseConfig
import vn.com.quyln.mistia.core.network.MistiaWireFormat
import vn.com.quyln.mistia.core.network.SupabasePostgrestRemoteStore
import vn.com.quyln.mistia.core.sync.PullOnlySyncEngine
import vn.com.quyln.mistia.core.sync.CategoryPushCoordinator
import vn.com.quyln.mistia.core.sync.CreditCardPushCoordinator
import vn.com.quyln.mistia.core.sync.TransactionPushCoordinator
import vn.com.quyln.mistia.core.sync.WalletPushCoordinator
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CategoryNameTranslator
import vn.com.quyln.mistia.core.network.SupabaseCategoryNameTranslator
import vn.com.quyln.mistia.core.network.FrankfurterExchangeRateRepository
import vn.com.quyln.mistia.core.network.SupabaseReceiptAnalysisClient
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
    fun provideLocalStore(database: MistiaDatabase, json: Json): LocalStore = RoomLocalStore(database, json)

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
    fun provideCategoryPushCoordinator(
        localStore: LocalStore,
        remoteStore: RemoteMutationStore,
    ): CategoryPushCoordinator = CategoryPushCoordinator(
        localStore = localStore,
        remoteStore = remoteStore,
        writesEnabled = BuildConfig.ALLOW_CATEGORY_CLOUD_WRITES,
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
    fun provideFinanceRepository(localStore: LocalStore): FinanceRepository =
        OfflineFirstFinanceRepository(localStore)

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
        categoryTranslationCoordinator: CategoryTranslationCoordinator,
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
        ),
        categoryTranslationCoordinator,
    )
}
