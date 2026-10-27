package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.*
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InvestmentPublicationPushCoordinatorTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val order=mutableListOf<CloudEntity>()
    private fun publisher(kind:CloudEntity,n:Int,after:suspend ()->Unit = {})=object:DomainPushCoordinator {
        override val entity=kind
        override suspend fun pushPending(ownerUserId:UserId,accessToken:String):DomainPushSummary {
            assertEquals(owner,ownerUserId);assertEquals("captured-token",accessToken);order+=kind;after()
            return DomainPushSummary(n,n*2,n*3,n*4,n*5,n*6,n*7)
        }
    }
    private fun coordinator(afterAsset:suspend ()->Unit = {})=InvestmentPublicationPushCoordinator(
        publisher(CloudEntity.INVESTMENT_CHANNEL,1),publisher(CloudEntity.INVESTMENT_ASSET,10,afterAsset),publisher(CloudEntity.INVESTMENT_TRADE,100))
    @Test fun publishesPrerequisitesThenTradesBeforeFinalAssetAndChannelRetirement()=runTest {
        assertEquals(CloudEntity.INVESTMENT_CHANNEL,coordinator().entity)
        coordinator().pushPending(owner,"captured-token")
        assertEquals(listOf(CloudEntity.INVESTMENT_CHANNEL,CloudEntity.INVESTMENT_ASSET,CloudEntity.INVESTMENT_TRADE,CloudEntity.INVESTMENT_ASSET,CloudEntity.INVESTMENT_CHANNEL),order)
    }
    @Test fun preservesAllSevenSummaryCountersAcrossEveryPhase()=runTest {
        assertEquals(DomainPushSummary(122,244,366,488,610,732,854),coordinator().pushPending(owner,"captured-token"))
    }
    @Test fun cancellationBetweenPhasesStopsFurtherPublication()=runTest {
        val job=launch{coordinator{currentCoroutineContext().cancel()}.pushPending(owner,"captured-token")}
        job.join();assertTrue(job.isCancelled)
        assertEquals(listOf(CloudEntity.INVESTMENT_CHANNEL,CloudEntity.INVESTMENT_ASSET),order)
    }
    @Test fun cashEventsRunAfterTradesAndBeforeRetirementWithoutDuplicateEntityLoss()=runTest {
        val c=InvestmentPublicationPushCoordinator(publisher(CloudEntity.INVESTMENT_CHANNEL,1),publisher(CloudEntity.INVESTMENT_ASSET,10),
            publisher(CloudEntity.INVESTMENT_TRADE,100),publisher(CloudEntity.LEDGER_TRANSACTION,1000))
        assertEquals(DomainPushSummary(1122,2244,3366,4488,5610,6732,7854),c.pushPending(owner,"captured-token"))
        assertEquals(listOf(CloudEntity.INVESTMENT_CHANNEL,CloudEntity.INVESTMENT_ASSET,CloudEntity.INVESTMENT_TRADE,CloudEntity.LEDGER_TRANSACTION,CloudEntity.INVESTMENT_ASSET,CloudEntity.INVESTMENT_CHANNEL),order)
    }

}
