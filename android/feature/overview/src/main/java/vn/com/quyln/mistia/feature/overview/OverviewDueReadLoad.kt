package vn.com.quyln.mistia.feature.overview

import androidx.compose.runtime.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.CancellationException
import vn.com.quyln.mistia.core.model.*

internal sealed interface OverviewDueReadLoad {
    data object Loading:OverviewDueReadLoad
    data class Loaded(val snapshot:UpcomingDueReadSnapshot):OverviewDueReadLoad
    data object Failed:OverviewDueReadLoad
}

@Composable
internal fun overviewDueReadLoad(owner:UserId,repository:FinanceRepository,retry:Int):State<OverviewDueReadLoad> {
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    return key(owner.value,repository,retry,lifecycle) {
        produceState<OverviewDueReadLoad>(OverviewDueReadLoad.Loading) {
            try {
                lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                    value=OverviewDueReadLoad.Loading
                    repository.observeUpcomingDueReadSnapshot(owner).collect {
                        value=if(it.owner==owner) OverviewDueReadLoad.Loaded(it) else OverviewDueReadLoad.Failed
                    }
                }
            } catch(cancelled:CancellationException) {throw cancelled}
            catch(_:Exception) {value=OverviewDueReadLoad.Failed}
        }
    }
}
