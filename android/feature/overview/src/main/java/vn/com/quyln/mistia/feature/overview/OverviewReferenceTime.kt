package vn.com.quyln.mistia.feature.overview

import androidx.compose.runtime.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import java.time.Instant
import kotlinx.coroutines.delay

@Composable internal fun rememberOverviewReferenceTime(now:()->Instant=Instant::now):Instant {
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    val currentNow by rememberUpdatedState(now)
    var reference by remember {mutableStateOf(currentNow())}
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while(true) {reference=currentNow();delay(60_000)}
        }
    }
    return reference
}
