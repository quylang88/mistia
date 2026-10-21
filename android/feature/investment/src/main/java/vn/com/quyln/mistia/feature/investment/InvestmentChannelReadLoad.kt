package vn.com.quyln.mistia.feature.investment

import androidx.compose.runtime.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.CancellationException
import vn.com.quyln.mistia.core.model.*

internal sealed interface InvestmentChannelReadLoad {
    data object Loading:InvestmentChannelReadLoad
    data class Loaded(val snapshot:InvestmentChannelSnapshot):InvestmentChannelReadLoad
    data object Failed:InvestmentChannelReadLoad
}
@Composable internal fun investmentChannelReadLoad(owner:UserId,repository:InvestmentRepository,retry:Int):State<InvestmentChannelReadLoad> {
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    return key(owner.value,repository,retry,lifecycle) {produceState<InvestmentChannelReadLoad>(InvestmentChannelReadLoad.Loading) {
        try{lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED){
            value=InvestmentChannelReadLoad.Loading
            repository.observeChannelSnapshot(owner).collect{value=if(it.owner==owner) InvestmentChannelReadLoad.Loaded(it) else InvestmentChannelReadLoad.Failed}
        }}catch(cancelled:CancellationException){throw cancelled}catch(_:Exception){value=InvestmentChannelReadLoad.Failed}
    }}
}
