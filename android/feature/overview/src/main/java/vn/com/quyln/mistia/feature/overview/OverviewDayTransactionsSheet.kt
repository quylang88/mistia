package vn.com.quyln.mistia.feature.overview

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import vn.com.quyln.mistia.core.designsystem.*
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun OverviewDayTransactionsSheet(day:OverviewExpenseDay,wallets:Map<String,LedgerWalletRecord>,categories:Map<String,TransactionCategoryRecord>,zone:ZoneId,
    onDismiss:()->Unit,onSelect:(String)->Unit) {
    val locale=LocalConfiguration.current.locales[0]
    val configuration=LocalConfiguration.current
    val context=androidx.compose.ui.platform.LocalContext.current
    val density=androidx.compose.ui.platform.LocalDensity.current
    val height=LocalConfiguration.current.screenHeightDp.dp
    val expense=Color(0.96f,0.36f,0.49f)
    ModalBottomSheet(onDismissRequest=onDismiss,sheetState=rememberModalBottomSheetState(skipPartiallyExpanded=false),dragHandle=null,
        modifier=Modifier.testTag("overview.day.sheet"),containerColor=MaterialTheme.colorScheme.surfaceContainerLow) {
        // The sheet window supplies its own Android resources; retain the parent's app language.
        CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context,
            LocalConfiguration provides configuration,androidx.compose.ui.platform.LocalResources provides context.resources,
            androidx.compose.ui.platform.LocalDensity provides density) {
        Column(Modifier.fillMaxWidth().heightIn(min=height*0.5f,max=height*0.9f)) {
            Row(Modifier.fillMaxWidth().padding(horizontal=8.dp,vertical=4.dp),verticalAlignment=Alignment.CenterVertically) {
                IconButton(onClick=onDismiss) {Icon(Icons.Default.Close,stringResource(R.string.common_close))}
                Text(stringResource(R.string.overview_overview_day_details),fontWeight=FontWeight.SemiBold,fontSize=17.sp)
            }
            Column(Modifier.weight(1f,fill=false).verticalScroll(rememberScrollState()).padding(horizontal=18.dp).padding(bottom=28.dp),verticalArrangement=Arrangement.spacedBy(18.dp)) {
                MistiaGlassCard {padding ->
                    Column(Modifier.fillMaxWidth().padding(padding),verticalArrangement=Arrangement.spacedBy(16.dp)) {
                        Text(stringResource(R.string.overview_overview_daily_expenses),fontSize=13.sp,fontWeight=FontWeight.Bold,color=MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(day.day.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL).withLocale(locale)),Modifier.testTag("overview.day.date"),
                            style=TextStyle(fontSize=28.sp,fontWeight=FontWeight.Bold,color=MaterialTheme.colorScheme.onSurface))
                        FlowRow(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,verticalArrangement=Arrangement.spacedBy(12.dp)) {
                            Column(Modifier.widthIn(min=160.dp),verticalArrangement=Arrangement.spacedBy(4.dp)) {
                                Text(stringResource(R.string.overview_overview_total_spent),fontSize=11.sp,fontWeight=FontWeight.SemiBold,color=MaterialTheme.colorScheme.onSurfaceVariant)
                                BasicText(day.totalMinor?.let {formatMinorUnits(it,day.currencyCode)} ?: "—",Modifier.testTag("overview.day.total"),
                                    style=TextStyle(fontSize=16.sp,fontWeight=FontWeight.Bold,color=expense),maxLines=1,softWrap=false,
                                    autoSize=TextAutoSize.StepBased(minFontSize=10.sp,maxFontSize=16.sp,stepSize=0.5.sp))
                            }
                            Column(verticalArrangement=Arrangement.spacedBy(4.dp)) {
                                Text(stringResource(R.string.overview_overview_transactions),fontSize=11.sp,fontWeight=FontWeight.SemiBold,color=MaterialTheme.colorScheme.onSurfaceVariant)
                                Text(day.rows.size.toString(),Modifier.testTag("overview.day.count"),fontSize=16.sp,fontWeight=FontWeight.Bold)
                            }
                        }
                    }
                }
                if(day.rows.isEmpty()) Text(stringResource(R.string.transactions_transactions_no_transactions_yet),color=MaterialTheme.colorScheme.onSurfaceVariant)
                else MistiaGlassCard {padding ->
                    Column(Modifier.fillMaxWidth().padding(padding)) {
                        day.rows.forEachIndexed {index,row ->
                            val record=row.transaction
                            val category=categories[record.categoryId]?.takeIf {it.ownerUserId==record.ownerUserId && it.id==record.categoryId}
                            val wallet=wallets[record.sourceWalletId]?.takeIf {it.ownerUserId==record.ownerUserId && it.id==record.sourceWalletId}
                            val categoryName=category?.let {when(locale.language) {"en" -> it.nameEnglish;"ja" -> it.nameJapanese;else -> it.name}?.takeIf(String::isNotBlank) ?: it.name}
                            val title=localizedTransactionTitle(record,category).trim().ifBlank {categoryName ?: stringResource(R.string.overview_overview_expense)}
                            val walletName=wallet?.name ?: stringResource(R.string.overview_overview_no_wallet_selected)
                            val time=Instant.parse(record.occurredAt).atZone(zone).format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale))
                            val subtitle=listOfNotNull(time,walletName,categoryName?.takeIf {it!=title}).joinToString(" • ")
                            Column(Modifier.fillMaxWidth().testTag("overview.day.row.${record.id}").clickable {onSelect(record.id)}.padding(vertical=12.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                                Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                                    CategoryIcon(category?.iconSymbolName ?: "mistia.flow.expense",category?.kind,"#F45C7E",Modifier.size(34.dp))
                                    Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(4.dp)) {
                                        Text(title,fontSize=16.sp,fontWeight=FontWeight.SemiBold,maxLines=1,overflow=TextOverflow.Ellipsis)
                                        Text(subtitle,fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=2,overflow=TextOverflow.Ellipsis)
                                    }
                                }
                                BasicText((if(row.money.minor<0) "+" else "-")+formatMinorUnitsMagnitude(row.money.minor,row.money.currencyCode),Modifier.fillMaxWidth().testTag("overview.day.amount.${record.id}"),
                                    style=TextStyle(fontSize=15.sp,fontWeight=FontWeight.Bold,color=expense,textAlign=TextAlign.End),maxLines=1,softWrap=false,
                                    autoSize=TextAutoSize.StepBased(minFontSize=10.sp,maxFontSize=15.sp,stepSize=0.5.sp))
                            }
                            if(index<day.rows.lastIndex) HorizontalDivider()
                        }
                    }
                }
            }
        }
        }
    }
}
