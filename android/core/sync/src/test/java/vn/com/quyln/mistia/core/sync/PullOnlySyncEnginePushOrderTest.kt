package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.AuthRepository
import vn.com.quyln.mistia.core.model.AuthSession
import vn.com.quyln.mistia.core.model.AuthState
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.EntityCount
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.PendingMutation
import vn.com.quyln.mistia.core.model.QueuedMutation
import vn.com.quyln.mistia.core.model.RemotePage
import vn.com.quyln.mistia.core.model.RemoteStore
import vn.com.quyln.mistia.core.model.UserId

class PullOnlySyncEnginePushOrderTest {
    @Test
    fun `sync pushes category wallet card profile then transaction before pull`() = runTest {
        val events = mutableListOf<String>()
        val category = RecordingPushCoordinator(CloudEntity.TRANSACTION_CATEGORY, events)
        val wallet = RecordingPushCoordinator(CloudEntity.LEDGER_WALLET, events)
        val card = RecordingPushCoordinator(CloudEntity.CREDIT_CARD_PROFILE, events)
        val transaction = RecordingPushCoordinator(CloudEntity.LEDGER_TRANSACTION, events)
        val remote = object : RemoteStore {
            override suspend fun pullPage(
                table: String,
                accessToken: String,
                ownerUserId: UserId,
                offset: Int,
                limit: Int,
            ): RemotePage {
                if (offset == 0) events.add("pull:$table")
                return RemotePage(emptyList(), null)
            }
        }
        val engine = PullOnlySyncEngine(
            appContext = null,
            authRepository = SignedInAuthRepository(),
            localStore = EmptyLocalStore(),
            remoteStore = remote,
            pushCoordinators = listOf(transaction, card, wallet, category),
        )

        val result = engine.syncNow()

        assertTrue(result.isSuccess)
        assertEquals("push:transaction_categories", events[0])
        assertEquals("push:ledger_wallets", events[1])
        assertEquals("push:credit_card_profiles", events[2])
        assertEquals("push:ledger_transactions", events[3])
        assertEquals("pull:transaction_categories", events[4])
    }

    private class RecordingPushCoordinator(
        override val entity: CloudEntity,
        private val events: MutableList<String>,
    ) : DomainPushCoordinator {
        override suspend fun pushPending(ownerUserId: UserId, accessToken: String): DomainPushSummary {
            events.add("push:${entity.table}")
            return DomainPushSummary()
        }
    }

    private class SignedInAuthRepository : AuthRepository {
        private val session = AuthSession(UserId(OWNER), null, TOKEN, "refresh", Long.MAX_VALUE)
        override val state: StateFlow<AuthState> = MutableStateFlow(AuthState.SignedIn(session))
        override suspend fun restore() = Unit
        override suspend fun signIn(email: String, password: String) = Result.success(session)
        override suspend fun signUp(email: String, password: String, displayName: String) = Result.success(session)
        override suspend fun resendConfirmation(email: String) = Result.success(Unit)
        override suspend fun sendPasswordReset(email: String) = Result.success(Unit)
        override suspend fun exchangeGoogleIdToken(idToken: String, nonce: String?) = Result.success(session)
        override suspend fun refreshIfNeeded() = Result.success(session)
        override suspend fun signOut(clearLocalSession: Boolean) = Unit
    }

    private class EmptyLocalStore : LocalStore {
        override fun observe(entity: String, ownerUserId: UserId): Flow<List<CloudRecord>> =
            MutableStateFlow(emptyList())
        override fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>> =
            MutableStateFlow(emptyList())
        override suspend fun record(ownerUserId: UserId, entity: String, recordId: String) = null
        override suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation) = Unit
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
    }

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val TOKEN = "access-token"
    }
}
