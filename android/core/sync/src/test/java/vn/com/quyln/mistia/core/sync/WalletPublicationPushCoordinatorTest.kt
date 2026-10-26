package vn.com.quyln.mistia.core.sync

import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.cancel
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class WalletPublicationPushCoordinatorTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val calls=mutableListOf<String>()
    private fun child(name:String,entity:CloudEntity=CloudEntity.LEDGER_WALLET,action:suspend ()->DomainPushSummary={DomainPushSummary()})=object:DomainPushCoordinator {
        override val entity=entity
        override suspend fun pushPending(ownerUserId:UserId,accessToken:String):DomainPushSummary {
            assertEquals(owner,ownerUserId);assertEquals("token",accessToken);calls+=name;return action()
        }
    }
    @Test fun rootPreflightOrdinaryThenRootDependencyPassRetainsEverySummaryCounter()=runTest {
        var roots=0
        val root=child("root"){roots++;if(roots==1)DomainPushSummary(1,2,3,4,5,6,7) else DomainPushSummary(100,200,300,400,500,600,700)}
        val ordinary=child("ordinary"){DomainPushSummary(10,20,30,40,50,60,70)}
        assertEquals(DomainPushSummary(121,242,363,484,605,726,847),WalletPublicationPushCoordinator(ordinary,root).pushPending(owner,"token"))
        assertEquals(listOf("root","ordinary","root","ordinary"),calls)
    }
    @Test fun cancellationFromRootPreflightStopsAllRemainingPhases()=runTest {
        val result=runCatching{WalletPublicationPushCoordinator(child("ordinary"),child("root"){throw CancellationException("revoked")}).pushPending(owner,"token")}
        assertTrue(result.exceptionOrNull() is CancellationException);assertEquals(listOf("root"),calls)
    }
    @Test fun ordinaryFailurePropagatesWithoutRunningTheDependencyPass()=runTest {
        val failure=IOException("local store unavailable")
        val result=runCatching{WalletPublicationPushCoordinator(child("ordinary"){throw failure},child("root")).pushPending(owner,"token")}
        assertSame(failure,result.exceptionOrNull());assertEquals(listOf("root","ordinary"),calls)
    }
    @Test fun cancellationBetweenChildrenCannotRunAnotherPhase()=runTest {
        val result=runCatching{withContext(Job()) {
            WalletPublicationPushCoordinator(child("ordinary"),child("root"){currentCoroutineContext().cancel();DomainPushSummary()}).pushPending(owner,"token")
        }}
        assertTrue(result.exceptionOrNull() is CancellationException);assertEquals(listOf("root"),calls)
    }
    @Test fun anotherEntityCannotBeHiddenInsideTheWalletRegistration() {
        assertTrue(runCatching{WalletPublicationPushCoordinator(child("ordinary",CloudEntity.LEDGER_TRANSACTION),child("root"))}.isFailure)
        assertTrue(runCatching{WalletPublicationPushCoordinator(child("ordinary"),child("root",CloudEntity.INVESTMENT_ASSET))}.isFailure)
    }
}
