package vn.com.quyln.mistia

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
import vn.com.quyln.mistia.core.model.InvestmentRepository
import vn.com.quyln.mistia.core.model.SyncEngine
import vn.com.quyln.mistia.core.auth.SecureDeviceIdStore
import vn.com.quyln.mistia.feature.family.FamilyScreen
import vn.com.quyln.mistia.feature.investment.InvestmentScreen
import vn.com.quyln.mistia.feature.management.ManagementScreen
import vn.com.quyln.mistia.feature.overview.OverviewScreen
import vn.com.quyln.mistia.feature.planning.PlanningScreen
import vn.com.quyln.mistia.feature.transactions.TransactionsScreen

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    @Inject lateinit var authRepository: AuthRepository
    @Inject lateinit var financeRepository: FinanceRepository
    @Inject lateinit var familyRepository: FamilyRepository
    @Inject lateinit var investmentRepository: InvestmentRepository
    @Inject lateinit var syncEngine: SyncEngine
    @Inject lateinit var deviceRegistry: DeviceRegistry
    @Inject lateinit var deviceIdStore: SecureDeviceIdStore

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
                    familyRepository = familyRepository,
                    investmentRepository = investmentRepository,
                    syncEngine = syncEngine,
                    deviceRegistry = deviceRegistry,
                    deviceIdStore = deviceIdStore,
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
    familyRepository: FamilyRepository,
    investmentRepository: InvestmentRepository,
    syncEngine: SyncEngine,
    deviceRegistry: DeviceRegistry,
    deviceIdStore: SecureDeviceIdStore,
    openedFromFamilyInvite: Boolean,
) {
    val authState by authRepository.state.collectAsStateWithLifecycle()
    LaunchedEffect(authRepository) { authRepository.restore() }

    when (val state = authState) {
        AuthState.Restoring -> FullScreenProgress()
        AuthState.SignedOut,
        is AuthState.Failure,
        -> vn.com.quyln.mistia.auth.AuthScreen()
        is AuthState.SignedIn -> {
            LaunchedEffect(state.session.userId.value) {
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
                syncEngine.syncNow()
            }
            SignedInRoot(
                authState = state,
                authRepository = authRepository,
                financeRepository = financeRepository,
                familyRepository = familyRepository,
                investmentRepository = investmentRepository,
                syncEngine = syncEngine,
                deviceIdStore = deviceIdStore,
                openedFromFamilyInvite = openedFromFamilyInvite,
            )
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
    familyRepository: FamilyRepository,
    investmentRepository: InvestmentRepository,
    syncEngine: SyncEngine,
    deviceIdStore: SecureDeviceIdStore,
    openedFromFamilyInvite: Boolean,
) {
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
                    )
                    RootTab.TRANSACTIONS -> TransactionsScreen(
                        authState.session.userId,
                        financeRepository,
                        modifier,
                    )
                    RootTab.PLANNING -> PlanningScreen(
                        authState.session.userId,
                        financeRepository,
                        modifier,
                    )
                    RootTab.MANAGEMENT -> ManagementScreen(
                        ownerUserId = authState.session.userId,
                        repository = financeRepository,
                        deviceIdProvider = { deviceIdStore.getOrCreate() },
                        onSyncNow = { scope.launch { syncEngine.syncNow() } },
                        onSignOut = { scope.launch { authRepository.signOut() } },
                        onOpenFamily = { navController.navigate("family") },
                        onOpenInvestment = { navController.navigate("investment") },
                        modifier = modifier,
                    )
                }
            }
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
}

@Composable
private fun FullScreenProgress() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}
