package vn.com.quyln.mistia.feature.overview

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.com.quyln.mistia.core.designsystem.*
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@Composable internal fun OverviewMonthlyMetrics(month:OverviewMonthlyCashflow,currency:String) {
    val code=currency.trim().uppercase(java.util.Locale.ROOT).takeIf {it in CurrencyPreferences.supportedCurrencyCodes} ?: "JPY"
    MistiaGlassCard {padding ->
        FlowRow(Modifier.padding(padding).fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(14.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
            for((kind,amount) in listOf("income" to month.incomeMinor,"expense" to month.expenseMinor)) {
                Column(Modifier.widthIn(min=140.dp),verticalArrangement=Arrangement.spacedBy(6.dp)) {
                    Text(stringResource(if(kind=="income") R.string.overview_overview_income_this_month else R.string.overview_overview_expense_this_month),
                        fontSize=13.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(formatMinorUnits(amount,code),Modifier.testTag("overview.monthly.$kind"),fontSize=18.sp,fontWeight=FontWeight.Bold,
                        color=if(kind=="income") Color(0xFF2DAA9E) else Color(0xFFF45C7E),maxLines=1,softWrap=false)
                }
            }
        }
    }
}
