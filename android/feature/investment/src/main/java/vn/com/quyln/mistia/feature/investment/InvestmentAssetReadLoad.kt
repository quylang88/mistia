package vn.com.quyln.mistia.feature.investment

import androidx.compose.runtime.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.CancellationException
import vn.com.quyln.mistia.core.model.*

internal sealed interface InvestmentAssetReadLoad {
    data object Loading:InvestmentAssetReadLoad
    data object Failed:InvestmentAssetReadLoad
    data class Loaded(val snapshot:InvestmentAssetSnapshot):InvestmentAssetReadLoad
}

@Composable internal fun investmentAssetReadLoad(owner:UserId,repository:InvestmentRepository,retry:Int):State<InvestmentAssetReadLoad> {
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    return key(owner.value,repository,retry,lifecycle) {
        produceState<InvestmentAssetReadLoad>(InvestmentAssetReadLoad.Loading) {
            try {
                lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                    value=InvestmentAssetReadLoad.Loading
                    repository.observeAssetSnapshot(owner).collect{snapshot ->
                        val scoped=snapshot.owner==owner && snapshot.rows.all{row ->
                            val entity=CloudEntity.fromTable(row.entity)
                            entity!=null && entity in InvestmentAssetSnapshot.entities && row.financeRawIdentity(owner,entity,true)
                        }
                        value=if(scoped)InvestmentAssetReadLoad.Loaded(snapshot) else InvestmentAssetReadLoad.Failed
                    }
                }
            }catch(cancelled:CancellationException){throw cancelled}
            catch(_:Exception){value=InvestmentAssetReadLoad.Failed}
        }
    }
}
