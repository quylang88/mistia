package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test
import vn.com.quyln.mistia.core.model.*
import kotlinx.serialization.json.*
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
    fun `sync orders existing domains then investment channels assets and trades before pull`() = runTest {
        val events = mutableListOf<String>()
        val category = RecordingPushCoordinator(CloudEntity.TRANSACTION_CATEGORY, events)
        val wallet = RecordingPushCoordinator(CloudEntity.LEDGER_WALLET, events)
        val card = RecordingPushCoordinator(CloudEntity.CREDIT_CARD_PROFILE, events)
        val transaction = RecordingPushCoordinator(CloudEntity.LEDGER_TRANSACTION, events)
        val budget = RecordingPushCoordinator(CloudEntity.BUDGET_PLAN, events)
        val savings = RecordingPushCoordinator(CloudEntity.SAVINGS_GOAL, events)
        val due = RecordingPushCoordinator(CloudEntity.DUE_OCCURRENCE_RECORD, events)
        val bill = RecordingPushCoordinator(CloudEntity.RECURRING_BILL_PLAN, events)
        val installment = RecordingPushCoordinator(CloudEntity.INSTALLMENT_PLAN, events)
        val channel = RecordingPushCoordinator(CloudEntity.INVESTMENT_CHANNEL, events)
        val asset = RecordingPushCoordinator(CloudEntity.INVESTMENT_ASSET, events)
        val trade = RecordingPushCoordinator(CloudEntity.INVESTMENT_TRADE, events)
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
            pushCoordinators = listOf(trade, asset, channel, due, installment, bill, savings, budget, transaction, card, wallet, category),
        )

        val result = engine.syncNow()

        assertTrue(result.isSuccess)
        assertEquals("push:transaction_categories", events[0])
        assertEquals("push:ledger_wallets", events[1])
        assertEquals("push:credit_card_profiles", events[2])
        assertEquals("push:ledger_transactions", events[3])
        assertEquals("push:budget_plans", events[4])
        assertEquals("push:savings_goals", events[5])
        assertEquals("push:recurring_bill_plans", events[6])
        assertEquals("push:installment_plans", events[7])
        assertEquals("push:due_occurrence_records", events[8])
        assertEquals("push:investment_channels", events[9])
        assertEquals("push:investment_assets", events[10])
        assertEquals("push:investment_trades", events[11])
        assertEquals("pull:transaction_categories", events[12])
    }

    @Test fun `disabled real channel coordinator permits pull without querying an outbox or invoking a writer`()=runTest {
        val local=object:LocalStore by EmptyLocalStore() {
            override suspend fun pendingMutations(ownerUserId:UserId,entity:CloudEntity,dueAtEpochMillis:Long,limit:Int):List<QueuedMutation> = error("Disabled channel must not inspect an outbox")
        }
        val channelRemote=object:RemoteMutationStore {
            override suspend fun fetchRecord(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId):CloudRecord?=error("Disabled channel cannot fetch")
            override suspend fun createRecord(entity:CloudEntity,accessToken:String,ownerUserId:UserId,payload:JsonObject):CloudRecord=error("Disabled channel cannot create")
            override suspend fun conditionalUpdate(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId,expectedVersion:Long,payload:JsonObject):CloudRecord?=error("Disabled channel cannot update")
        }
        val pulled=mutableListOf<String>()
        val remote=object:RemoteStore {
            override suspend fun pullPage(table:String,accessToken:String,ownerUserId:UserId,offset:Int,limit:Int):RemotePage {
                pulled.add(table);return RemotePage(emptyList(),null)
            }
        }
        val channel=InvestmentChannelPushCoordinator(local,channelRemote,false,{error("Disabled channel cannot request a session")})
        assertTrue(PullOnlySyncEngine(null,SignedInAuthRepository(),local,remote,listOf(channel)).syncNow().isSuccess)
        assertEquals(CloudEntity.pullOrder.map{it.table},pulled.take(CloudEntity.entries.size))
    }

    private val maintenanceCatalog=SystemCategoryCatalog.parse("""[
        {"id":"home","kind":"expense","active":true,"icon":"house.fill","fallbackIcon":"house.fill","color":"#123456",
        "translations":{"vi":"Nhà","en":"Home","ja":"家"},"aliases":[],"children":[]}
    ]""")
    private val maintenanceDevice="22222222-2222-2222-2222-222222222222"
    @Test fun `syncNow and pullAll reconcile actual raw category rows after every table finishes`()=runTest {
        for(pullOnly in listOf(false,true)) {
            val events=mutableListOf<String>();val received=mutableListOf<CloudRecord>()
            val raw=maintenanceCatalog.activeDefinitions.single().seedRecord(UserId(OWNER),null,maintenanceDevice,"2026-10-14T00:00:00Z").copy(syncVersion=7,name="Remote raw").toCloudRecord()
            val cached=TransactionCategoryRecord.fromCloudRecord(raw).copy(name="Cached local").toCloudRecord()
            val local=object:LocalStore by EmptyLocalStore() {
                override suspend fun categoryReferenceSnapshot(owner:UserId)=CategoryReferenceSnapshot(owner,
                    categoryReferenceEntities.associateWith {if(it==CloudEntity.TRANSACTION_CATEGORY) listOf(cached) else emptyList()},emptyList(),emptyList())
                override suspend fun commitObservedSystemCategoryMaintenance(expected:CategoryReferenceSnapshot,key:String,remote:List<CloudRecord>,catalog:SystemCategoryCatalog,deviceId:String,now:String):Boolean {
                    events.add("maintenance");received+=remote
                    planObservedSystemCategoryMaintenance(expected,key,remote,catalog,deviceId,now)
                    return true
                }
            }
            val remote=object:RemoteStore {
                override suspend fun pullPage(table:String,accessToken:String,ownerUserId:UserId,offset:Int,limit:Int):RemotePage {
                    events.add("pull:$table")
                    return RemotePage(if(table==CloudEntity.TRANSACTION_CATEGORY.table) listOf(raw.payload) else emptyList(),null)
                }
            }
            val engine=PullOnlySyncEngine(null,SignedInAuthRepository(),local,remote,emptyList(),
                categoryMaintenanceCoordinator=CategoryMaintenanceCoordinator(local,maintenanceCatalog,{maintenanceDevice}) {0L})
            val result=if(pullOnly) engine.pullAll() else engine.syncNow()
            assertTrue(result.isSuccess)
            assertEquals(listOf(raw),received)
            assertEquals("maintenance",events.last())
            assertEquals(CloudEntity.entries.size+ReadOnlyCloudCollection.entries.size+1,events.size)
        }
    }
    @Test fun `incomplete pull never runs category maintenance from a partial snapshot`()=runTest {
        val events=mutableListOf<String>()
        val raw=maintenanceCatalog.activeDefinitions.single().seedRecord(UserId(OWNER),null,maintenanceDevice,"2026-10-14T00:00:00Z").copy(syncVersion=7).toCloudRecord()
        val local=object:LocalStore by EmptyLocalStore() {
            override suspend fun categoryReferenceSnapshot(owner:UserId):CategoryReferenceSnapshot {
                events.add("maintenance")
                error("No maintenance until full pull")
            }
        }
        val remote=object:RemoteStore {
            override suspend fun pullPage(table:String,accessToken:String,ownerUserId:UserId,offset:Int,limit:Int):RemotePage {
                if(table==CloudEntity.BUDGET_PLAN.table) throw java.io.IOException("interrupted pull")
                return RemotePage(if(table==CloudEntity.TRANSACTION_CATEGORY.table) listOf(raw.payload) else emptyList(),null)
            }
        }
        val engine=PullOnlySyncEngine(null,SignedInAuthRepository(),local,remote,emptyList(),
            categoryMaintenanceCoordinator=CategoryMaintenanceCoordinator(local,maintenanceCatalog,{maintenanceDevice}))
        assertTrue(engine.syncNow().isFailure)
        assertTrue(events.isEmpty())
    }
    @Test fun `invalid pull pagination fails immediately before category maintenance`()=runTest {
        val raw=maintenanceCatalog.activeDefinitions.single().seedRecord(UserId(OWNER),null,maintenanceDevice,"2026-10-14T00:00:00Z").toPayload()
        for(page in listOf(RemotePage(listOf(raw),0),RemotePage(listOf(raw),2),RemotePage(emptyList(),1))) {
            var calls=0
            val remote=object:RemoteStore {
                override suspend fun pullPage(table:String,accessToken:String,ownerUserId:UserId,offset:Int,limit:Int):RemotePage {
                    calls++
                    check(calls==1) {"Repeated invalid pagination"}
                    return page
                }
            }
            val engine=PullOnlySyncEngine(null,SignedInAuthRepository(),EmptyLocalStore(),remote,emptyList())
            val result=engine.pullAll()
            assertTrue(result.isFailure)
            assertEquals("Invalid pull pagination",result.exceptionOrNull()!!.message)
            assertEquals(1,calls)
        }
    }
    @Test fun `pull cancellation propagates from syncNow and pullAll without maintenance`()=runTest {
        for(pullOnly in listOf(false,true)) {
            var maintenanceCalls=0
            val local=object:LocalStore by EmptyLocalStore() {
                override suspend fun categoryReferenceSnapshot(owner:UserId):CategoryReferenceSnapshot {
                    maintenanceCalls++
                    error("Cancelled pull cannot maintain categories")
                }
            }
            val remote=object:RemoteStore {
                override suspend fun pullPage(table:String,accessToken:String,ownerUserId:UserId,offset:Int,limit:Int):RemotePage =
                    throw kotlinx.coroutines.CancellationException("cancelled pull")
            }
            val engine=PullOnlySyncEngine(null,SignedInAuthRepository(),local,remote,emptyList(),
                categoryMaintenanceCoordinator=CategoryMaintenanceCoordinator(local,maintenanceCatalog,{maintenanceDevice}))
            val failure=runCatching {if(pullOnly) engine.pullAll() else engine.syncNow()}.exceptionOrNull()
            assertTrue(failure is kotlinx.coroutines.CancellationException)
            assertEquals(0,maintenanceCalls)
        }
    }
    @Test fun `maintenance hook cancellation propagates through both engine entry points`()=runTest {
        for(pullOnly in listOf(false,true)) {
            var maintenanceCalls=0
            val raw=maintenanceCatalog.activeDefinitions.single().seedRecord(UserId(OWNER),null,maintenanceDevice,"2026-10-14T00:00:00Z").copy(syncVersion=7).toCloudRecord()
            val local=object:LocalStore by EmptyLocalStore() {
                override suspend fun categoryReferenceSnapshot(owner:UserId):CategoryReferenceSnapshot {
                    maintenanceCalls++
                    throw kotlinx.coroutines.CancellationException("cancelled maintenance hook")
                }
            }
            val remote=object:RemoteStore {
                override suspend fun pullPage(table:String,accessToken:String,ownerUserId:UserId,offset:Int,limit:Int)=
                    RemotePage(if(table==CloudEntity.TRANSACTION_CATEGORY.table) listOf(raw.payload) else emptyList(),null)
            }
            val engine=PullOnlySyncEngine(null,SignedInAuthRepository(),local,remote,emptyList(),
                categoryMaintenanceCoordinator=CategoryMaintenanceCoordinator(local,maintenanceCatalog,{maintenanceDevice}))
            val failure=runCatching {if(pullOnly) engine.pullAll() else engine.syncNow()}.exceptionOrNull()
            assertTrue(failure is kotlinx.coroutines.CancellationException)
            assertEquals(1,maintenanceCalls)
        }
    }
    @Test fun `default bootstrap follows complete pull and maintenance for both entry points`()=runTest {
        for(pullOnly in listOf(false,true)) {
            val events=mutableListOf<String>()
            val raw=maintenanceCatalog.activeDefinitions.single().seedRecord(UserId(OWNER),null,maintenanceDevice,"2026-10-14T00:00:00Z").copy(syncVersion=7).toCloudRecord()
            val local=object:LocalStore by EmptyLocalStore() {
                override suspend fun categoryReferenceSnapshot(owner:UserId)=CategoryReferenceSnapshot(owner,
                    categoryReferenceEntities.associateWith {if(it==CloudEntity.TRANSACTION_CATEGORY) listOf(raw) else emptyList()},emptyList(),emptyList())
                override suspend fun commitObservedSystemCategoryMaintenance(expected:CategoryReferenceSnapshot,key:String,remote:List<CloudRecord>,catalog:SystemCategoryCatalog,deviceId:String,now:String):Boolean {
                    events.add("maintenance");return true
                }
            }
            val remote=object:RemoteStore {
                override suspend fun pullPage(table:String,accessToken:String,ownerUserId:UserId,offset:Int,limit:Int):RemotePage {
                    events.add("pull:$table")
                    return RemotePage(if(table==CloudEntity.TRANSACTION_CATEGORY.table) listOf(raw.payload) else emptyList(),null)
                }
            }
            val engine=PullOnlySyncEngine(null,SignedInAuthRepository(),local,remote,emptyList(),
                categoryMaintenanceCoordinator=CategoryMaintenanceCoordinator(local,maintenanceCatalog,{maintenanceDevice}),
                ensureDefaultCategories={owner -> assertEquals(UserId(OWNER),owner);events.add("defaults")})
            val result=if(pullOnly) engine.pullAll() else engine.syncNow()
            assertTrue(result.isSuccess)
            assertEquals(listOf("maintenance","defaults"),events.takeLast(2))
            assertEquals(1,events.count {it=="defaults"})
        }
    }
    @Test fun `retryable offline pull creates missing defaults but retains network failure`()=runTest {
        for(pullOnly in listOf(false,true)) {
            var defaults=0
            val failure=java.io.IOException("offline")
            val remote=object:RemoteStore {
                override suspend fun pullPage(table:String,accessToken:String,ownerUserId:UserId,offset:Int,limit:Int):RemotePage=throw failure
            }
            val engine=PullOnlySyncEngine(null,SignedInAuthRepository(),EmptyLocalStore(),remote,emptyList(),
                ensureDefaultCategories={owner -> assertEquals(UserId(OWNER),owner);defaults++})
            val result=if(pullOnly) engine.pullAll() else engine.syncNow()
            assertTrue(result.isFailure)
            assertEquals(failure,result.exceptionOrNull())
            assertEquals(1,defaults)
        }
    }
    @Test fun `cancelled and permanently invalid pulls never create fallback defaults`()=runTest {
        for(failure in listOf(kotlinx.coroutines.CancellationException("cancelled"),IllegalArgumentException("invalid data"))) {
            var defaults=0
            val remote=object:RemoteStore {
                override suspend fun pullPage(table:String,accessToken:String,ownerUserId:UserId,offset:Int,limit:Int):RemotePage=throw failure
            }
            val engine=PullOnlySyncEngine(null,SignedInAuthRepository(),EmptyLocalStore(),remote,emptyList(),ensureDefaultCategories={defaults++})
            if(failure is kotlinx.coroutines.CancellationException) {
                assertTrue(runCatching {engine.syncNow()}.exceptionOrNull() is kotlinx.coroutines.CancellationException)
            } else assertTrue(engine.syncNow().isFailure)
            assertEquals(0,defaults)
        }
    }
    @Test fun `offline auth refresh failure still bootstraps cached signed in owner`()=runTest {
        for(pullOnly in listOf(false,true)) {
            val failure=java.io.IOException("refresh offline")
            val auth=SignedInAuthRepository().apply {refreshError=failure}
            var defaults=0
            val remote=object:RemoteStore {
                override suspend fun pullPage(table:String,accessToken:String,ownerUserId:UserId,offset:Int,limit:Int):RemotePage=error("Cannot pull without refreshed session")
            }
            val engine=PullOnlySyncEngine(null,auth,EmptyLocalStore(),remote,emptyList(),ensureDefaultCategories={owner ->
                assertEquals(UserId(OWNER),owner);defaults++
            })
            val result=if(pullOnly) engine.pullAll() else engine.syncNow()
            assertEquals(failure,result.exceptionOrNull())
            assertEquals(1,defaults)
        }
    }
    @Test fun `account change during failed or successful pull cannot bootstrap the previous owner`()=runTest {
        for(networkFailure in listOf(false,true)) {
            val auth=SignedInAuthRepository()
            var defaults=0
            val remote=object:RemoteStore {
                override suspend fun pullPage(table:String,accessToken:String,ownerUserId:UserId,offset:Int,limit:Int):RemotePage {
                    auth.state.value=vn.com.quyln.mistia.core.model.AuthState.SignedOut
                    if(networkFailure) throw java.io.IOException("network after signout")
                    return RemotePage(emptyList(),null)
                }
            }
            val engine=PullOnlySyncEngine(null,auth,EmptyLocalStore(),remote,emptyList(),ensureDefaultCategories={defaults++})
            val result=runCatching {engine.syncNow()}
            if(!networkFailure) assertTrue(result.exceptionOrNull() is kotlinx.coroutines.CancellationException)
            assertEquals(0,defaults)
        }
    }
    @Test fun `late pull after signout cannot restore cleared account rows`()=runTest {
        val auth=SignedInAuthRepository()
        var stored=0
        val local=object:LocalStore by EmptyLocalStore() {
            override suspend fun replacePullSnapshot(ownerUserId:UserId,entity:String,records:List<CloudRecord>) {stored++}
        }
        val remote=object:RemoteStore {
            override suspend fun pullPage(table:String,accessToken:String,ownerUserId:UserId,offset:Int,limit:Int):RemotePage {
                auth.state.value=AuthState.SignedOut
                return RemotePage(emptyList(),null)
            }
        }
        val engine=PullOnlySyncEngine(null,auth,local,remote,emptyList())
        assertTrue(runCatching {engine.pullAll()}.exceptionOrNull() is kotlinx.coroutines.CancellationException)
        assertEquals(0,stored)
    }
    @Test fun `disabled family notifications skip inbox pull without clearing cached rows`()=runTest {
        val pulled=mutableListOf<String>();val replaced=mutableListOf<String>()
        val remote=object:RemoteStore {
            override suspend fun pullPage(table:String,accessToken:String,ownerUserId:UserId,offset:Int,limit:Int):RemotePage {
                pulled+=table;return RemotePage(emptyList(),null)
            }
        }
        val local=object:LocalStore by EmptyLocalStore() {
            override suspend fun replacePullSnapshot(ownerUserId:UserId,entity:String,records:List<CloudRecord>) {replaced+=entity}
        }
        val engine=PullOnlySyncEngine(null,SignedInAuthRepository(),local,remote,emptyList(),familyNotificationsEnabled={false})
        assertTrue(engine.pullAll().isSuccess)
        assertFalse(pulled.contains(ReadOnlyCloudCollection.FAMILY_NOTIFICATION.table))
        assertFalse(replaced.contains(ReadOnlyCloudCollection.FAMILY_NOTIFICATION.table))
    }
    @Test fun `family preference disabled while inbox response is in flight refuses cache replacement`()=runTest {
        var enabled=true;val replaced=mutableListOf<String>()
        val remote=object:RemoteStore {
            override suspend fun pullPage(table:String,accessToken:String,ownerUserId:UserId,offset:Int,limit:Int):RemotePage {
                if(table==ReadOnlyCloudCollection.FAMILY_NOTIFICATION.table) enabled=false
                return RemotePage(emptyList(),null)
            }
        }
        val local=object:LocalStore by EmptyLocalStore() {
            override suspend fun replacePullSnapshot(ownerUserId:UserId,entity:String,records:List<CloudRecord>) {replaced+=entity}
        }
        val engine=PullOnlySyncEngine(null,SignedInAuthRepository(),local,remote,emptyList(),familyNotificationsEnabled={enabled})
        assertTrue(engine.pullAll().isSuccess)
        assertFalse(replaced.contains(ReadOnlyCloudCollection.FAMILY_NOTIFICATION.table))
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
        override val state: MutableStateFlow<AuthState> = MutableStateFlow(AuthState.SignedIn(session))
        var refreshError:Throwable?=null
        override suspend fun restore() = Unit
        override suspend fun signIn(email: String, password: String) = Result.success(session)
        override suspend fun signUp(email: String, password: String, displayName: String) = Result.success(session)
        override suspend fun resendConfirmation(email: String) = Result.success(Unit)
        override suspend fun sendPasswordReset(email: String) = Result.success(Unit)
        override suspend fun exchangeGoogleIdToken(idToken: String, nonce: String?) = Result.success(session)
        override suspend fun refreshIfNeeded():Result<AuthSession?> = refreshError?.let {Result.failure(it)} ?: Result.success(session)
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
