package vn.com.quyln.mistia.feature.overview

import androidx.compose.runtime.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.CancellationException
import vn.com.quyln.mistia.core.model.*

internal sealed interface OverviewBudgetReadLoad {
    data object Loading:OverviewBudgetReadLoad
    data class Loaded(val snapshot:BudgetReadSnapshot):OverviewBudgetReadLoad
    data object Failed:OverviewBudgetReadLoad
}

@Composable
internal fun overviewBudgetReadLoad(owner:UserId,repository:FinanceRepository,retry:Int):State<OverviewBudgetReadLoad> {
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    return key(owner.value,repository,retry,lifecycle) {
        produceState<OverviewBudgetReadLoad>(OverviewBudgetReadLoad.Loading) {
            try {
                lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                    value=OverviewBudgetReadLoad.Loading
                    repository.observeBudgetReadSnapshot(owner).collect {
                        value=if(it.owner==owner) OverviewBudgetReadLoad.Loaded(it) else OverviewBudgetReadLoad.Failed
                    }
                }
            } catch(cancelled:CancellationException) {throw cancelled}
            catch(_:Exception) {value=OverviewBudgetReadLoad.Failed}
        }
    }
}
