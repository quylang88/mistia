package vn.com.quyln.mistia.feature.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotificationSettingsScreen(store:NotificationPreferencesStore,onBack:()->Unit,onRequestPermission:()->Unit) {
    val preferences by store.state.collectAsStateWithLifecycle()
    LaunchedEffect(preferences.enabled,preferences.reminders,preferences.details.isEmpty()) {
        if(preferences.enabled && preferences.reminders && preferences.details.isEmpty()) store.initializeDetails()
    }
    Scaffold(topBar={TopAppBar(title={Text(stringResource(R.string.settings_notifications_title))},
        navigationIcon={IconButton(onClick=onBack) {Icon(Icons.AutoMirrored.Filled.ArrowBack,stringResource(R.string.common_close))}})}) {padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding),contentPadding=PaddingValues(16.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
            item {
                Card {
                    SettingToggle("notifications-master",R.string.settings_notifications_enable_title,preferences.enabled,{
                        store.setMaster(it);if(it) onRequestPermission()
                    },{Icon(Icons.Default.NotificationsActive,null)})
                }
            }
            item {Text(stringResource(R.string.settings_notifications_enable_description),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
            if(preferences.enabled) {
                item {Text(stringResource(R.string.settings_notifications_reminders_title),style=MaterialTheme.typography.titleSmall)}
                item {Card {
                    ReminderKind.entries.forEachIndexed {index,kind ->
                        SettingToggle("notification-detail-${kind.name}",when(kind) {
                            ReminderKind.BUDGET -> R.string.settings_notifications_reminders_budget
                            ReminderKind.BILLS -> R.string.settings_notifications_reminders_bills
                            ReminderKind.CREDIT_CARDS -> R.string.settings_notifications_reminders_credit_cards
                            ReminderKind.WALLETS -> R.string.settings_notifications_reminders_wallets
                        },preferences.details[kind] ?: false,{store.setDetail(kind,it)}, {Icon(when(kind) {
                            ReminderKind.BUDGET -> Icons.Default.PieChart
                            ReminderKind.BILLS -> Icons.Default.EventNote
                            ReminderKind.CREDIT_CARDS -> Icons.Default.CreditCard
                            ReminderKind.WALLETS -> Icons.Default.AccountBalanceWallet
                        },null)})
                        if(index<ReminderKind.entries.lastIndex) HorizontalDivider(Modifier.padding(start=60.dp))
                    }
                }}
                item {Text(stringResource(R.string.settings_notifications_reminders_description),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
                item {Card {SettingToggle("notifications-family",R.string.settings_notifications_family_title,preferences.family,store::setFamily,{Icon(Icons.Default.Groups,null)})}}
                item {Text(stringResource(R.string.settings_notifications_family_description),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
            }
        }
    }
}
@Composable
private fun SettingToggle(tag:String,title:Int,value:Boolean,change:(Boolean)->Unit,icon:@Composable ()->Unit) {
    ListItem(modifier=Modifier.testTag(tag).toggleable(value=value,role=Role.Switch,onValueChange=change),
        headlineContent={Text(stringResource(title))},leadingContent=icon,trailingContent={Switch(checked=value,onCheckedChange=null)})
}
