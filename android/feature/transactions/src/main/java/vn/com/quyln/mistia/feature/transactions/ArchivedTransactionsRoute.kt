package vn.com.quyln.mistia.feature.transactions

import androidx.compose.runtime.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.BasicText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.graphics.Color
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.combine
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.designsystem.MistiaGlassCard
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.designsystem.FinanceIcon
import vn.com.quyln.mistia.core.model.*

@Composable fun ArchivedTransactionsRoute(owner:UserId,repository:FinanceRepository,receiptImages:TransactionReceiptImageRepository,
    deviceIdProvider:suspend ()->String,primaryCurrencyCode:String="JPY",onDismiss:()->Unit) {
    Surface(Modifier.fillMaxSize(),color=MaterialTheme.colorScheme.background,contentColor=MaterialTheme.colorScheme.onBackground) {
        key(owner.value,repository,receiptImages) {OwnedArchivedTransactions(owner,repository,receiptImages,deviceIdProvider,primaryCurrencyCode,onDismiss)}
    }
}

private sealed interface ArchiveLoad {
    data object Loading:ArchiveLoad
    data object Failed:ArchiveLoad
    data class Ready(val rows:List<LedgerTransactionRecord>,val wallets:List<LedgerWalletRecord>,val categories:List<TransactionCategoryRecord>):ArchiveLoad
}
private data class ArchiveAction(val record:LedgerTransactionRecord,val action:TransactionLifecycleAction)

@Composable private fun OwnedArchivedTransactions(owner:UserId,repository:FinanceRepository,receipts:TransactionReceiptImageRepository,
    deviceIdProvider:suspend ()->String,primaryCurrencyCode:String,onDismiss:()->Unit) {
    var retry by remember{mutableIntStateOf(0)}
    val locale=LocalConfiguration.current.locales[0]
    var selected by remember{mutableStateOf<ArchiveAction?>(null)}
    val load by produceState<ArchiveLoad>(ArchiveLoad.Loading,retry) {
        value=ArchiveLoad.Loading
        try {
            combine(repository.observe(CloudEntity.LEDGER_TRANSACTION,owner),repository.observeWallets(owner),repository.observeCategories(owner)){rows,wallets,categories->
                val archived=rows.filter{it.ownerUserId==owner.value}.mapNotNull{raw->
                    val deleted=raw.financeRawDeleted(true);val hidden=raw.payload.financeRawArchived()
                    require(deleted!=null && hidden!=null){"Unreadable archive state"}
                    if(deleted || !hidden)return@mapNotNull null
                    require(raw.financeRawIdentity(owner,CloudEntity.LEDGER_TRANSACTION,true))
                    require(raw.payload.financeRawLong("amount_minor")!=null)
                    java.time.Instant.parse(raw.payload.financeRawString("occurred_at"))
                    LedgerTransactionRecord.fromCloudRecord(raw).takeIf{it.supportsOrdinaryTransactionLifecycle()}
                }.sortedByDescending{java.time.Instant.parse(it.occurredAt)}
                ArchiveLoad.Ready(archived,wallets.filter{it.ownerUserId==owner.value},categories.filter{it.ownerUserId==owner.value})
            }.collect{value=it}
        } catch(cancelled:CancellationException){throw cancelled}
          catch(_:Exception){value=ArchiveLoad.Failed}
    }
    val ready=load as? ArchiveLoad.Ready
    Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).padding(horizontal=16.dp,vertical=18.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.management_managementarchiveditems_archived_items),Modifier.testTag("transaction.archived.heading"),style=MaterialTheme.typography.headlineSmall)
                Text(stringResource(R.string.management_managementarchiveditems_transactions),style=MaterialTheme.typography.labelLarge)
            }
            TextButton(onClick=onDismiss,modifier=Modifier.heightIn(min=48.dp)){Text(stringResource(R.string.common_close))}
        }
        when(load) {
            ArchiveLoad.Loading->{CircularProgressIndicator();Text(stringResource(R.string.transactions_stored_editor_loading),Modifier.testTag("transaction.archived.loading"))}
            ArchiveLoad.Failed->{Text(stringResource(R.string.transactions_stored_editor_unavailable),Modifier.testTag("transaction.archived.error"));TextButton(onClick={retry++},modifier=Modifier.heightIn(min=48.dp).testTag("transaction.archived.retry")){Text(stringResource(R.string.planning_installment_retry))}}
            is ArchiveLoad.Ready->if(ready!!.rows.isEmpty())Text(stringResource(R.string.management_managementarchiveditems_no_archived_items),Modifier.testTag("transaction.archived.empty"))
            else LazyColumn(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(12.dp),contentPadding=PaddingValues(bottom=24.dp)) {
                items(ready.rows,key={it.id}){row->
                    MistiaGlassCard {padding->Column(Modifier.fillMaxWidth().padding(padding).testTag("transaction.archived.row."+row.id),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                        val category=ready.categories.firstOrNull{it.id==row.categoryId}
                        Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(10.dp)) {
                            FinanceIcon(category?.iconSymbolName ?: when(row.primaryKind){
                                TransactionPrimaryKind.EXPENSE->"mistia.flow.expense"
                                TransactionPrimaryKind.INCOME->"mistia.flow.income"
                                else->if(row.transferSubtype==TransactionTransferSubtype.DEBT)"mistia.debt.lend"else "mistia.flow.transfer.internal"
                            },Modifier.size(34.dp))
                            Column(Modifier.weight(1f)) {
                                Text(row.title,Modifier.testTag("transaction.archived.name."+row.id),style=MaterialTheme.typography.titleMedium)
                                val source=ready.wallets.firstOrNull{it.id==row.sourceWalletId}?.name ?: stringResource(R.string.management_managementarchiveditems_no_wallet_selected)
                                val categoryTitle=when(locale.language){"ja"->category?.nameJapanese;"vi"->category?.name;else->category?.nameEnglish}?.takeIf{it.isNotBlank()} ?: category?.name
                                val subtitle=if(row.transferSubtype==TransactionTransferSubtype.INTERNAL_TRANSFER)source+" → "+(ready.wallets.firstOrNull{it.id==row.destinationWalletId}?.name ?: stringResource(R.string.management_managementarchiveditems_destination))
                                    else source+" • "+(categoryTitle ?: row.counterpartyName ?: stringResource(R.string.management_managementarchiveditems_no_category_selected))
                                Text(subtitle,Modifier.testTag("transaction.archived.subtitle."+row.id),style=MaterialTheme.typography.bodySmall)
                            }
                        }
                        val sign=when(row.primaryKind){TransactionPrimaryKind.EXPENSE->"−";TransactionPrimaryKind.INCOME->"+";else->if(row.transferSubtype==TransactionTransferSubtype.DEBT)"−"else ""}
                        ArchivedMoneyText(sign+formatMinorUnits(row.amountMinor,row.sourceCurrencyCode ?: ready.wallets.firstOrNull{it.id==row.sourceWalletId}?.currencyCode ?: primaryCurrencyCode),"transaction.archived.amount."+row.id,
                            when(sign){"−"->MaterialTheme.colorScheme.error;"+"->vn.com.quyln.mistia.core.designsystem.categoryColorFromHex("#2DAA9E");else->MaterialTheme.colorScheme.onSurface})
                        val date=java.time.Instant.parse(row.occurredAt).atZone(java.time.ZoneId.systemDefault()).format(java.time.format.DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.MEDIUM).withLocale(locale))
                        Text(date,style=MaterialTheme.typography.bodySmall)
                        TextButton(onClick={selected=ArchiveAction(row,TransactionLifecycleAction.RESTORE)},modifier=Modifier.fillMaxWidth().heightIn(min=48.dp).testTag("transaction.archived.restore."+row.id)){Text(stringResource(R.string.management_managementarchiveditems_restore),Modifier.testTag("transaction.archived.restore.text."+row.id))}
                        TextButton(onClick={selected=ArchiveAction(row,TransactionLifecycleAction.DELETE)},modifier=Modifier.fillMaxWidth().heightIn(min=48.dp).testTag("transaction.archived.delete."+row.id)){Text(stringResource(R.string.management_managementarchiveditems_delete_permanently),Modifier.testTag("transaction.archived.delete.text."+row.id),color=MaterialTheme.colorScheme.error)}
                    }}
                }
            }
        }
    }
    selected?.let{choice->TransactionLifecycleActionDialog(owner,choice.record,choice.action,repository,receipts,ready?.wallets.orEmpty(),deviceIdProvider,primaryCurrencyCode,
        onDone={selected=null},onDismiss={selected=null})}
}

@Composable private fun ArchivedMoneyText(value:String,tag:String,color:Color) {
    val measurer=rememberTextMeasurer()
    val style=MaterialTheme.typography.bodyLarge.copy(color=color)
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        var size=style.fontSize.value
        while(size>12f && measurer.measure(value,style.copy(fontSize=size.sp)).size.width>constraints.maxWidth)size-=0.5f
        BasicText(value,Modifier.fillMaxWidth().testTag(tag),style=style.copy(fontSize=size.sp))
    }
}
