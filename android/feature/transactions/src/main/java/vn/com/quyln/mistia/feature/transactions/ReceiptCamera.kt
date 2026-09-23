package vn.com.quyln.mistia.feature.transactions

import android.Manifest
import android.annotation.SuppressLint
import android.content.pm.PackageManager
import android.net.Uri
import android.view.Surface
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import java.io.File
import kotlinx.coroutines.launch
import vn.com.quyln.mistia.core.designsystem.R

@Composable
internal fun ReceiptCameraButton(
    existingImageCount: Int,
    onResult: (ReceiptPhotoSelectionResult) -> Unit,
    onFailure: (ReceiptCameraFailure) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val context = LocalContext.current
    val latestOnFailure by rememberUpdatedState(onFailure)
    var cameraOpen by remember { mutableStateOf(false) }
    val cameraAvailable = remember(context) {
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
    }
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) cameraOpen = true else latestOnFailure(ReceiptCameraFailure.PermissionDenied)
    }
    val hasCapacity = existingImageCount < ReceiptPhotoPickerLimits.MAX_IMAGES

    OutlinedButton(
        modifier = modifier,
        enabled = enabled && hasCapacity,
        onClick = {
            val hasPermission = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.CAMERA,
            ) == PackageManager.PERMISSION_GRANTED
            when (receiptCameraEntryAction(hasPermission, cameraAvailable)) {
                ReceiptCameraEntryAction.Unavailable -> {
                    latestOnFailure(ReceiptCameraFailure.Unavailable)
                }
                ReceiptCameraEntryAction.RequestPermission -> {
                    permissionLauncher.launch(Manifest.permission.CAMERA)
                }
                ReceiptCameraEntryAction.OpenCamera -> cameraOpen = true
            }
        },
    ) {
        Text(stringResource(R.string.transactions_transactioneditor_take_photo))
    }

    if (cameraOpen) {
        ReceiptCameraSheet(
            onDismiss = { cameraOpen = false },
            onResult = onResult,
            onFailure = onFailure,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReceiptCameraSheet(
    onDismiss: () -> Unit,
    onResult: (ReceiptPhotoSelectionResult) -> Unit,
    onFailure: (ReceiptCameraFailure) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val preparer = remember(context) { AndroidReceiptImagePreparer(context.contentResolver) }
    val activeCaptureFile = remember { mutableStateOf<File?>(null) }
    val imageCapture = remember {
        ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
            .build()
    }
    var isBusy by remember { mutableStateOf(false) }

    DisposableEffect(Unit) {
        onDispose { activeCaptureFile.value?.delete() }
    }

    ModalBottomSheet(onDismissRequest = { if (!isBusy) onDismiss() }) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onDismiss, enabled = !isBusy) {
                    Text(stringResource(R.string.common_cancel))
                }
                Text(
                    text = stringResource(R.string.transactions_aibill_receipt_image),
                    style = MaterialTheme.typography.titleLarge,
                )
            }

            ReceiptCameraPreview(
                imageCapture = imageCapture,
                onFailure = { failure ->
                    onFailure(failure)
                    onDismiss()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(3f / 4f)
                    .background(Color.Black),
            )

            Button(
                modifier = Modifier.fillMaxWidth(),
                enabled = !isBusy,
                onClick = {
                    val captureFile = runCatching { createReceiptCaptureFile(context.cacheDir) }
                        .getOrElse {
                            onFailure(ReceiptCameraFailure.CaptureFailed)
                            return@Button
                        }
                    activeCaptureFile.value = captureFile
                    isBusy = true
                    imageCapture.takePicture(
                        ImageCapture.OutputFileOptions.Builder(captureFile).build(),
                        ContextCompat.getMainExecutor(context),
                        object : ImageCapture.OnImageSavedCallback {
                            override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                                scope.launch {
                                    try {
                                        val result = prepareReceiptCameraCapture(captureFile) { file ->
                                            preparer.prepare(Uri.fromFile(file))
                                        }
                                        activeCaptureFile.value = null
                                        onResult(result)
                                        onDismiss()
                                    } finally {
                                        isBusy = false
                                    }
                                }
                            }

                            override fun onError(exception: ImageCaptureException) {
                                captureFile.delete()
                                activeCaptureFile.value = null
                                isBusy = false
                                onFailure(ReceiptCameraFailure.CaptureFailed)
                            }
                        },
                    )
                },
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (isBusy) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                        )
                    }
                    Text(stringResource(R.string.transactions_transactioneditor_take_photo))
                }
            }
        }
    }
}

@SuppressLint("MissingPermission")
@Composable
private fun ReceiptCameraPreview(
    imageCapture: ImageCapture,
    onFailure: (ReceiptCameraFailure) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val latestOnFailure by rememberUpdatedState(onFailure)
    val previewView = remember(context) {
        PreviewView(context).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
    }
    val preview = remember(previewView) {
        Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
    }

    DisposableEffect(context, lifecycleOwner, preview, imageCapture) {
        val providerFuture = ProcessCameraProvider.getInstance(context)
        val executor = ContextCompat.getMainExecutor(context)
        var provider: ProcessCameraProvider? = null
        var disposed = false

        providerFuture.addListener(
            {
                if (disposed) return@addListener
                try {
                    val resolvedProvider = providerFuture.get()
                    provider = resolvedProvider
                    if (!resolvedProvider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)) {
                        latestOnFailure(ReceiptCameraFailure.Unavailable)
                        return@addListener
                    }
                    resolvedProvider.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        imageCapture,
                    )
                } catch (_: Exception) {
                    latestOnFailure(ReceiptCameraFailure.BindFailed)
                }
            },
            executor,
        )

        onDispose {
            disposed = true
            runCatching { provider?.unbind(preview, imageCapture) }
        }
    }

    AndroidView(
        factory = { previewView },
        modifier = modifier,
        update = { view -> imageCapture.targetRotation = view.display?.rotation ?: Surface.ROTATION_0 },
    )
}
