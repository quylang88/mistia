package vn.com.quyln.mistia.feature.transactions

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import vn.com.quyln.mistia.core.designsystem.R

@Composable
internal fun ReceiptPhotoPickerButton(
    existingImageCount: Int,
    onResult: (ReceiptPhotoSelectionResult) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val context = LocalContext.current
    val preparer = remember(context) { AndroidReceiptImagePreparer(context.contentResolver) }
    val scope = rememberCoroutineScope()
    val latestExistingImageCount by rememberUpdatedState(existingImageCount)
    val latestOnResult by rememberUpdatedState(onResult)
    var isPreparing by remember { mutableStateOf(false) }

    val handleSelection: (List<Uri>) -> Unit = { uris ->
        if (uris.isNotEmpty() && !isPreparing) {
            val availableSlots = (
                ReceiptPhotoPickerLimits.MAX_IMAGES - latestExistingImageCount.coerceAtLeast(0)
            ).coerceAtLeast(0)
            scope.launch {
                isPreparing = true
                try {
                    latestOnResult(
                        prepareReceiptPhotoSelections(uris, availableSlots, preparer::prepare),
                    )
                } finally {
                    isPreparing = false
                }
            }
        }
    }
    val latestHandleSelection by rememberUpdatedState(handleSelection)
    val pickerMode = receiptPhotoPickerMode(existingImageCount)
    val multipleMaxItems = (pickerMode as? ReceiptPhotoPickerMode.Multiple)?.maxItems ?: 2
    val singlePicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia(),
    ) { uri ->
        uri?.let { latestHandleSelection(listOf(it)) }
    }
    val multiplePicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickMultipleVisualMedia(multipleMaxItems),
    ) { uris ->
        latestHandleSelection(uris)
    }

    OutlinedButton(
        modifier = modifier,
        enabled = enabled && !isPreparing && pickerMode != ReceiptPhotoPickerMode.None,
        onClick = {
            val request = PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
            when (pickerMode) {
                ReceiptPhotoPickerMode.None -> Unit
                ReceiptPhotoPickerMode.Single -> singlePicker.launch(request)
                is ReceiptPhotoPickerMode.Multiple -> multiplePicker.launch(request)
            }
        },
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (isPreparing) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    strokeWidth = 2.dp,
                )
            }
            Text(stringResource(R.string.transactions_aibill_add_bills))
        }
    }
}
