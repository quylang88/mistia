package vn.com.quyln.mistia.feature.planning

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import java.math.BigInteger
import java.math.BigDecimal
import vn.com.quyln.mistia.core.designsystem.*
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@Composable
internal fun BudgetBranchCard(branch: BudgetBranchRow, onEdit: (String?) -> Unit) {
    MistiaGlassCard { padding ->
        Column(Modifier.padding(padding), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            BudgetAmountRow(branch.name, branch.icon, branch.colorHex, branch.spentMinor, branch.limitMinor, branch.currencyCode, branch.pace, branch.primaryBudgetId,"branch-${branch.id}") { onEdit(branch.primaryBudgetId) }
            if(branch.children.isNotEmpty()) Text(stringResource(R.string.planning_planning_child_budgets),style=MaterialTheme.typography.labelLarge)
            branch.children.forEach { child ->
                HorizontalDivider()
                Box(Modifier.padding(start = 20.dp)) {
                    BudgetAmountRow(child.name, child.icon, child.colorHex, child.spentMinor, child.limitMinor, child.currencyCode, child.pace, child.plan.id,"budget-${child.plan.id}") { onEdit(child.plan.id) }
                }
            }
        }
    }
}

@Composable
private fun BudgetAmountRow(name: String, icon: String, colorHex: String, spent: BigInteger?, limit: BigInteger?, currency: String?, pace: BudgetPace, budgetId: String?,readKey:String, onClick: () -> Unit) {
    val unavailable=stringResource(R.string.overview_overview_reporting_amount_unavailable)
    val known=spent!=null && limit!=null && currency!=null && pace.health!=null
    Column(Modifier.testTag("budget.edit.$budgetId").fillMaxWidth().then(if(budgetId==null) Modifier else Modifier.clickable(onClick=onClick)), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CategoryIcon(icon, TransactionCategoryKind.EXPENSE, colorHex, Modifier.size(40.dp))
            Column(Modifier.weight(1f)) {
                Text(name, style = MaterialTheme.typography.titleSmall)
                Text("${budgetReadMoney(spent,currency)} / ${budgetReadMoney(limit,currency)}",Modifier.testTag("budget.money.$readKey").semantics {if(!known) stateDescription=unavailable},style=MaterialTheme.typography.bodySmall)
            }
        }
        val color = when (pace.health) {
            BudgetHealth.STABLE -> categoryColorFromHex("#2DAA9E")
            BudgetHealth.CAUTION -> categoryColorFromHex("#F59B3F")
            BudgetHealth.EXCEEDED -> categoryColorFromHex("#F45C7E")
            null -> MaterialTheme.colorScheme.onSurfaceVariant
        }
        if(known) {
            val progress=if(limit!!.signum()>0) BigDecimal(spent!!).divide(BigDecimal(limit),24,java.math.RoundingMode.HALF_UP).max(BigDecimal.ZERO).min(BigDecimal.ONE).toFloat() else 0f
            LinearProgressIndicator(progress={progress},color=color,modifier=Modifier.fillMaxWidth().testTag("budget.progress.$readKey"))
        }
        Text(if(pace.isPastMonth) stringResource(R.string.planning_planning_month_ended) else stringResource(R.string.planning_planning_value_days_left,pace.daysRemaining.toString()),
            style=MaterialTheme.typography.labelSmall)
        if(!known) Text(unavailable,Modifier.testTag("budget.unavailable.$readKey"),color=color,style=MaterialTheme.typography.labelSmall)
        else Text(stringResource(when (pace.health) {
            BudgetHealth.STABLE -> R.string.shared_corelogic_planning_stable
            BudgetHealth.CAUTION -> R.string.shared_corelogic_planning_needs_attention
            BudgetHealth.EXCEEDED -> R.string.shared_corelogic_planning_exceeded
            null -> R.string.overview_overview_reporting_amount_unavailable
        }), color = color, style = MaterialTheme.typography.labelSmall)
    }
}
