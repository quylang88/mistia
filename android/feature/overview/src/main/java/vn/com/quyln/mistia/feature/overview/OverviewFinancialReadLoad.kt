package vn.com.quyln.mistia.feature.overview

import androidx.compose.runtime.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.CancellationException
import vn.com.quyln.mistia.core.model.*

internal sealed interface OverviewFinancialReadLoad {
    data object Loading:OverviewFinancialReadLoad
    data class Loaded(val snapshot:OverviewFinancialReadSnapshot):OverviewFinancialReadLoad
    data object Failed:OverviewFinancialReadLoad
}

@Composable
internal fun overviewFinancialReadLoad(owner:UserId,repository:FinanceRepository,retry:Int):State<OverviewFinancialReadLoad> {
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    return key(owner.value,repository,retry,lifecycle) {
        produceState<OverviewFinancialReadLoad>(OverviewFinancialReadLoad.Loading) {
            try {
                lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                    value=OverviewFinancialReadLoad.Loading
                    repository.observeOverviewFinancialReadSnapshot(owner).collect {
                        value=if(it.owner==owner) OverviewFinancialReadLoad.Loaded(it) else OverviewFinancialReadLoad.Failed
                    }
                }
            } catch(cancelled:CancellationException) {throw cancelled}
            catch(_:Exception) {value=OverviewFinancialReadLoad.Failed}
        }
    }
}
