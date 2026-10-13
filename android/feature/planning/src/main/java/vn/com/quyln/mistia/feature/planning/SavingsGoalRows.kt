package vn.com.quyln.mistia.feature.planning

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.style.TextAlign
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import vn.com.quyln.mistia.core.designsystem.MistiaSectionCard
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

internal fun LazyListScope.savingsGoalContent(rows:List<SavingsGoalRow>,summary:SavingsGoalSummary,onAdd:()->Unit,onEdit:(SavingsGoalRecord)->Unit) {
    item {
        MistiaSectionCard(stringResource(R.string.planning_planning_goals2)) {
            Text("${stringResource(R.string.planning_planning_active_goals)}: ${summary.activeCount}")
            Text("${stringResource(R.string.planning_planning_saved)}: ${formatMinorUnits(summary.totalSavedMinor,"JPY")}",style=MaterialTheme.typography.headlineSmall)
            summary.nearestGoalName?.let { Text("${stringResource(R.string.planning_planning_closest_to_goal)}: $it") }
        }
    }
    if(rows.isEmpty()) item { MistiaSectionCard(stringResource(R.string.planning_planning_no_goals_yet)) {
        Text(stringResource(R.string.planning_planning_add_an_emergency_fund_trip_or_big))
    } }
    items(rows,key={it.goal.id}) { row -> SavingsGoalCard(row) {onEdit(row.goal)} }
    item { Button(onClick=onAdd,modifier=Modifier.fillMaxWidth().testTag("goal.add")) {Text(stringResource(R.string.planning_planning_add_goal))} }
}

@Composable private fun SavingsGoalCard(row:SavingsGoalRow,onClick:()->Unit) {
    val goal=row.goal
    Surface(Modifier.fillMaxWidth().testTag("goal.edit.${goal.id}").clickable(onClick=onClick),shape=MaterialTheme.shapes.large,tonalElevation=1.dp) {
        Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                SavingsGoalIcon(goal.iconSymbolName)
                Column {Text(goal.name,style=MaterialTheme.typography.titleMedium);Text("${formatMinorUnits(goal.currentSavedMinor,goal.currencyCode)} / ${formatMinorUnits(goal.targetMinor,goal.currencyCode)}",style=MaterialTheme.typography.bodySmall)}
            }
            val progress=if(goal.targetMinor>0) (goal.currentSavedMinor.toDouble()/goal.targetMinor.toDouble()).coerceIn(0.0,1.0).toFloat() else 0f
            LinearProgressIndicator(progress={progress},modifier=Modifier.fillMaxWidth(),color=Color(0xFF2DAA9E))
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {
                Text(Instant.parse(goal.targetDate).atZone(ZoneId.systemDefault()).toLocalDate().format(DateTimeFormatter.ofLocalizedDate(FormatStyle.SHORT)),style=MaterialTheme.typography.bodySmall,modifier=Modifier.weight(1f))
                Text(stringResource(R.string.planning_planning_need_value_month,formatMinorUnits(row.monthlyRequiredMinor,goal.currencyCode)),style=MaterialTheme.typography.bodySmall,color=Color(0xFF5B7BFF),textAlign=TextAlign.End,modifier=Modifier.weight(1f))
            }
        }
    }
}
