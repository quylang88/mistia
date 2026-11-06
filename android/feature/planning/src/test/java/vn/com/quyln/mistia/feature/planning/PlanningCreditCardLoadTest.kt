package vn.com.quyln.mistia.feature.planning

import java.io.IOException
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class PlanningCreditCardLoadTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val saved = CreditCardDraft(name = "Owned card", creditLimitMinor = 1000)
        .toMutation(owner, null, null, null, device, "2026-10-01T00:00:00Z")
    private val snapshot = CreditCardAccountReadSnapshot(owner,
        listOf(saved.wallet.record.toCloudRecord(), saved.profile.record.toCloudRecord()))

    @Test fun loadingIsEmittedBeforeTheSourceIsInvokedAndRealAccountsFollow() = runBlocking {
        var started = false
        val states = planningCreditCardLoad(owner) { started = true; flowOf(snapshot) }
            .onEach { if (it is PlanningCreditCardLoad.Loading) assertFalse(started) }.toList()
        assertTrue(started); assertEquals(2, states.size)
        assertEquals(owner, states.first().owner)
        val loaded = states.last() as PlanningCreditCardLoad.Loaded
        assertEquals(snapshot, loaded.snapshot)
        assertEquals("Owned card", loaded.accounts.single().wallet.name)
        assertEquals(1000L, loaded.accounts.single().availableCreditMinor)
    }

    @Test fun aCompletedEmptyReadIsLoadedRatherThanAnUnobservedEmptyDefault() = runBlocking {
        var reads = 0
        val states = planningCreditCardLoad(owner) { reads++; flowOf(CreditCardAccountReadSnapshot(owner, emptyList())) }.toList()
        assertEquals(1, reads); assertTrue(states.first() is PlanningCreditCardLoad.Loading)
        assertTrue((states.last() as PlanningCreditCardLoad.Loaded).accounts.isEmpty())
    }

    @Test fun changedOwnerCannotProduceAnAccountSuccessForTheRequestedOwner() = runBlocking {
        val states = planningCreditCardLoad(owner) { flowOf(snapshot.copy(owner = other)) }.toList()
        assertTrue(states.first() is PlanningCreditCardLoad.Loading)
        assertEquals(PlanningCreditCardLoad.Failed(owner), states.last())
        assertFalse(states.any { it is PlanningCreditCardLoad.Loaded })
    }

    @Test fun malformedOwnedMoneyProducesAnExplicitFailureInsteadOfPartialCards() = runBlocking {
        val row = saved.profile.record.toCloudRecord()
        val bad = snapshot.copy(rows = listOf(saved.wallet.record.toCloudRecord(),
            row.copy(payload = JsonObject(row.payload + ("credit_limit_minor" to JsonPrimitive("1000"))))))
        val states = planningCreditCardLoad(owner) { flowOf(bad) }.toList()
        assertEquals(PlanningCreditCardLoad.Failed(owner), states.last())
        assertFalse(states.any { it is PlanningCreditCardLoad.Loaded })
    }

    @Test fun sourceConstructionErrorsBecomeRetryablePresentationFailure() = runBlocking {
        var calls = 0
        val states = planningCreditCardLoad(owner) { calls++; throw IOException("synthetic") }.toList()
        assertEquals(1, calls)
        assertEquals(listOf(PlanningCreditCardLoad.Loading(owner), PlanningCreditCardLoad.Failed(owner)), states)
    }

    @Test fun sourceFailureAfterSuccessDoesNotKeepThePreviousCardsAsCurrent() = runBlocking {
        val states = planningCreditCardLoad(owner) { flow { emit(snapshot); throw IOException("synthetic") } }.toList()
        assertTrue(states[1] is PlanningCreditCardLoad.Loaded)
        assertEquals(PlanningCreditCardLoad.Failed(owner), states.last())
    }

    @Test fun cancellationPropagatesWithoutAnErrorPresentation() = runBlocking {
        val states = mutableListOf<PlanningCreditCardLoad>()
        val failure = runCatching {
            planningCreditCardLoad(owner) { throw CancellationException("caller stopped") }.toList(states)
        }.exceptionOrNull()
        assertTrue(failure is CancellationException)
        assertEquals(listOf(PlanningCreditCardLoad.Loading(owner)), states)
    }

    @Test fun ownerPresentationGateClearsOldLoadedStateBeforeANewCollectorRuns() {
        val loaded = PlanningCreditCardLoad.Loaded(snapshot, planningCreditCardAccounts(snapshot))
        assertEquals(PlanningCreditCardLoad.Loading(other), loaded.forOwner(other))
        assertSame(loaded, loaded.forOwner(owner))
    }

    @Test fun aNewCollectionRetriesTheActualSourceAfterFailure() = runBlocking {
        var calls = 0
        val read = { calls++; if (calls == 1) throw IOException("first attempt") else flowOf(snapshot) }
        assertEquals(PlanningCreditCardLoad.Failed(owner), planningCreditCardLoad(owner, read).toList().last())
        assertTrue(planningCreditCardLoad(owner, read).toList().last() is PlanningCreditCardLoad.Loaded)
        assertEquals(2, calls)
    }
}
