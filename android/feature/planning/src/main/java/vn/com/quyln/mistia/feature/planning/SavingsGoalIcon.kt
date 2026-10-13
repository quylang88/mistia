package vn.com.quyln.mistia.feature.planning

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.categoryColorFromHex

internal val goalIcons=listOf(
    Triple("mistia.goal.savings",R.string.core_ui_mistiafinanceicons_savings,"#2DAA9E"),
    Triple("mistia.goal.travel",R.string.core_ui_mistiafinanceicons_travel,"#5B7BFF"),
    Triple("mistia.goal.home",R.string.core_ui_mistiafinanceicons_home,"#FF8A4C"),
    Triple("mistia.goal.education",R.string.core_ui_mistiafinanceicons_study,"#A76BFF"),
    Triple("mistia.goal.vehicle",R.string.core_ui_mistiafinanceicons_vehicle,"#2DAA9E"),
    Triple("mistia.goal.family",R.string.core_ui_mistiafinanceicons_family,"#FF6D8A"),
)

@Composable internal fun SavingsGoalIcon(symbol:String,modifier:Modifier=Modifier) {
    val color=categoryColorFromHex(goalIcons.firstOrNull { it.first==symbol }?.third ?: "#2DAA9E")
    val icon=when(symbol) {
        "mistia.goal.travel","airplane" -> Icons.Default.Flight
        "mistia.goal.home","house.fill" -> Icons.Default.Home
        "mistia.goal.education","graduationcap.fill" -> Icons.Default.School
        "mistia.goal.vehicle","car.fill" -> Icons.Default.DirectionsCar
        "mistia.goal.family","person.2.fill" -> Icons.Default.Groups
        "shield.fill" -> Icons.Default.Shield
        "laptopcomputer" -> Icons.Default.Laptop
        else -> Icons.Default.GpsFixed
    }
    Box(modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(color.copy(alpha=0.18f)),contentAlignment=Alignment.Center) {
        Icon(icon,contentDescription=null,tint=color,modifier=Modifier.size(26.dp))
    }
}
