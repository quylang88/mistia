package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.key
import androidx.compose.runtime.produceState
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.flow
import vn.com.quyln.mistia.core.model.*

internal sealed interface PlanningCreditCardLoad {
    val owner: UserId
    data class Loading(override val owner: UserId) : PlanningCreditCardLoad
    data class Failed(override val owner: UserId) : PlanningCreditCardLoad
    data class Loaded(val snapshot: CreditCardAccountReadSnapshot, val accounts: List<PlanningCreditCardAccount>) : PlanningCreditCardLoad {
        override val owner: UserId get() = snapshot.owner
    }
}

internal fun planningCreditCardLoad(owner: UserId, read: () -> Flow<CreditCardAccountReadSnapshot>): Flow<PlanningCreditCardLoad> = flow {
    emit(PlanningCreditCardLoad.Loading(owner))
    read().collect { snapshot ->
        currentCoroutineContext().ensureActive()
        require(snapshot.owner == owner) { "Card load owner changed" }
        val accounts = withContext(Dispatchers.Default) { planningCreditCardAccounts(snapshot) }
        currentCoroutineContext().ensureActive()
        emit(PlanningCreditCardLoad.Loaded(snapshot, accounts))
    }
}.catch { error ->
    if (error is CancellationException || error !is Exception) throw error
    emit(PlanningCreditCardLoad.Failed(owner))
}

internal fun PlanningCreditCardLoad.forOwner(owner: UserId): PlanningCreditCardLoad =
    if (this.owner == owner) this else PlanningCreditCardLoad.Loading(owner)

@Composable
internal fun rememberPlanningCreditCardLoad(owner: UserId, repository: FinanceRepository, active: Boolean, retry: Int): State<PlanningCreditCardLoad> =
    key(owner.value, repository) {
        val lifecycle = LocalLifecycleOwner.current.lifecycle
        produceState<PlanningCreditCardLoad>(PlanningCreditCardLoad.Loading(owner), active, retry, lifecycle) {
            value = PlanningCreditCardLoad.Loading(owner)
            if (active) lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                planningCreditCardLoad(owner) { repository.observeCreditCardAccountReadSnapshot(owner) }.collect { value = it }
            }
        }
    }
