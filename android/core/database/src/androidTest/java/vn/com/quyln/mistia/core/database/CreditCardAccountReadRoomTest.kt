package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.Collections
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class CreditCardAccountReadRoomTest {
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val now = "2026-10-01T00:00:00Z"
    private fun id(n: Int) = java.util.UUID(0, n.toLong()).toString()
    private val device = id(90)
    private val saved = CreditCardDraft(walletId = id(1), profileId = id(2), name = "Card", creditLimitMinor = 1000)
        .toMutation(owner, null, null, null, device, now)
    private val charge = TransactionDraft(id = id(3), primaryKind = TransactionPrimaryKind.TRANSFER,
        transferSubtype = TransactionTransferSubtype.DEBT, debtIntent = TransactionDebtIntent.LEND, title = "Charge",
        amountMinor = 70, occurredAt = now, sourceWalletId = saved.wallet.record.id, counterpartyName = "A")
        .toMutation(owner, null, saved.wallet.record, null, null, device, now).record

    @Before fun setup() {
        db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store)
    }
    @After fun close() { db.close() }
    private fun rows(generation: Int = 0) = listOf(saved.wallet.record.toCloudRecord(),
        saved.profile.record.copy(creditLimitMinor = 1000L + generation).toCloudRecord(),
        charge.copy(amountMinor = 70L + generation).toCloudRecord()).map {
            it.copy(payload = JsonObject(it.payload + ("generation" to JsonPrimitive(generation))))
        }
    private fun pending(row: CloudRecord) = PendingMutation(requireNotNull(CloudEntity.fromTable(row.entity)), row.id,
        row.ownerUserId, if (row.deletedAt == null) MutationKind.UPSERT else MutationKind.DELETE,
        row.payload, now, row.syncVersion, device)
    private suspend fun batch(generation: Int = 0) = store.commitMutations(rows(generation).map { it to pending(it) })
    private suspend fun state() = CreditCardAccountReadSnapshot.entities.associateWith {
        store.recordsIncludingDeleted(owner, it.table) to store.pendingMutations(owner, it, Long.MAX_VALUE)
    }

    @Test fun ownedSnapshotContainsAllThreeDomainsAndPreservesHistoryWithoutReadWrites() = runBlocking {
        batch()
        val dead = charge.copy(deletedAt = now, isArchived = true, archivedAt = now).toCloudRecord()
        store.commitMutation(dead, pending(dead))
        val before = state(); val snapshot = repo.observeCreditCardAccountReadSnapshot(owner).first()
        Assert.assertEquals(owner, snapshot.owner)
        Assert.assertEquals(CreditCardAccountReadSnapshot.entities.map { it.table }.toSet(), snapshot.rows.map { it.entity }.toSet())
        Assert.assertEquals(dead, snapshot.rows.single { it.entity == CloudEntity.LEDGER_TRANSACTION.table })
        Assert.assertEquals(0L, planningCreditCardAccounts(snapshot).single().currentDebtMinor)
        Assert.assertEquals(before, state())
    }

    @Test fun atomicWalletProfileAndLedgerChangesNeverEmitMixedReadGenerations() = runBlocking {
        batch(); val observed = AtomicInteger(-1)
        val values = Collections.synchronizedList(mutableListOf<List<Int>>())
        val job = launch(Dispatchers.Unconfined, start = CoroutineStart.UNDISPATCHED) {
            repo.observeCreditCardAccountReadSnapshot(owner).collect { snapshot ->
                val generations = snapshot.rows.map { it.payload.getValue("generation").jsonPrimitive.int }
                values.add(generations)
                if (generations.size == 3 && generations.distinct().size == 1) observed.set(generations.first())
                Assert.assertEquals(930L, planningCreditCardAccounts(snapshot).single().availableCreditMinor)
            }
        }
        try {
            withTimeout(5000) { while (observed.get() < 0) delay(5) }
            for (generation in 1..16) { batch(generation); withTimeout(5000) { while (observed.get() < generation) delay(5) } }
        } finally { job.cancelAndJoin() }
        Assert.assertTrue(values.isNotEmpty())
        Assert.assertTrue(synchronized(values) { values.all { it.size == 3 && it.distinct().size == 1 } })
    }

    @Test fun foreignOwnerAndUnrelatedEntityAreExcludedAtTheSingleQueryBoundary() = runBlocking {
        batch()
        for (row in rows()) {
            val foreign = row.copy(ownerUserId = other.value, payload = JsonObject(row.payload + ("user_id" to JsonPrimitive(other.value))))
            store.commitMutation(foreign, pending(foreign))
        }
        val unrelated = rows().first().copy(entity = CloudEntity.BUDGET_PLAN.table)
        store.commitMutation(unrelated, pending(unrelated))
        val snapshot = store.observeCreditCardAccountReadSnapshot(owner).first()
        Assert.assertEquals(3, snapshot.rows.size)
        Assert.assertTrue(snapshot.rows.all { it.ownerUserId == owner.value && it.entity in CreditCardAccountReadSnapshot.entities.map { e -> e.table } })
    }

    @Test fun genuinelyEmptyReadIsAvailableAndCancellationDoesNotWrite() = runBlocking {
        val first = repo.observeCreditCardAccountReadSnapshot(owner).first()
        Assert.assertEquals(owner, first.owner); Assert.assertTrue(first.rows.isEmpty())
        val before = state(); val job = launch { repo.observeCreditCardAccountReadSnapshot(owner).collect {} }
        yield(); job.cancelAndJoin(); Assert.assertEquals(before, state())
    }

    @Test fun malformedOwnedMoneySurvivesRawReadButRepositoryRejectsSuccessfulPartialAccounts() = runBlocking {
        batch(); val profile = rows().single { it.entity == CloudEntity.CREDIT_CARD_PROFILE.table }
        val bad = profile.copy(payload = JsonObject(profile.payload + ("credit_limit_minor" to JsonPrimitive("1000"))))
        store.commitMutation(bad, pending(bad)); val before = state()
        Assert.assertEquals(bad, store.observeCreditCardAccountReadSnapshot(owner).first().rows.single { it.id == profile.id })
        val failure = runCatching { repo.observeCreditCardAccountReadSnapshot(owner).first() }.exceptionOrNull()
        Assert.assertTrue(failure is IllegalArgumentException); Assert.assertEquals(before, state())
    }

    @Test fun repositoryRejectsAChangedSnapshotOwnerInsteadOfRelabellingRows() = runBlocking {
        val substituted = object : LocalStore by store {
            override fun observeCreditCardAccountReadSnapshot(owner: UserId) = flowOf(CreditCardAccountReadSnapshot(other, rows()))
        }
        val failure = runCatching { OfflineFirstFinanceRepository(substituted).observeCreditCardAccountReadSnapshot(owner).first() }.exceptionOrNull()
        Assert.assertTrue(failure is IllegalArgumentException)
    }

    @Test fun repositoryRejectsForeignBodyInsideAnOwnedEnvelope() = runBlocking {
        val row = rows().first().let { it.copy(payload = JsonObject(it.payload + ("user_id" to JsonPrimitive(other.value)))) }
        val substituted = object : LocalStore by store {
            override fun observeCreditCardAccountReadSnapshot(owner: UserId) = flowOf(CreditCardAccountReadSnapshot(owner, listOf(row)))
        }
        val failure = runCatching { OfflineFirstFinanceRepository(substituted).observeCreditCardAccountReadSnapshot(owner).first() }.exceptionOrNull()
        Assert.assertTrue(failure is IllegalArgumentException)
    }

    @Test fun snapshotAndOutboxesSurviveDiskReopenWithoutReadMutations() = runBlocking {
        val name = "card-read-${java.util.UUID.randomUUID()}"
        db.close(); db = Room.databaseBuilder(context, MistiaDatabase::class.java, name).allowMainThreadQueries().build()
        store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store)
        try {
            batch(); val before = state(); val snapshot = repo.observeCreditCardAccountReadSnapshot(owner).first()
            db.close(); db = Room.databaseBuilder(context, MistiaDatabase::class.java, name).allowMainThreadQueries().build()
            store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store)
            Assert.assertEquals(snapshot, repo.observeCreditCardAccountReadSnapshot(owner).first())
            Assert.assertEquals(before, state())
        } finally { db.close(); context.deleteDatabase(name) }
    }
}
