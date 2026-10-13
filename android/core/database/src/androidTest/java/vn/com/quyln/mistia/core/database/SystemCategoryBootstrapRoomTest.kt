package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class SystemCategoryBootstrapRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("22222222-2222-2222-2222-222222222222")
    private val device="33333333-3333-3333-3333-333333333333"
    private val now="2026-10-13T00:00:00Z"
    private fun catalog()=InstrumentationRegistry.getInstrumentation().context.assets.open("MistiaSystemCategories.json").bufferedReader().use {SystemCategoryCatalog.parse(it.readText())}

    @Test fun fullCatalogReopenKeepsTombstonesCustomMetadataAndSeparateOwnerBatches()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val name="bootstrap-${UUID.randomUUID()}.db"
        var db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).allowMainThreadQueries().build()
        try {
            val catalog=catalog()
            var store=RoomLocalStore(db)
            var repo=OfflineFirstFinanceRepository(store)
            assertEquals(147,repo.ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow().createdCount)
            val rent=repo.observeCategories(owner).first().single {it.systemKey=="rent"}
                .copy(name="Custom rent",isFavorite=true,deletedAt=now)
            store.commitMutation(rent.toCloudRecord(),rent.bootstrapMutation().copy(kind=MutationKind.DELETE))
            db.close()
            db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).allowMainThreadQueries().build()
            store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)
            assertEquals(0,repo.ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow().createdCount)
            assertEquals(rent,TransactionCategoryRecord.fromCloudRecord(store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,rent.id)!!))
            assertEquals(147,store.recordsIncludingDeleted(owner,CloudEntity.TRANSACTION_CATEGORY.table).size)
            assertEquals(147,repo.observeBudgetCategoryMetadata(owner).first().size)
            assertEquals(146,repo.observeBudgetCategories(owner).first().size)
            assertEquals(rent,repo.observeBudgetCategoryMetadata(owner).first().single {it.id==rent.id})
            assertEquals(147,store.pendingMutations(owner,CloudEntity.TRANSACTION_CATEGORY,Long.MAX_VALUE,500).size)
            assertEquals(147,repo.ensureDefaultSystemCategories(other,catalog,device,now).getOrThrow().createdCount)
            val a=store.recordsIncludingDeleted(owner,CloudEntity.TRANSACTION_CATEGORY.table).map {it.id}.toSet()
            val b=store.recordsIncludingDeleted(other,CloudEntity.TRANSACTION_CATEGORY.table).map {it.id}.toSet()
            assertTrue(a.intersect(b).isEmpty())
        } finally {db.close();context.deleteDatabase(name)}
    }
    @Test fun invalidSecondMutationRollsBackWholeDefaultCatalogBatch()=runTest {
        val db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        try {
            val store=RoomLocalStore(db)
            val corrupting=object:LocalStore by store {
                override suspend fun commitMissingSystemCategories(mutations:List<Pair<CloudRecord,PendingMutation>>) {
                    store.commitMissingSystemCategories(mutations.mapIndexed {index,pair -> if(index==1) pair.first to pair.second.copy(payload=null) else pair})
                }
            }
            assertTrue(OfflineFirstFinanceRepository(corrupting).ensureDefaultSystemCategories(owner,catalog(),device,now).isFailure)
            assertTrue(store.recordsIncludingDeleted(owner,CloudEntity.TRANSACTION_CATEGORY.table).isEmpty())
            assertTrue(store.pendingMutations(owner,CloudEntity.TRANSACTION_CATEGORY,Long.MAX_VALUE,500).isEmpty())
        } finally {db.close()}
    }
    @Test fun arrivingLegacySystemKeyAbortsBatchThenRetryPreservesRemoteCustomization()=runTest {
        val db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        try {
            val store=RoomLocalStore(db)
            val catalog=catalog()
            val definition=catalog.activeDefinitions.first {it.parentKey==null}
            val remote=definition.seedRecord(owner,null,device,now).copy(id=UUID.randomUUID().toString(),name="Remote custom parent",syncVersion=7)
            val racing=object:LocalStore by store {
                override suspend fun commitMissingSystemCategories(mutations:List<Pair<CloudRecord,PendingMutation>>) {
                    store.replacePullSnapshot(owner,CloudEntity.TRANSACTION_CATEGORY.table,listOf(remote.toCloudRecord()))
                    store.commitMissingSystemCategories(mutations)
                }
            }
            assertTrue(OfflineFirstFinanceRepository(racing).ensureDefaultSystemCategories(owner,catalog,device,now).isFailure)
            assertEquals(1,store.recordsIncludingDeleted(owner,CloudEntity.TRANSACTION_CATEGORY.table).size)
            assertTrue(store.pendingMutations(owner,CloudEntity.TRANSACTION_CATEGORY,Long.MAX_VALUE,500).isEmpty())
            assertEquals(146,OfflineFirstFinanceRepository(store).ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow().createdCount)
            assertEquals(remote,TransactionCategoryRecord.fromCloudRecord(store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,remote.id)!!))
            assertEquals(147,store.recordsIncludingDeleted(owner,CloudEntity.TRANSACTION_CATEGORY.table).size)
        } finally {db.close()}
    }
}
