package vn.com.quyln.mistia.feature.transactions

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import vn.com.quyln.mistia.core.designsystem.R

/** Keep both actions usable and the heading readable at narrow widths or enlarged system text. */
@Composable internal fun TransactionEditorHeading(title:String,isSaving:Boolean,onDismiss:()->Unit,onSave:()->Unit) {
    val cancel:@Composable ()->Unit = {
        TextButton(onClick=onDismiss,enabled=!isSaving,modifier=Modifier.heightIn(min=48.dp).testTag("transaction.cancel")) {
            Text(stringResource(R.string.common_cancel))
        }
    }
    val save:@Composable ()->Unit = {
        Button(onClick=onSave,enabled=!isSaving,modifier=Modifier.heightIn(min=48.dp).testTag("transaction.save")) {
            Text(stringResource(R.string.common_save))
        }
    }
    val heading:@Composable (Modifier)->Unit = {modifier->
        Text(title,modifier.testTag("transaction.heading"),textAlign=TextAlign.Center,style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.SemiBold)
    }
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        if(maxWidth<320.dp || LocalDensity.current.fontScale>=1.2f) {
            Column(Modifier.fillMaxWidth(),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.CenterVertically){cancel();save()}
                heading(Modifier.fillMaxWidth())
            }
        } else {
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.CenterVertically) {
                cancel();heading(Modifier.weight(1f).padding(horizontal=8.dp));save()
            }
        }
    }
}
