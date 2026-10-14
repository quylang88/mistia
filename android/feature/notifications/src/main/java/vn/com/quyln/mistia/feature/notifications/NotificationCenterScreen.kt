package vn.com.quyln.mistia.feature.notifications

import androidx.activity.compose.BackHandler
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotificationCenterScreen(owner:UserId,repository:AppNotificationRepository,onBack:()->Unit,
    onRefresh:suspend ()->Result<*>,modifier:Modifier=Modifier,onOpenNotification:(AppNotificationRecord)->Unit={}) {
    key(owner.value) {NotificationCenterContent(owner,repository,onBack,onRefresh,modifier,onOpenNotification)}
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NotificationCenterContent(owner:UserId,repository:AppNotificationRepository,onBack:()->Unit,
    onRefresh:suspend ()->Result<*>,modifier:Modifier,onOpenNotification:(AppNotificationRecord)->Unit) {
    val rows by remember(owner,repository) {repository.observeAppNotifications(owner)}.collectAsStateWithLifecycle(emptyList())
    val groups=notificationGroups(owner,rows,Instant.now())
    var selected by rememberSaveable(owner.value) {mutableStateOf<String?>(null)}
    var menu by remember {mutableStateOf(false)}
    var busy by remember {mutableStateOf(false)}
    var refreshing by remember {mutableStateOf(false)}
    var error by remember {mutableStateOf(false)}
    val scope=rememberCoroutineScope()
    val group=groups.firstOrNull {it.id.name==selected}
    fun read(keys:Set<String>?) {
        if(busy) return
        busy=true
        scope.launch {
            try {error=repository.markNotificationsRead(owner,keys,Instant.now().toString()).isFailure}
            catch(cancelled:CancellationException) {throw cancelled}
            catch(_:Exception) {error=true}
            finally {busy=false}
        }
    }
    BackHandler(enabled=selected!=null) {selected=null}
    fun refresh() {
        if(busy) return
        busy=true;refreshing=true
        scope.launch {
            try {error=onRefresh().isFailure} catch(cancelled:CancellationException) {throw cancelled}
            catch(_:Exception) {error=true} finally {busy=false;refreshing=false}
        }
    }
    Scaffold(modifier=modifier.testTag("notification-center"),topBar={LargeTopAppBar(
        title={Text(stringResource(group?.id?.title() ?: R.string.notifications_notificationcenter_notifications))},
        navigationIcon={IconButton(onClick={if(selected!=null) selected=null else onBack()}) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack,stringResource(R.string.common_close))
        }},actions={
            if(busy) CircularProgressIndicator(Modifier.size(22.dp))
            Box {
                IconButton(onClick={menu=true},enabled=!busy) {Icon(Icons.Default.MoreVert,stringResource(R.string.notifications_notificationcenter_notification_actions))}
                DropdownMenu(expanded=menu,onDismissRequest={menu=false}) {
                    DropdownMenuItem(text={Text(stringResource(R.string.notifications_notificationcenter_mark_all_as_read))},onClick={menu=false;read(null)})
                    DropdownMenuItem(text={Text(stringResource(R.string.management_managementauth_sync_now))},onClick={
                        menu=false;refresh()
                    })
                }
            }
        })}) {padding ->
        PullToRefreshBox(isRefreshing=refreshing,onRefresh={refresh()},modifier=Modifier.fillMaxSize().padding(padding)) {
        LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(bottom=22.dp)) {
            if(groups.isEmpty() || (selected!=null && group==null)) item {
                Column(Modifier.fillMaxWidth().padding(32.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Default.NotificationsNone,null,Modifier.size(40.dp),tint=MaterialTheme.colorScheme.primary)
                    Text(stringResource(R.string.notifications_notificationcenter_no_notifications_yet),style=MaterialTheme.typography.titleLarge)
                    Text(stringResource(R.string.notifications_notificationcenter_permission_requests_and_family_activity_will_appear),color=MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else if(selected==null) {
                items(groups,key={it.id.name}) {summary ->
                    ListItem(modifier=Modifier.testTag("notification-group-${summary.id.name}").clickable(enabled=!busy) {
                        selected=summary.id.name;read(summary.rows.map {it.key}.toSet())
                    },headlineContent={Text(stringResource(summary.id.title()),style=MaterialTheme.typography.titleMedium)},
                        supportingContent={Text(summary.latest.title,maxLines=1)},
                        leadingContent={Icon(summary.id.icon(),null,Modifier.size(34.dp),tint=MaterialTheme.colorScheme.primary)},
                        trailingContent={if(summary.unreadCount>0) Badge {Text(if(summary.unreadCount>99) "99+" else summary.unreadCount.toString())}
                            else Text(localDate(summary.latest.createdAt),style=MaterialTheme.typography.labelSmall)})
                    HorizontalDivider(Modifier.padding(start=76.dp))
                }
            } else if(group!=null) {
                val days=group.rows.groupBy {Instant.parse(it.createdAt).atZone(ZoneId.systemDefault()).toLocalDate()}.toSortedMap(compareByDescending {it})
                days.forEach {(day,dayRows) ->
                    item(key="day-$day") {Text(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(day),Modifier.padding(16.dp),style=MaterialTheme.typography.labelLarge,color=MaterialTheme.colorScheme.onSurfaceVariant)}
                    items(dayRows.asReversed(),key={it.key}) {row ->
                        ListItem(modifier=Modifier.testTag("notification-${row.key}").clickable(enabled=!busy) {read(setOf(row.key));onOpenNotification(row)},
                            headlineContent={Text(row.title)},supportingContent={Column(verticalArrangement=Arrangement.spacedBy(4.dp)) {
                                Text(row.body);Text(localDate(row.createdAt),style=MaterialTheme.typography.labelSmall)
                                if(row.actionState!="resolved" && row.kind in setOf("billPaymentRequired","billOverdue","billAutoPaymentFailed"))
                                    Text(stringResource(if(row.kind=="billAutoPaymentFailed") R.string.notifications_notificationcenter_tap_to_add_funds_to_wallet
                                        else R.string.notifications_notificationcenter_tap_to_pay),color=MaterialTheme.colorScheme.primary,style=MaterialTheme.typography.labelMedium)
                            }},leadingContent={Icon(group.id.icon(),null,tint=MaterialTheme.colorScheme.primary)},
                            trailingContent={if(!row.isRead) Badge()})
                        HorizontalDivider(Modifier.padding(start=62.dp))
                    }
                }
            }
        }
    }
    }
    if(error) AlertDialog(onDismissRequest={error=false},title={Text(stringResource(R.string.common_error))},
        text={Text(stringResource(R.string.common_unknown_error))},confirmButton={TextButton(onClick={error=false}) {Text(stringResource(R.string.common_ok))}})
}
private fun localDate(value:String)=DateTimeFormatter.ofLocalizedDateTime(FormatStyle.SHORT).format(Instant.parse(value).atZone(ZoneId.systemDefault()))
private fun NotificationGroupId.title()=when(this) {
    NotificationGroupId.ACTION_REQUESTS -> R.string.notifications_notificationcenter_group_action_requests
    NotificationGroupId.ACCESS -> R.string.notifications_notificationcenter_group_access
    NotificationGroupId.FAMILY_CASHFLOW -> R.string.notifications_notificationcenter_group_family_cashflow
    NotificationGroupId.FAMILY_DATA -> R.string.notifications_notificationcenter_group_family_data
    NotificationGroupId.BILLS -> R.string.notifications_notificationcenter_group_bills
    NotificationGroupId.CREDIT_CARDS -> R.string.notifications_notificationcenter_group_credit_cards
    NotificationGroupId.WALLETS -> R.string.notifications_notificationcenter_group_wallets
    NotificationGroupId.BUDGETS -> R.string.notifications_notificationcenter_group_budgets
}
private fun NotificationGroupId.icon():ImageVector=when(this) {
    NotificationGroupId.ACTION_REQUESTS -> Icons.Default.Checklist
    NotificationGroupId.ACCESS -> Icons.Default.Lock
    NotificationGroupId.FAMILY_CASHFLOW -> Icons.Default.SwapHoriz
    NotificationGroupId.FAMILY_DATA -> Icons.Default.Groups
    NotificationGroupId.BILLS -> Icons.Default.EventNote
    NotificationGroupId.CREDIT_CARDS -> Icons.Default.CreditCard
    NotificationGroupId.WALLETS -> Icons.Default.AccountBalanceWallet
    NotificationGroupId.BUDGETS -> Icons.Default.PieChart
}
