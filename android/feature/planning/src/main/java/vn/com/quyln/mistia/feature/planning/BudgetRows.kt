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
import vn.com.quyln.mistia.core.designsystem.*
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@Composable
internal fun BudgetBranchCard(branch: BudgetBranchRow, onEdit: (String?) -> Unit) {
    MistiaGlassCard { padding ->
        Column(Modifier.padding(padding), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            BudgetAmountRow(branch.name, branch.icon, branch.colorHex, branch.spentMinor, branch.limitMinor, branch.currencyCode, branch.pace, branch.primaryBudgetId) { onEdit(branch.primaryBudgetId) }
            if(branch.children.isNotEmpty()) Text(stringResource(R.string.planning_planning_child_budgets),style=MaterialTheme.typography.labelLarge)
            branch.children.forEach { child ->
                HorizontalDivider()
                Box(Modifier.padding(start = 20.dp)) {
                    BudgetAmountRow(child.name, child.icon, child.colorHex, child.spentMinor, child.plan.limitMinor, child.plan.currencyCode, child.pace, child.plan.id) { onEdit(child.plan.id) }
                }
            }
        }
    }
}

@Composable
private fun BudgetAmountRow(name: String, icon: String, colorHex: String, spent: Long, limit: Long, currency: String, pace: BudgetPace, budgetId: String?, onClick: () -> Unit) {
    Column(Modifier.testTag("budget.edit.$budgetId").fillMaxWidth().then(if(budgetId==null) Modifier else Modifier.clickable(onClick=onClick)), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CategoryIcon(icon, TransactionCategoryKind.EXPENSE, colorHex, Modifier.size(40.dp))
            Column(Modifier.weight(1f)) {
                Text(name, style = MaterialTheme.typography.titleSmall)
                Text("${formatMinorUnits(spent,currency)} / ${formatMinorUnits(limit,currency)}", style = MaterialTheme.typography.bodySmall)
            }
        }
        val color = when (pace.health) {
            BudgetHealth.STABLE -> categoryColorFromHex("#2DAA9E")
            BudgetHealth.CAUTION -> categoryColorFromHex("#F59B3F")
            BudgetHealth.EXCEEDED -> categoryColorFromHex("#F45C7E")
        }
        val progress = if (limit > 0) (spent.toBigDecimal().divide(limit.toBigDecimal(), 6, java.math.RoundingMode.HALF_UP).toFloat()).coerceIn(0f,1f) else 0f
        LinearProgressIndicator(progress = { progress }, color = color, modifier = Modifier.fillMaxWidth())
        Text(if(pace.isPastMonth) stringResource(R.string.planning_planning_month_ended) else stringResource(R.string.planning_planning_value_days_left,pace.daysRemaining.toString()),
            style=MaterialTheme.typography.labelSmall)
        Text(stringResource(when (pace.health) {
            BudgetHealth.STABLE -> R.string.shared_corelogic_planning_stable
            BudgetHealth.CAUTION -> R.string.shared_corelogic_planning_needs_attention
            BudgetHealth.EXCEEDED -> R.string.shared_corelogic_planning_exceeded
        }), color = color, style = MaterialTheme.typography.labelSmall)
    }
}
