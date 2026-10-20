package vn.com.quyln.mistia.feature.planning

import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.sp
import java.math.BigInteger
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.designsystem.R

internal fun budgetReadMoney(amount:BigInteger?,code:String?):String =
    if(amount==null || code==null) "\u2014" else formatMinorUnits(amount,code)

@Composable internal fun BudgetSummaryMoney(amount:BigInteger?,code:String,tag:String,label:String?=null,large:Boolean=false) {
    val hint=stringResource(R.string.overview_overview_reporting_amount_unavailable)
    val text=(label?.let {"$it: "} ?: "")+budgetReadMoney(amount,code)
    BasicText(text,Modifier.testTag(tag).semantics {if(amount==null) stateDescription=hint},
        style=(if(large) MaterialTheme.typography.headlineSmall else MaterialTheme.typography.bodyLarge).copy(color=MaterialTheme.colorScheme.onSurface),
        maxLines=1,softWrap=false,autoSize=TextAutoSize.StepBased(minFontSize=10.sp,maxFontSize=if(large) 24.sp else 16.sp,stepSize=0.5.sp))
}
