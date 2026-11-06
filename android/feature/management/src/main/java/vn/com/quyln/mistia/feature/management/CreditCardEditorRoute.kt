package vn.com.quyln.mistia.feature.management

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

private sealed interface CardEditorLoad {
    data object Loading : CardEditorLoad
    data object Failed : CardEditorLoad
    data class Loaded(val snapshot: CreditCardAccountReadSnapshot, val wallets: List<LedgerWalletRecord>,
        val account: PlanningCreditCardAccount?) : CardEditorLoad
}

/** Shared owned controller for Management and Planning; the existing sheet remains the form. */
@Composable
fun CreditCardEditorRoute(owner: UserId, walletId: String?, repository: FinanceRepository,
    deviceIdProvider: suspend () -> String, onDismiss: () -> Unit,
    enabledCurrencyCodes: List<String> = listOf("JPY", "VND")) {
    key(owner.value, walletId, repository) {
        OwnedCreditCardEditorRoute(owner, walletId, repository, deviceIdProvider, onDismiss, enabledCurrencyCodes)
    }
}

@Composable
private fun OwnedCreditCardEditorRoute(owner: UserId, walletId: String?, repository: FinanceRepository,
    deviceIdProvider: suspend () -> String, onDismiss: () -> Unit, enabledCurrencyCodes: List<String>) {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var retry by remember { mutableIntStateOf(0) }
    val load by produceState<CardEditorLoad>(CardEditorLoad.Loading, lifecycle, retry) {
        value = CardEditorLoad.Loading
        try {
            lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                repository.observeCreditCardAccountReadSnapshot(owner).collect { snapshot ->
                    currentCoroutineContext().ensureActive()
                    require(snapshot.owner == owner)
                    val accounts = planningCreditCardAccounts(snapshot)
                    val wallets = snapshot.rows.filter { it.entity == CloudEntity.LEDGER_WALLET.table }.map(LedgerWalletRecord::fromCloudRecord)
                    value = CardEditorLoad.Loaded(snapshot, wallets, accounts.singleOrNull { it.wallet.id == walletId })
                }
            }
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { value = CardEditorLoad.Failed }
    }
    val latestDismiss by rememberUpdatedState(onDismiss)
    val latestDevice by rememberUpdatedState(deviceIdProvider)
    val loaded = load as? CardEditorLoad.Loaded
    val invalidTarget = loaded != null && walletId != null && loaded.account == null
    LaunchedEffect(invalidTarget) { if (invalidTarget) latestDismiss() }
    when {
        invalidTarget -> Unit
        load == CardEditorLoad.Loading -> Column(Modifier.fillMaxWidth().padding(24.dp).testTag("card.route.loading"),
            horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator()
            Text(stringResource(R.string.app_mistia_loading_your_data))
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_close)) }
        }
        load == CardEditorLoad.Failed -> Column(Modifier.fillMaxWidth().padding(24.dp).testTag("card.route.error")) {
            Text(stringResource(R.string.planning_card_accounts_load_failed))
            TextButton(onClick = { retry++ }, modifier = Modifier.testTag("card.route.retry")) { Text(stringResource(R.string.planning_installment_retry)) }
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_close)) }
        }
        loaded != null -> {
            val account = loaded.account
            // Keep both the restored draft and its original raw comparison generation together.
            val originalRows = rememberSaveable(owner.value, walletId, account?.profile?.id) {
                account?.let { card -> listOf(CloudEntity.LEDGER_WALLET.table to card.wallet.id, CloudEntity.CREDIT_CARD_PROFILE.table to card.profile.id).map { (entity, id) ->
                    Json.encodeToString(loaded.snapshot.rows.single { it.entity == entity && it.id == id })
                } }.orEmpty()
            }
            val createWalletId = rememberSaveable { UUID.randomUUID().toString() }
            val createProfileId = rememberSaveable { UUID.randomUUID().toString() }
            val currencyEditable = account == null || loaded.snapshot.rows.none { row ->
                row.entity == CloudEntity.LEDGER_TRANSACTION.table && listOf("source_wallet_id", "destination_wallet_id").any { key ->
                    row.payload.financeRawString(key)?.trim()?.equals(account.wallet.id, ignoreCase = true) == true
                }
            }
            CreditCardEditorSheet(owner.value, account?.wallet, account?.profile, loaded.wallets,
                nextSortOrder = ((loaded.wallets.maxOfOrNull { it.sortOrder } ?: -1).toLong() + 1).coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                currencyEditable = currencyEditable, enabledCurrencyCodes = enabledCurrencyCodes,
                onDismiss = onDismiss, onSave = { draft ->
                    try {
                        currentCoroutineContext().ensureActive()
                        val expectation = if (walletId != null) {
                            check(originalRows.size == 2)
                            CreditCardEditExpectation(Json.decodeFromString(originalRows[0]), Json.decodeFromString(originalRows[1]))
                        } else null
                        val device = latestDevice()
                        currentCoroutineContext().ensureActive()
                        val request = draft.copy(walletId = draft.walletId ?: createWalletId,
                            profileId = draft.profileId ?: createProfileId, expectedEdit = expectation)
                        val result = repository.saveCreditCard(owner, request, device, Instant.now().toString())
                        currentCoroutineContext().ensureActive()
                        result.exceptionOrNull()?.let { if (it is CancellationException) throw it }
                        result
                    } catch (cancelled: CancellationException) { throw cancelled }
                    catch (error: Exception) { Result.failure(error) }
                })
        }
    }
}
