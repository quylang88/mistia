package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class SystemCategoryBootstrapTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("22222222-2222-2222-2222-222222222222")
    private val device="33333333-3333-3333-3333-333333333333"
    private val now="2026-10-13T00:00:00Z"
    private val store=BudgetMemoryStore()
    private val repo=OfflineFirstFinanceRepository(store)
    private val catalog=SystemCategoryCatalog.parse("""[
      {"id":"parent_expense_housing","kind":"expense","active":true,"icon":"mistia.category.parent.expense.housing","fallbackIcon":"house.fill","color":"#FF8A4C","translations":{"vi":"Nhà","en":"Home","ja":"住まい"},"aliases":[],"children":[
        {"id":"rent","active":true,"icon":"mistia.category.expense.home.rent","fallbackIcon":"house.fill","color":"#FF8A4C","translations":{"vi":"Thuê nhà","en":"Rent","ja":"家賃"},"aliases":[]},
        {"id":"internet","active":true,"icon":"mistia.category.expense.home.internet","fallbackIcon":"wifi","color":"#5B7BFF","translations":{"vi":"Internet","en":"Internet","ja":"インターネット"},"aliases":[]}
      ]}
    ]""")
    private fun seed(key:String)=catalog.definitions.single {it.key==key}.seedRecord(owner,
        if(key=="parent_expense_housing") null else SystemCategoryIdentity.cloudId("parent_expense_housing",owner),device,now)
    private suspend fun put(row:TransactionCategoryRecord)=store.commitMutation(row.toCloudRecord(),row.bootstrapMutation())

    @Test fun `missing defaults commit atomically with cloud owner IDs and no duplicate second bootstrap`()=runTest {
        val result=repo.ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow()
        assertEquals(3,result.createdCount);assertEquals(1,store.batches.size)
        val rows=repo.observeCategories(owner).first()
        assertEquals(3,rows.size)
        val parent=rows.single {it.systemKey=="parent_expense_housing"}
        assertEquals(SystemCategoryIdentity.cloudId("parent_expense_housing",owner),parent.id)
        assertTrue(rows.filter {it.hierarchyRole==CategoryHierarchyRole.CHILD}.all {it.parentCategoryId==parent.id})
        assertTrue(rows.all {it.isSystem && it.syncVersion==0L && it.ownerUserId==owner.value})
        assertEquals(3,store.outboxRows(owner.value).size)
        assertEquals(0,repo.ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow().createdCount)
        assertEquals(1,store.batches.size)
    }
    @Test fun `existing custom metadata archive versions and legacy IDs are preserved while children link existing parent`()=runTest {
        val parent=seed("parent_expense_housing").copy(id="44444444-4444-4444-4444-444444444444",name="My home",nameEnglish="Personal",isFavorite=true,syncVersion=9007199254740993L)
        put(parent)
        val archived=seed("rent").copy(name="Custom rent",isArchived=true,parentCategoryId=parent.id)
        put(archived)
        assertEquals(1,repo.ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow().createdCount)
        assertEquals(parent,TransactionCategoryRecord.fromCloudRecord(store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,parent.id)!!))
        assertEquals(archived,TransactionCategoryRecord.fromCloudRecord(store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,archived.id)!!))
        assertEquals(parent.id,repo.observeCategories(owner).first().single {it.systemKey=="internet"}.parentCategoryId)
    }
    @Test fun `arbitrary legacy tombstone keys prevent resurrection and deleted parent prevents new descendants`()=runTest {
        val leaf=seed("rent").copy(id="55555555-5555-5555-5555-555555555555",deletedAt=now)
        put(leaf)
        val result=repo.ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow()
        assertEquals(2,result.createdCount);assertTrue("rent" in result.preservedTombstoneKeys)
        assertNull(store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,SystemCategoryIdentity.cloudId("rent",owner)))
        val separate=BudgetMemoryStore();val repository=OfflineFirstFinanceRepository(separate)
        val parent=seed("parent_expense_housing").copy(deletedAt=now)
        separate.commitMutation(parent.toCloudRecord(),parent.bootstrapMutation())
        assertEquals(0,repository.ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow().createdCount)
    }
    @Test fun `canonical identity occupied by unrelated user row aborts the entire planned batch`()=runTest {
        val occupied=seed("internet").copy(systemKey=null,isSystem=false,name="Custom category")
        put(occupied)
        assertTrue(repo.ensureDefaultSystemCategories(owner,catalog,device,now).isFailure)
        assertEquals(listOf(occupied),repo.observeCategories(owner).first())
        assertEquals(1,store.outboxRows(owner.value).size)
    }
    @Test fun `duplicate system keys reported without rewriting existing records or linked identities`()=runTest {
        val a=seed("rent")
        val b=a.copy(id="66666666-6666-6666-6666-666666666666",name="Legacy duplicate")
        put(a);put(b)
        val result=repo.ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow()
        assertTrue("rent" in result.duplicateSystemKeys)
        assertEquals(a,TransactionCategoryRecord.fromCloudRecord(store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,a.id)!!))
        assertEquals(b,TransactionCategoryRecord.fromCloudRecord(store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,b.id)!!))
    }
    @Test fun `different accounts have independent IDs and forged payload scope aborts without writes`()=runTest {
        repo.ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow()
        repo.ensureDefaultSystemCategories(other,catalog,device,now).getOrThrow()
        val a=repo.observeCategories(owner).first();val b=repo.observeCategories(other).first()
        assertTrue(a.map {it.id}.intersect(b.map {it.id}.toSet()).isEmpty())
        val forged=seed("rent").copy(ownerUserId=other.value)
        store.commitMutation(forged.toCloudRecord().copy(ownerUserId=owner.value),forged.bootstrapMutation().copy(subjectUserId=owner.value))
        val before=store.outboxRows(owner.value)
        assertTrue(repo.ensureDefaultSystemCategories(owner,catalog,device,now).isFailure)
        assertEquals(before,store.outboxRows(owner.value))
    }
    @Test fun `failure and cancellation leave no partial default batch`()=runTest {
        store.failBatch=true
        assertTrue(repo.ensureDefaultSystemCategories(owner,catalog,device,now).isFailure)
        assertTrue(repo.observeCategories(owner).first().isEmpty());assertTrue(store.outboxRows(owner.value).isEmpty())
        val cancelling=object:LocalStore by store {override suspend fun commitMissingSystemCategories(mutations:List<Pair<CloudRecord,PendingMutation>>) {throw CancellationException("cancel")}}
        try {OfflineFirstFinanceRepository(cancelling).ensureDefaultSystemCategories(owner,catalog,device,now);fail("cancel swallowed")} catch(expected:CancellationException) {}
    }
    @Test fun `concurrent bootstrap through same repository only creates one batch`()=runTest {
        val a=async {repo.ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow().createdCount}
        val b=async {repo.ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow().createdCount}
        assertEquals(listOf(0,3),listOf(a.await(),b.await()).sorted())
        assertEquals(1,store.batches.size)
    }
    @Test fun `legitimate foreign viewer cache does not block self bootstrap or get overwritten`()=runTest {
        val foreign=catalog.definitions.single {it.key=="rent"}.seedRecord(other,SystemCategoryIdentity.cloudId("parent_expense_housing",other),device,now)
        store.replacePullSnapshot(owner,CloudEntity.TRANSACTION_CATEGORY.table,listOf(foreign.toCloudRecord().copy(ownerUserId=owner.value)))
        assertEquals(3,repo.ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow().createdCount)
        assertEquals(foreign,TransactionCategoryRecord.fromCloudRecord(store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,foreign.id)!!))
        assertEquals(3,store.outboxRows(owner.value).size)
    }
    @Test fun `short form owner UUID rejected without creating another account scope`()=runTest {
        assertTrue(repo.ensureDefaultSystemCategories(UserId("1-1-1-1-1"),catalog,device,now).isFailure)
    }
    @Test fun `foreign viewer payload with newer schema cannot block self defaults`()=runTest {
        val foreign=catalog.definitions.single {it.key=="rent"}.seedRecord(other,SystemCategoryIdentity.cloudId("parent_expense_housing",other),device,now)
        val row=foreign.toCloudRecord().copy(ownerUserId=owner.value,payload=kotlinx.serialization.json.JsonObject(foreign.toPayload()+("name" to kotlinx.serialization.json.JsonObject(emptyMap()))))
        store.replacePullSnapshot(owner,CloudEntity.TRANSACTION_CATEGORY.table,listOf(row))
        assertEquals(3,repo.ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow().createdCount)
        assertEquals(row,store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,foreign.id))
    }
    @Test fun `remote row arriving after snapshot cannot be overwritten by default batch`()=runTest {
        val remote=seed("rent").copy(name="Remote customization",syncVersion=7)
        val racing=object:LocalStore by store {
            override suspend fun commitMissingSystemCategories(mutations:List<Pair<CloudRecord,PendingMutation>>) {
                store.replacePullSnapshot(owner,CloudEntity.TRANSACTION_CATEGORY.table,listOf(remote.toCloudRecord()))
                store.commitMissingSystemCategories(mutations)
            }
        }
        assertTrue(OfflineFirstFinanceRepository(racing).ensureDefaultSystemCategories(owner,catalog,device,now).isFailure)
        assertEquals(remote,TransactionCategoryRecord.fromCloudRecord(store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,remote.id)!!))
        assertTrue(store.outboxRows(owner.value).isEmpty())
    }
}
