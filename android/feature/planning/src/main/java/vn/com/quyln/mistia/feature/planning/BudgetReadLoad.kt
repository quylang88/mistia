package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.CancellationException
import vn.com.quyln.mistia.core.model.*

internal sealed interface BudgetReadLoad {
    data object Loading:BudgetReadLoad
    data class Loaded(val snapshot:BudgetReadSnapshot):BudgetReadLoad
    data object Failed:BudgetReadLoad
}

@Composable
internal fun budgetReadLoad(owner:UserId,repository:FinanceRepository,retry:Int):State<BudgetReadLoad> {
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    return key(owner.value,repository,retry,lifecycle) {
        produceState<BudgetReadLoad>(BudgetReadLoad.Loading) {
            try {
                lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                    value=BudgetReadLoad.Loading
                    repository.observeBudgetReadSnapshot(owner).collect {
                        value=if(it.owner==owner) BudgetReadLoad.Loaded(it) else BudgetReadLoad.Failed
                    }
                }
            } catch(cancelled:CancellationException) {throw cancelled}
            catch(_:Exception) {value=BudgetReadLoad.Failed}
        }
    }
}
