package vn.com.quyln.mistia.feature.transactions

import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.time.Instant
import kotlinx.coroutines.flow.combine
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@Composable
fun NotificationTopUpSheet(owner:UserId,destinationWalletId:String,repository:FinanceRepository,
    exchangeRateRepository:ExchangeRateRepository,deviceIdProvider:suspend ()->String,onDismiss:()->Unit,primaryCurrencyCode:String="JPY") {
    key(owner.value,destinationWalletId) {
        val adjustmentTitle=stringResource(R.string.investment_wallet_history_adjustment)
        val data by produceState<Pair<List<LedgerWalletRecord>,List<TransactionCategoryRecord>>?>(null,owner) {
            combine(repository.observeWallets(owner),repository.observeCategories(owner)) {wallets,categories -> wallets to categories}.collect {value=it}
        }
        val rates by exchangeRateRepository.rates.collectAsStateWithLifecycle()
        LaunchedEffect(exchangeRateRepository) {exchangeRateRepository.refreshIfStale()}
        val initial=remember(owner,destinationWalletId) {notificationTopUpState(Instant.now().toString(),destinationWalletId)}
        val snapshot=data
        if(snapshot==null) AlertDialog(onDismissRequest=onDismiss,text={CircularProgressIndicator()},confirmButton={})
        else if(snapshot.first.none {it.id==destinationWalletId && it.ownerUserId==owner.value && !it.isArchived && it.deletedAt==null}) {
            AlertDialog(onDismissRequest=onDismiss,text={Text(stringResource(R.string.planning_planning_a_matching_payment_wallet_could_not_be))},
                confirmButton={TextButton(onClick=onDismiss) {Text(stringResource(R.string.common_ok))}})
        } else TransactionEditorSheet(owner.value,null,snapshot.first,snapshot.second,rates,initial.occurredAt,primaryCurrencyCode,initialState=initial,onDismiss=onDismiss,
            saveSessionKey=repository,onSave={draft -> repository.saveTransactionWithInvestmentFunds(owner,TransactionInvestmentSaveRequest(draft,draft.creationIdentity,draft.investmentConsent,adjustmentTitle,primaryCurrencyCode),deviceIdProvider(),Instant.now().toString())})
    }
}
