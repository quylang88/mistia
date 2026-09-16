package vn.com.quyln.mistia.feature.planning

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import vn.com.quyln.mistia.core.designsystem.MistiaSectionCard
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.FinanceRepository
import vn.com.quyln.mistia.core.model.UserId

@Composable
fun PlanningScreen(
    ownerUserId: UserId,
    repository: FinanceRepository,
    modifier: Modifier = Modifier,
) {
    val counts by repository.observeEntityCounts(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val values = counts.associate { it.entity to it.count }
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Text(stringResource(R.string.planning_planning_planning), style = MaterialTheme.typography.headlineMedium)
        }
        item {
            PlanningCountCard(stringResource(R.string.planning_planning_budgets), values[CloudEntity.BUDGET_PLAN.table] ?: 0)
        }
        item {
            PlanningCountCard(stringResource(R.string.planning_planning_goals2), values[CloudEntity.SAVINGS_GOAL.table] ?: 0)
        }
        item {
            PlanningCountCard(stringResource(R.string.planning_planning_bills2), values[CloudEntity.RECURRING_BILL_PLAN.table] ?: 0)
        }
        item {
            PlanningCountCard(stringResource(R.string.planning_planning_installments_loans2), values[CloudEntity.INSTALLMENT_PLAN.table] ?: 0)
        }
    }
}

@Composable
private fun PlanningCountCard(title: String, count: Int) {
    MistiaSectionCard(title = title) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            horizontalArrangement = Arrangement.End,
        ) {
            Text(count.toString(), style = MaterialTheme.typography.headlineSmall)
        }
    }
}
