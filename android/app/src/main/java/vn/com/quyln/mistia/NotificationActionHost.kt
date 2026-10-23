package vn.com.quyln.mistia

import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.res.stringResource
import java.time.ZoneId
import kotlinx.coroutines.flow.combine
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.feature.planning.NotificationBillPaymentSheet
import vn.com.quyln.mistia.feature.transactions.NotificationTopUpSheet

private data class ReadyNotificationAction(val action:NotificationBillAction?)
@Composable
internal fun NotificationActionHost(owner:UserId,row:AppNotificationRecord,repository:FinanceRepository,
    rates:ExchangeRateRepository,deviceId:suspend ()->String,onDismiss:()->Unit,primaryCurrencyCode:String="JPY") {
    key(owner.value,row.key,repository,primaryCurrencyCode) {
        val ready by produceState<ReadyNotificationAction?>(null,owner,row.key) {
            combine(repository.observeRecurringBills(owner),repository.observeDueOccurrences(owner),repository.observeWallets(owner)) {bills,occurrences,wallets ->
                notificationBillAction(owner,row,bills,occurrences,wallets,ZoneId.systemDefault())
            }.collect {if(value==null) value=ReadyNotificationAction(it)}
        }
        when(val action=ready?.action) {
            is NotificationBillAction.Pay -> NotificationBillPaymentSheet(owner,action,repository,deviceId,onDismiss,primaryCurrencyCode)
            is NotificationBillAction.TopUp -> NotificationTopUpSheet(owner,action.walletId,repository,rates,deviceId,onDismiss,primaryCurrencyCode)
            null -> if(ready==null) AlertDialog(onDismissRequest=onDismiss,text={CircularProgressIndicator()},confirmButton={})
                else AlertDialog(onDismissRequest=onDismiss,text={Text(stringResource(R.string.planning_duepayment_could_not_find_the_due_item))},
                    confirmButton={TextButton(onClick=onDismiss) {Text(stringResource(R.string.common_ok))}})
        }
    }
}
