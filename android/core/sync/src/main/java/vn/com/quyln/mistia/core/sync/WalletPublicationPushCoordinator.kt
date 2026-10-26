package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import vn.com.quyln.mistia.core.model.*

/** One engine wallet entry: release old links first, then publish dirty targets before new links. */
class WalletPublicationPushCoordinator(
    private val ordinary:DomainPushCoordinator,private val investment:DomainPushCoordinator,
):DomainPushCoordinator {
    override val entity=CloudEntity.LEDGER_WALLET
    init { require(ordinary.entity==entity && investment.entity==entity){"Wallet publication requires wallet coordinators"} }
    override suspend fun pushPending(ownerUserId:UserId,accessToken:String):DomainPushSummary {
        val caller=currentCoroutineContext()
        var summary=DomainPushSummary()
        for(coordinator in listOf(investment,ordinary,investment,ordinary)) {
            caller.ensureActive()
            summary+=coordinator.pushPending(ownerUserId,accessToken)
            caller.ensureActive()
        }
        return summary
    }
    private operator fun DomainPushSummary.plus(other:DomainPushSummary)=DomainPushSummary(
        pushed+other.pushed,acknowledged+other.acknowledged,conflicts+other.conflicts,
        retryableFailures+other.retryableFailures,permanentFailures+other.permanentFailures,
        staleResponses+other.staleResponses,reconciled+other.reconciled,
    )
}
