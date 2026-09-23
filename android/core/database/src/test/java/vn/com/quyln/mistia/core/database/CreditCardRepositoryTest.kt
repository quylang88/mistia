package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.CreditCardDraft
import vn.com.quyln.mistia.core.model.CreditCardNetwork
import vn.com.quyln.mistia.core.model.EntityCount
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.PendingMutation
import vn.com.quyln.mistia.core.model.QueuedMutation
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.WalletDraft
import vn.com.quyln.mistia.core.model.WalletKind

class CreditCardRepositoryTest {
    @Test
    fun `save atomically creates owner scoped card wallet and profile outbox rows`() = runTest {
        val store = CardMemoryStore()
        val repository = OfflineFirstFinanceRepository(store)
        repository.saveWallet(UserId(OWNER), bankDraft(), DEVICE, NOW).getOrThrow()

        val saved = repository.saveCreditCard(
            UserId(OWNER),
            draft(paymentSourceWalletId = PAYMENT_WALLET_ID),
            DEVICE,
            LATER,
        ).getOrThrow()

        assertEquals(CARD_WALLET_ID, saved.wallet.id)
        assertEquals(PROFILE_ID, saved.profile.id)
        assertEquals(PAYMENT_WALLET_ID, saved.profile.paymentSourceWalletId)
        assertEquals(2, store.cardCommitCount)
        assertEquals(
            setOf(CloudEntity.LEDGER_WALLET, CloudEntity.CREDIT_CARD_PROFILE),
            store.outbox.values.filter { it.recordId in setOf(CARD_WALLET_ID, PROFILE_ID) }.map { it.entity }.toSet(),
        )
        assertEquals(1, repository.observeCreditCardProfiles(UserId(OWNER)).firstValue().size)
        assertTrue(repository.observeCreditCardProfiles(UserId(OTHER_OWNER)).firstValue().isEmpty())
    }

    @Test
    fun `edit preserves independent base versions and sends explicit null for cleared fields`() = runTest {
        val store = CardMemoryStore()
        val repository = OfflineFirstFinanceRepository(store)
        val original = repository.saveCreditCard(UserId(OWNER), draft(notes = "memo"), DEVICE, NOW).getOrThrow()
        store.seed(original.wallet.copy(syncVersion = 4).toCloudRecord())
        store.seed(original.profile.copy(syncVersion = 9).toCloudRecord())

        repository.saveCreditCard(UserId(OWNER), draft(notes = ""), DEVICE, LATER).getOrThrow()

        assertEquals(4L, store.outbox.getValue(key(CloudEntity.LEDGER_WALLET, CARD_WALLET_ID)).baseVersion)
        val profileMutation = store.outbox.getValue(key(CloudEntity.CREDIT_CARD_PROFILE, PROFILE_ID))
        assertEquals(9L, profileMutation.baseVersion)
        assertEquals(JsonNull, profileMutation.payload?.get("notes"))
    }

    @Test
    fun `payment source lookup is owner scoped`() = runTest {
        val store = CardMemoryStore()
        val repository = OfflineFirstFinanceRepository(store)
        store.seed(bank(PAYMENT_WALLET_ID, OTHER_OWNER).toCloudRecord())

        val failure = repository.saveCreditCard(
            UserId(OWNER),
            draft(paymentSourceWalletId = PAYMENT_WALLET_ID),
            DEVICE,
            NOW,
        )

        assertTrue(failure.isFailure)
        assertEquals(0, store.cardCommitCount)
    }

    private fun draft(
        paymentSourceWalletId: String? = null,
        notes: String? = null,
    ) = CreditCardDraft(
        walletId = CARD_WALLET_ID,
        profileId = PROFILE_ID,
        name = "Travel Card",
        issuerName = "Mistia Bank",
        network = CreditCardNetwork.VISA,
        last4 = "1234",
        creditLimitMinor = 350_000,
        statementClosingDay = 10,
        paymentDueDay = 26,
        notes = notes,
        paymentSourceWalletId = paymentSourceWalletId,
        currencyCode = "JPY",
    )

    private fun bankDraft() = WalletDraft(
        id = PAYMENT_WALLET_ID,
        name = "Bank",
        kind = WalletKind.BANK,
        currencyCode = "JPY",
        institutionDisplayName = "Bank",
    )

    private fun bank(id: String, owner: String) = LedgerWalletRecord(
        id = id,
        ownerUserId = owner,
        name = "Bank",
        kindWireValue = WalletKind.BANK.wireValue,
        iconSymbolName = WalletKind.BANK.defaultIcon,
        iconColorHex = WalletKind.BANK.defaultColorHex,
        currencyCode = "JPY",
        openingBalanceMinor = 0,
        institutionDisplayName = "Bank",
        institutionPresetKey = null,
        sortOrder = 0,
        isArchived = false,
        archivedAt = null,
        createdAt = NOW,
        updatedAt = NOW,
        deletedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = DEVICE,
        systemPurposeRawValue = null,
        investmentLinkedWalletId = null,
    )

    private class CardMemoryStore : LocalStore {
        private val records = MutableStateFlow<Map<Triple<String, String, String>, CloudRecord>>(emptyMap())
        val outbox = linkedMapOf<Triple<String, String, String>, PendingMutation>()
        var cardCommitCount = 0

        override fun observe(entity: String, ownerUserId: UserId): Flow<List<CloudRecord>> = records.map { rows ->
            rows.values.filter { it.ownerUserId == ownerUserId.value && it.entity == entity && it.deletedAt == null }
        }
        override fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>> = MutableStateFlow(emptyList())
        override suspend fun record(ownerUserId: UserId, entity: String, recordId: String): CloudRecord? =
            records.value[Triple(ownerUserId.value, entity, recordId)]
        override suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation) {
            seed(record)
            outbox[key(mutation.entity, mutation.recordId)] = mutation
        }
        override suspend fun commitCreditCardMutation(
            walletRecord: CloudRecord,
            walletMutation: PendingMutation,
            profileRecord: CloudRecord,
            profileMutation: PendingMutation,
        ) {
            cardCommitCount += 2
            commitMutation(walletRecord, walletMutation)
            commitMutation(profileRecord, profileMutation)
        }
        override suspend fun pendingMutations(
            ownerUserId: UserId,
            entity: CloudEntity,
            dueAtEpochMillis: Long,
            limit: Int,
        ): List<QueuedMutation> = emptyList()
        override suspend fun acknowledgeMutation(mutation: QueuedMutation, remoteRecord: CloudRecord) = false
        override suspend fun recordMutationFailure(
            mutation: QueuedMutation,
            nextAttemptAtEpochMillis: Long,
            errorCode: String,
        ) = false
        override suspend fun replacePullSnapshot(ownerUserId: UserId, entity: String, records: List<CloudRecord>) = Unit
        override suspend fun pendingMutationRecordIds(ownerUserId: UserId, entity: String) = emptySet<String>()
        override suspend fun clearAccount(ownerUserId: UserId) = Unit

        fun seed(record: CloudRecord) {
            records.value = records.value + (Triple(record.ownerUserId, record.entity, record.id) to record)
        }
    }

    private suspend fun <T> Flow<List<T>>.firstValue(): List<T> = first()

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val OTHER_OWNER = "66666666-6666-6666-6666-666666666666"
        const val CARD_WALLET_ID = "22222222-2222-2222-2222-222222222222"
        const val PROFILE_ID = "33333333-3333-3333-3333-333333333333"
        const val PAYMENT_WALLET_ID = "44444444-4444-4444-4444-444444444444"
        const val DEVICE = "55555555-5555-5555-5555-555555555555"
        const val NOW = "2026-09-23T10:00:00.000Z"
        const val LATER = "2026-09-23T11:00:00.000Z"
        fun key(entity: CloudEntity, id: String) = Triple(OWNER, entity.table, id)
    }
}
