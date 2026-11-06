package vn.com.quyln.mistia

import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavHostController
import androidx.navigation.compose.composable
import vn.com.quyln.mistia.core.model.FinanceRepository
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.feature.management.CreditCardEditorRoute
import vn.com.quyln.mistia.feature.management.CreditCardStatementScreen

/** Shared by the actual application graph and its Room-backed navigation tests. */
internal fun NavGraphBuilder.planningCreditCardDestinations(owner: UserId, repository: FinanceRepository,
    navController: NavHostController, deviceIdProvider: () -> String, enabledCurrencyCodes: List<String>, primaryCurrencyCode: String) {
    composable("credit-card-statements/{walletId}") { entry ->
        val walletId = entry.arguments?.getString("walletId") ?: return@composable
        CreditCardStatementScreen(owner, walletId, repository, onBack = { navController.popBackStack() },
            deviceIdProvider = deviceIdProvider, primaryCurrencyCode = primaryCurrencyCode)
    }
    composable("credit-card-editor/{walletId}") { entry ->
        val target = entry.arguments?.getString("walletId") ?: return@composable
        CreditCardEditorRoute(owner, target.takeUnless { it == "new" }, repository,
            deviceIdProvider = { deviceIdProvider() }, onDismiss = { navController.popBackStack() },
            enabledCurrencyCodes = enabledCurrencyCodes)
    }
}
