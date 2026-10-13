package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class SavingsGoalRepositoryTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("44444444-4444-4444-4444-444444444444")
    private val device="22222222-2222-2222-2222-222222222222"
    private val goalId="33333333-3333-3333-3333-333333333333"
    private val now="2026-10-13T00:00:00Z"
    private val later="2026-10-13T01:00:00Z"
    private val store=BudgetMemoryStore()
    private val repo=OfflineFirstFinanceRepository(store)
    private fun draft()=SavingsGoalDraft(name="  Travel  ",targetMinor=9007199254740993L,currentSavedMinor=50,
        targetDate="2027-01-01T00:00:00Z",currencyCode="JPY",id=goalId)

    @Test fun `create trims identity and saves one scoped record and mutation`()=runTest {
        val saved=repo.saveSavingsGoal(owner,draft(),device,now).getOrThrow()
        assertEquals("Travel",saved.name);assertEquals(0,saved.sortOrder)
        assertEquals(9007199254740993L,saved.targetMinor)
        assertEquals(saved,repo.observeSavingsGoals(owner).first().single())
        assertTrue(repo.observeSavingsGoals(other).first().isEmpty())
        assertEquals(saved.toPayload(),store.outboxRows(owner.value).single().payload)
        assertEquals(1,store.batches.size)
        assertTrue(repo.observeWallets(owner).first().isEmpty())
    }
    @Test fun `edit keeps original currency created date version and clears wallet explicitly`()=runTest {
        val wallet=repo.saveWallet(owner,WalletDraft(name="Cash",kind=WalletKind.CASH,currencyCode="JPY"),device,now).getOrThrow()
        val saved=repo.saveSavingsGoal(owner,draft().copy(linkedWalletId=wallet.id),device,now).getOrThrow().copy(syncVersion=9007199254740993L)
        store.commitMutation(saved.toCloudRecord(),saved.pendingMutation())
        val edited=repo.saveSavingsGoal(owner,draft().copy(editingExisting=true,currencyCode="VND",currentSavedMinor=-100,linkedWalletId=null),device,later).getOrThrow()
        assertEquals("JPY",edited.currencyCode);assertEquals(now,edited.createdAt);assertEquals(saved.syncVersion,edited.syncVersion)
        assertEquals(-100,edited.currentSavedMinor);assertNull(edited.linkedWalletId)
        assertEquals(saved.syncVersion,store.outboxRows(owner.value).single { it.entity==CloudEntity.SAVINGS_GOAL }.baseVersion)
    }
    @Test fun `invalid name target foreign wallet and stale edit produce no mutation`()=runTest {
        val wallet=repo.saveWallet(other,WalletDraft(name="Other",kind=WalletKind.CASH,currencyCode="JPY"),device,now).getOrThrow()
        listOf(draft().copy(name=" "),draft().copy(targetMinor=0),draft().copy(linkedWalletId=wallet.id),draft().copy(editingExisting=true)).forEach {
            assertTrue(repo.saveSavingsGoal(owner,it,device,now).isFailure)
        }
        assertTrue(repo.observeSavingsGoals(owner).first().isEmpty())
        assertTrue(store.outboxRows(owner.value).isEmpty())
    }
    @Test fun `archived wallet remains allowed only as unchanged preferred link`()=runTest {
        val wallet=repo.saveWallet(owner,WalletDraft(name="Old",kind=WalletKind.CASH,currencyCode="JPY"),device,now).getOrThrow()
        repo.saveSavingsGoal(owner,draft().copy(linkedWalletId=wallet.id),device,now).getOrThrow()
        repo.archiveWallet(owner,RecordId(wallet.id),device,later).getOrThrow()
        assertTrue(repo.saveSavingsGoal(owner,draft().copy(editingExisting=true,linkedWalletId=wallet.id),device,later).isSuccess)
        assertTrue(repo.saveSavingsGoal(owner,draft().copy(id=null,linkedWalletId=wallet.id),device,later).isFailure)
    }
    @Test fun `delete tombstones with unchanged version and stale edit cannot resurrect`()=runTest {
        val saved=repo.saveSavingsGoal(owner,draft(),device,now).getOrThrow()
        assertTrue(repo.deleteSavingsGoal(other,RecordId(saved.id),device,later).isFailure)
        repo.deleteSavingsGoal(owner,RecordId(saved.id),device,later).getOrThrow()
        assertTrue(repo.observeSavingsGoals(owner).first().isEmpty())
        val mutation=store.outboxRows(owner.value).single()
        assertEquals(MutationKind.DELETE,mutation.kind);assertEquals(later,mutation.payload!!["deleted_at"]!!.toString().trim('"'))
        assertEquals(saved.syncVersion,mutation.baseVersion)
        assertTrue(repo.saveSavingsGoal(owner,draft().copy(editingExisting=true),device,later).isFailure)
    }
    @Test fun `order increments active goals only and overflow does not wrap`()=runTest {
        val saved=repo.saveSavingsGoal(owner,draft(),device,now).getOrThrow()
        val second=repo.saveSavingsGoal(owner,draft().copy(id=null),device,now).getOrThrow()
        assertEquals(1,second.sortOrder)
        val max=second.copy(sortOrder=Int.MAX_VALUE)
        store.commitMutation(max.toCloudRecord(),max.pendingMutation())
        assertTrue(repo.saveSavingsGoal(owner,draft().copy(id=null),device,now).isFailure)
        assertEquals(listOf(saved.id,second.id),repo.observeSavingsGoals(owner).first().map { it.id })
    }
    @Test fun `storage failure leaves no record or outbox and cancellation propagates`()=runTest {
        store.failBatch=true
        assertTrue(repo.saveSavingsGoal(owner,draft(),device,now).isFailure)
        assertTrue(repo.observeSavingsGoals(owner).first().isEmpty());assertTrue(store.outboxRows(owner.value).isEmpty())
        val cancelling=object:LocalStore by store {
            override suspend fun commitMutations(mutations:List<Pair<CloudRecord,PendingMutation>>) { throw CancellationException("cancel") }
        }
        try { OfflineFirstFinanceRepository(cancelling).saveSavingsGoal(owner,draft(),device,now);fail("cancellation swallowed") }
        catch(expected:CancellationException) { }
    }
    @Test fun `supplied UUID identity canonicalizes and uppercase edit lookup keeps same record`()=runTest {
        val uppercase="AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        val saved=repo.saveSavingsGoal(owner,draft().copy(id=uppercase),device,now).getOrThrow()
        assertEquals(uppercase.lowercase(),saved.id)
        val edited=repo.saveSavingsGoal(owner,draft().copy(id=uppercase,editingExisting=true),device,later).getOrThrow()
        assertEquals(saved.id,edited.id)
        assertEquals(1,repo.observeSavingsGoals(owner).first().size)
    }
    @Test fun `foreign payload owner hidden and rejected despite viewer envelope`()=runTest {
        val saved=repo.saveSavingsGoal(owner,draft(),device,now).getOrThrow()
        val forged=saved.copy(ownerUserId=other.value).toCloudRecord().copy(ownerUserId=owner.value)
        store.commitMutation(forged, saved.pendingMutation())
        assertTrue(repo.observeSavingsGoals(owner).first().isEmpty())
        assertTrue(repo.saveSavingsGoal(owner,draft().copy(editingExisting=true),device,later).isFailure)
        assertTrue(repo.deleteSavingsGoal(owner,RecordId(goalId),device,later).isFailure)
    }
}
