package vn.com.quyln.mistia.feature.investment

import androidx.compose.runtime.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.CancellationException
import vn.com.quyln.mistia.core.model.*

internal sealed interface InvestmentWalletReadLoad {
    data object Loading:InvestmentWalletReadLoad
    data object Failed:InvestmentWalletReadLoad
    data class Loaded(val snapshot:InvestmentCashReadSnapshot):InvestmentWalletReadLoad
}

@Composable internal fun investmentWalletReadLoad(owner:UserId,repository:InvestmentRepository,retry:Int):State<InvestmentWalletReadLoad> {
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    return key(owner.value,repository,retry,lifecycle) {
        produceState<InvestmentWalletReadLoad>(InvestmentWalletReadLoad.Loading) {
            try {
                lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                    value=InvestmentWalletReadLoad.Loading
                    repository.observeCashSnapshot(owner).collect { snapshot ->
                        val scoped=snapshot.owner==owner && runCatching{snapshot.requireScoped()}.isSuccess
                        value=if(scoped)InvestmentWalletReadLoad.Loaded(snapshot) else InvestmentWalletReadLoad.Failed
                    }
                }
            }catch(cancelled:CancellationException){throw cancelled}
            catch(_:Exception){value=InvestmentWalletReadLoad.Failed}
        }
    }
}
