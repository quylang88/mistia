package vn.com.quyln.mistia

import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import vn.com.quyln.mistia.core.sync.SessionRestorationCoordinator
import vn.com.quyln.mistia.core.sync.BillMaintenanceCoordinator
import vn.com.quyln.mistia.core.sync.runForegroundBillMaintenance
import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import vn.com.quyln.mistia.core.model.NotificationPreferencesStore
import android.os.Bundle
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.produceState
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import kotlinx.coroutines.launch
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.R as DesignR
import vn.com.quyln.mistia.core.model.AuthRepository
import vn.com.quyln.mistia.core.model.AuthState
import vn.com.quyln.mistia.core.model.FamilyRepository
import vn.com.quyln.mistia.core.model.DeviceRegistration
import vn.com.quyln.mistia.core.model.DeviceRegistry
import vn.com.quyln.mistia.core.model.FinanceRepository
import vn.com.quyln.mistia.core.model.ExchangeRateRepository
import vn.com.quyln.mistia.core.model.InvestmentRepository
import vn.com.quyln.mistia.core.model.ReceiptAnalysisClient
import vn.com.quyln.mistia.core.model.SyncEngine
import vn.com.quyln.mistia.core.model.TransactionReceiptImageRepository
import vn.com.quyln.mistia.core.auth.SecureDeviceIdStore
import vn.com.quyln.mistia.feature.family.FamilyScreen
import vn.com.quyln.mistia.feature.investment.InvestmentScreen
import vn.com.quyln.mistia.feature.management.ManagementScreen
import vn.com.quyln.mistia.feature.overview.OverviewScreen
import vn.com.quyln.mistia.feature.planning.PlanningScreen
import vn.com.quyln.mistia.feature.transactions.TransactionsScreen
import vn.com.quyln.mistia.core.sync.CategoryTranslationCoordinator

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    @Inject lateinit var authRepository: AuthRepository
    @Inject lateinit var notificationPreferences:NotificationPreferencesStore
    @Inject lateinit var financeRepository: FinanceRepository
    @Inject lateinit var familyRepository: FamilyRepository
    @Inject lateinit var investmentRepository: InvestmentRepository
    @Inject lateinit var sessionRestoration:SessionRestorationCoordinator
    @Inject lateinit var billMaintenance:BillMaintenanceCoordinator
    @Inject lateinit var syncEngine: SyncEngine
    @Inject lateinit var deviceRegistry: DeviceRegistry
    @Inject lateinit var deviceIdStore: SecureDeviceIdStore
    @Inject lateinit var categoryTranslationCoordinator: CategoryTranslationCoordinator
    @Inject lateinit var exchangeRateRepository: ExchangeRateRepository
    @Inject lateinit var receiptAnalysisClient: ReceiptAnalysisClient
    @Inject lateinit var receiptImageRepository: TransactionReceiptImageRepository

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val openedFromFamilyInvite = intent?.data?.let { uri ->
            uri.host == "family-invite" || uri.path.orEmpty().startsWith("/invite/family/")
        } == true
        setContent {
            MistiaTheme(darkTheme = isSystemInDarkTheme()) {
                MistiaApp(
                    authRepository = authRepository,
                    financeRepository = financeRepository,
                    notificationPreferences=notificationPreferences,
                    familyRepository = familyRepository,
                    investmentRepository = investmentRepository,
                    syncEngine = syncEngine,
                    billMaintenance=billMaintenance,
                    sessionRestoration=sessionRestoration,
                    deviceRegistry = deviceRegistry,
                    deviceIdStore = deviceIdStore,
                    categoryTranslationCoordinator = categoryTranslationCoordinator,
                    exchangeRateRepository = exchangeRateRepository,
                    receiptAnalysisClient = receiptAnalysisClient,
                    receiptImageRepository = receiptImageRepository,
                    openedFromFamilyInvite = openedFromFamilyInvite,
                )
            }
        }
    }
}

@Composable
private fun MistiaApp(
    authRepository: AuthRepository,
    financeRepository: FinanceRepository,
    notificationPreferences:NotificationPreferencesStore,
    familyRepository: FamilyRepository,
    investmentRepository: InvestmentRepository,
    syncEngine: SyncEngine,
    billMaintenance:BillMaintenanceCoordinator,
    sessionRestoration:SessionRestorationCoordinator,
    deviceRegistry: DeviceRegistry,
    deviceIdStore: SecureDeviceIdStore,
    categoryTranslationCoordinator: CategoryTranslationCoordinator,
    exchangeRateRepository: ExchangeRateRepository,
    receiptAnalysisClient: ReceiptAnalysisClient,
    receiptImageRepository: TransactionReceiptImageRepository,
    openedFromFamilyInvite: Boolean,
) {
    val lifecycleOwner=LocalLifecycleOwner.current
    val authState by authRepository.state.collectAsStateWithLifecycle()
    LaunchedEffect(sessionRestoration) {sessionRestoration.ensureRestored()}

    when (val state = authState) {
        AuthState.Restoring -> FullScreenProgress()
        AuthState.SignedOut,
        is AuthState.Failure,
        -> vn.com.quyln.mistia.auth.AuthScreen()
        is AuthState.SignedIn -> {
            LaunchedEffect(state.session.userId.value,lifecycleOwner) {
                deviceRegistry.register(
                    state.session,
                    DeviceRegistration(
                        userId = state.session.userId,
                        deviceId = deviceIdStore.getOrCreate(),
                        deviceName = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                        modelIdentifier = Build.DEVICE,
                        modelDisplayName = Build.MODEL,
                        systemName = "Android",
                        systemVersion = Build.VERSION.RELEASE,
                        appVersion = BuildConfig.VERSION_NAME,
                        appBuild = BuildConfig.VERSION_CODE.toString(),
                    ),
                )
                syncEngine.scheduleBackgroundSync()
                lifecycleOwner.lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
                    runForegroundBillMaintenance(synchronize={syncEngine.syncNow()},maintain={billMaintenance.run()})
                }
            }
            key(state.session.userId.value) {
            SignedInRoot(
                authState = state,
                authRepository = authRepository,
                financeRepository = financeRepository,
                notificationPreferences=notificationPreferences,
                familyRepository = familyRepository,
                investmentRepository = investmentRepository,
                syncEngine = syncEngine,
                deviceIdStore = deviceIdStore,
                categoryTranslationCoordinator = categoryTranslationCoordinator,
                exchangeRateRepository = exchangeRateRepository,
                receiptAnalysisClient = receiptAnalysisClient,
                receiptImageRepository = receiptImageRepository,
                openedFromFamilyInvite = openedFromFamilyInvite,
            )
            }
        }
    }
}

private enum class RootTab(val titleResource: Int, val icon: ImageVector) {
    OVERVIEW(DesignR.string.app_roottab_overview, Icons.Default.Home),
    TRANSACTIONS(DesignR.string.app_roottab_transactions, Icons.Default.SwapHoriz),
    PLANNING(DesignR.string.app_roottab_planning, Icons.Default.Flag),
    MANAGEMENT(DesignR.string.app_roottab_manage, Icons.Default.Layers),
}

@Composable
private fun SignedInRoot(
    authState: AuthState.SignedIn,
    authRepository: AuthRepository,
    financeRepository: FinanceRepository,
    notificationPreferences:NotificationPreferencesStore,
    familyRepository: FamilyRepository,
    investmentRepository: InvestmentRepository,
    syncEngine: SyncEngine,
    deviceIdStore: SecureDeviceIdStore,
    categoryTranslationCoordinator: CategoryTranslationCoordinator,
    exchangeRateRepository: ExchangeRateRepository,
    receiptAnalysisClient: ReceiptAnalysisClient,
    receiptImageRepository: TransactionReceiptImageRepository,
    openedFromFamilyInvite: Boolean,
) {
    val notificationRows by produceState<List<vn.com.quyln.mistia.core.model.AppNotificationRecord>?>(null,authState.session.userId,financeRepository) {
        financeRepository.observeAppNotifications(authState.session.userId).collect {value=it}
    }
    var notificationActionKey by rememberSaveable(authState.session.userId.value) {mutableStateOf<String?>(null)}
    val unreadNotifications=vn.com.quyln.mistia.core.model.notificationGroups(authState.session.userId,notificationRows.orEmpty(),java.time.Instant.now()).sumOf {it.unreadCount}
    val navController = rememberNavController()
    val scope = rememberCoroutineScope()
    LaunchedEffect(openedFromFamilyInvite) {
        if (openedFromFamilyInvite) navController.navigate("family")
    }
    NavHost(navController = navController, startDestination = "tabs") {
        composable("tabs") {
            var selected by rememberSaveable { mutableStateOf(RootTab.OVERVIEW) }
            Scaffold(
                bottomBar = {
                    NavigationBar {
                        RootTab.entries.forEach { tab ->
                            NavigationBarItem(
                                selected = selected == tab,
                                onClick = { selected = tab },
                                icon = { Icon(tab.icon, contentDescription = stringResource(tab.titleResource)) },
                                label = { Text(stringResource(tab.titleResource)) },
                            )
                        }
                    }
                },
            ) { padding ->
                val modifier = Modifier.padding(padding)
                when (selected) {
                    RootTab.OVERVIEW -> OverviewScreen(
                        authState.session.userId,
                        financeRepository,
                        syncEngine.status,
                        modifier,
                        unreadNotificationCount=unreadNotifications,
                        onOpenNotifications={navController.navigate("notifications")},
                    )
                    RootTab.TRANSACTIONS -> TransactionsScreen(
                        ownerUserId = authState.session.userId,
                        repository = financeRepository,
                        exchangeRateRepository = exchangeRateRepository,
                        receiptAnalysisClient = receiptAnalysisClient,
                        receiptImageRepository = receiptImageRepository,
                        accessTokenProvider = {
                            (authRepository.refreshIfNeeded().getOrNull() ?: authState.session).accessToken
                        },
                        deviceIdProvider = { deviceIdStore.getOrCreate() },
                        modifier = modifier,
                    )
                    RootTab.PLANNING -> PlanningScreen(
                        authState.session.userId,
                        financeRepository,
                        modifier,
                        deviceIdProvider = { deviceIdStore.getOrCreate() },
                        exchangeRateRepository = exchangeRateRepository,
                    )
                    RootTab.MANAGEMENT -> ManagementScreen(
                        ownerUserId = authState.session.userId,
                        repository = financeRepository,
                        deviceIdProvider = { deviceIdStore.getOrCreate() },
                        onTranslatePendingCategories = {
                            val session = authRepository.refreshIfNeeded().getOrNull() ?: authState.session
                            categoryTranslationCoordinator.translatePending(
                                ownerUserId = session.userId,
                                accessToken = session.accessToken,
                            )
                        },
                        onSyncNow = { scope.launch { syncEngine.syncNow() } },
                        onSignOut = { scope.launch { authRepository.signOut() } },
                        onOpenFamily = { navController.navigate("family") },
                        onOpenInvestment = { navController.navigate("investment") },
                        onOpenNotificationSettings={navController.navigate("notification-settings")},
                        modifier = modifier,
                    )
                }
            }
        }
        composable("notification-settings") {
            val context=LocalContext.current
            val permission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
            vn.com.quyln.mistia.feature.settings.NotificationSettingsScreen(notificationPreferences,
                onBack={navController.popBackStack()},onRequestPermission={
                    if(Build.VERSION.SDK_INT>=33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)
                        permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                })
        }
        composable("notifications") {
            vn.com.quyln.mistia.feature.notifications.NotificationCenterScreen(authState.session.userId,financeRepository,
                onBack={navController.popBackStack()},onRefresh={syncEngine.syncNow()},onOpenNotification={row ->
                    if(row.kind in setOf("billPaymentRequired","billOverdue","billAutoPaymentFailed")) notificationActionKey=row.key
                })
        }
        composable("family") {
            FamilyScreen(
                ownerUserId = authState.session.userId,
                repository = familyRepository,
                onBack = { navController.popBackStack() },
            )
        }
        composable("investment") {
            InvestmentScreen(
                ownerUserId = authState.session.userId,
                repository = investmentRepository,
                onBack = { navController.popBackStack() },
            )
        }
    }
    if(notificationActionKey!=null && notificationRows!=null) {
        val row=notificationRows!!.singleOrNull {it.key==notificationActionKey}
        if(row==null) LaunchedEffect(notificationActionKey) {notificationActionKey=null}
        else NotificationActionHost(authState.session.userId,row,financeRepository,exchangeRateRepository,
            {deviceIdStore.getOrCreate()},{notificationActionKey=null})
    }
}

@Composable
private fun FullScreenProgress() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}
