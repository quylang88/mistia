package vn.com.quyln.mistia.core.database

import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class RecurringBillRepositoryTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="22222222-2222-2222-2222-222222222222"
    private val id="33333333-3333-3333-3333-333333333333"
    private val zone=ZoneId.of("Asia/Tokyo")
    private val now="2026-10-13T00:00:00Z"
    private val later="2026-11-13T00:00:00Z"
    private val store=BudgetMemoryStore()
    private val repo=OfflineFirstFinanceRepository(store,zone)
    private var prepared:RecurringBillDraft?=null
    private suspend fun draft():RecurringBillDraft {
        prepared?.let { return it }
        val parent=repo.saveCategory(owner,CategoryDraft(name="Home",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,now).getOrThrow()
        val child=repo.saveCategory(owner,CategoryDraft(name="Internet",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,now).getOrThrow()
        val wallet=repo.saveWallet(owner,WalletDraft(name="Cash",kind=WalletKind.CASH,currencyCode="JPY"),device,now).getOrThrow()
        return RecurringBillDraft("  Internet  ",child.id,5000,wallet.id,"JPY",id=id,paymentStartDay=25,dueDay=10,hasDeadline=true,zoneId=zone).also { prepared=it }
    }
    @Test fun `default bill save accepts the device zone changed after repository construction`()=runTest {
        val draft=draft();val original=java.util.TimeZone.getDefault()
        try {
            java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("UTC"))
            val live=OfflineFirstFinanceRepository(store)
            java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone(zone))
            assertEquals("2026-09-30T15:00:00Z",live.saveRecurringBill(owner,draft,device,now).getOrThrow().firstScheduledMonth)
        } finally {java.util.TimeZone.setDefault(original)}
    }
    @Test fun `resume after device zone change uses the new local month at UTC month boundary`()=runTest {
        val bill=repo.saveRecurringBill(owner,draft(),device,now).getOrThrow()
        repo.pauseRecurringBill(owner,RecordId(bill.id),device,now).getOrThrow()
        val original=java.util.TimeZone.getDefault()
        try {
            java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("UTC"))
            val live=OfflineFirstFinanceRepository(store)
            java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone(zone))
            live.resumeRecurringBill(owner,RecordId(bill.id),device,"2026-10-31T15:30:00Z").getOrThrow()
            assertEquals("2026-10-31T15:00:00Z",live.observeRecurringBills(owner).first().single().resumeStartMonth)
        } finally {java.util.TimeZone.setDefault(original)}
    }
    @Test fun `create snapshots category icon and normalizes recurring schedule into one mutation`()=runTest {
        val draft=draft()
        val saved=repo.saveRecurringBill(owner,draft.copy(autoPayEnabled=true,autoPayDay=20),device,now).getOrThrow()
        assertEquals("Internet",saved.name);assertEquals(draft.categoryId,saved.categoryId)
        assertEquals(repo.observeCategories(owner).first().single { it.id==draft.categoryId }.iconSymbolName,saved.iconSymbolName)
        assertEquals("2026-09-30T15:00:00Z",saved.firstScheduledMonth)
        assertEquals(25,saved.autoPayDay);assertNull(saved.paymentStartDate);assertNull(saved.dueDate)
        assertEquals(saved.toPayload(),store.outboxRows(owner.value).single { it.entity==CloudEntity.RECURRING_BILL_PLAN }.payload)
        assertTrue(repo.observeRecurringBills(other).first().isEmpty())
        assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
    }
    @Test fun `next month start optional amount and disabled deadline emit explicit clears`()=runTest {
        val saved=repo.saveRecurringBill(owner,draft().copy(startsNextMonth=true,amountMinor=null,hasDeadline=false,autoPayEnabled=false),device,now).getOrThrow()
        assertEquals("2026-10-31T15:00:00Z",saved.firstScheduledMonth)
        assertEquals(25,saved.dueDay);assertFalse(saved.hasExplicitDueDate!!)
        assertNull(saved.amountMinor);assertNull(saved.autoPayDay);assertNull(saved.autoPayDate)
    }
    @Test fun `disabled deadline ignores stale hidden due day and normalizes to payment start`()=runTest {
        val saved=repo.saveRecurringBill(owner,draft().copy(hasDeadline=false,dueDay=0),device,now).getOrThrow()
        assertEquals(25,saved.dueDay)
        assertFalse(saved.hasExplicitDueDate!!)
    }
    @Test fun `pause and resume retain occurrences and edits keep original version currency and anchor`()=runTest {
        val draft=draft()
        val saved=repo.saveRecurringBill(owner,draft,device,now).getOrThrow().copy(syncVersion=9007199254740993L)
        store.commitMutation(saved.toCloudRecord(),saved.pendingMutation())
        val paid=occurrence(saved,"2026-10","paid")
        store.commitMutation(paid.toCloudRecord(),paid.pendingMutation())
        repo.pauseRecurringBill(owner,RecordId(saved.id),device,now).getOrThrow()
        val paused=repo.observeRecurringBills(owner).first().single()
        assertTrue(paused.isPaused);assertEquals(now,paused.pausedAt);assertNull(paused.resumeStartMonth)
        val edited=repo.saveRecurringBill(owner,draft.copy(editingExisting=true,currencyCode="VND",startsNextMonth=true),device,later).getOrThrow()
        assertTrue(edited.isPaused);assertEquals(now,edited.pausedAt);assertEquals(saved.firstScheduledMonth,edited.firstScheduledMonth)
        assertEquals("JPY",edited.currencyCode);assertEquals(saved.syncVersion,edited.syncVersion);assertEquals(now,edited.createdAt)
        repo.resumeRecurringBill(owner,RecordId(saved.id),device,later).getOrThrow()
        val resumed=repo.observeRecurringBills(owner).first().single()
        assertFalse(resumed.isPaused);assertNull(resumed.pausedAt);assertEquals("2026-10-31T15:00:00Z",resumed.resumeStartMonth)
        assertEquals(listOf(paid),repo.observeDueOccurrences(owner).first())
        assertEquals(saved.syncVersion,store.outboxRows(owner.value).single { it.entity==CloudEntity.RECURRING_BILL_PLAN }.baseVersion)
    }
    @Test fun `one time normalizes local dates clamps auto pay and clears recurrence pause metadata`()=runTest {
        val draft=draft()
        val saved=repo.saveRecurringBill(owner,draft,device,now).getOrThrow()
        repo.pauseRecurringBill(owner,RecordId(saved.id),device,now).getOrThrow()
        val one=repo.saveRecurringBill(owner,draft.copy(editingExisting=true,scheduleKind=BillScheduleKind.ONE_TIME,
            paymentStartDate="2026-10-14T03:00:00Z",dueDate="2026-10-16T03:00:00Z",autoPayEnabled=true,autoPayDate="2026-10-30T00:00:00Z"),device,now).getOrThrow()
        assertFalse(one.isPaused);assertNull(one.pausedAt);assertNull(one.resumeStartMonth);assertNull(one.firstScheduledMonth)
        assertEquals(1,one.frequencyMonths);assertEquals("2026-10-13T15:00:00Z",one.paymentStartDate)
        assertEquals("2026-10-15T15:00:00Z",one.dueDate);assertEquals(one.dueDate,one.autoPayDate);assertNull(one.autoPayDay)
        val before=one.toPayload()
        repo.pauseRecurringBill(owner,RecordId(saved.id),device,later).getOrThrow()
        assertEquals(before,repo.observeRecurringBills(owner).first().single().toPayload())
    }
    @Test fun `archive requires all cycles paid and preserves paid history and original plan version`()=runTest {
        val saved=repo.saveRecurringBill(owner,draft(),device,now).getOrThrow()
        assertTrue(repo.archiveRecurringBill(owner,RecordId(saved.id),device,now).isFailure)
        val skipped=occurrence(saved,"2026-10","skipped")
        store.commitMutation(skipped.toCloudRecord(),skipped.pendingMutation())
        assertTrue(repo.archiveRecurringBill(owner,RecordId(saved.id),device,now).isFailure)
        val paid=skipped.copy(statusWireValue="paid",paidAt=now)
        store.commitMutation(paid.toCloudRecord(),paid.pendingMutation())
        repo.archiveRecurringBill(owner,RecordId(saved.id),device,now).getOrThrow()
        val archived=repo.observeRecurringBills(owner).first().single()
        assertTrue(archived.isArchived);assertEquals(saved.syncVersion,archived.syncVersion)
        assertEquals(listOf(paid),repo.observeDueOccurrences(owner).first())
        assertTrue(repo.saveRecurringBill(owner,draft().copy(editingExisting=true),device,now).isFailure)
    }
    @Test fun `invalid foreign dependencies dates and stale edit leave no bill mutation`()=runTest {
        val draft=draft()
        val foreign=repo.saveWallet(other,WalletDraft(name="Other",kind=WalletKind.CASH,currencyCode="JPY"),device,now).getOrThrow()
        listOf(draft.copy(name=" "),draft.copy(categoryId=null),draft.copy(paymentWalletId=null),draft.copy(paymentWalletId=foreign.id),
            draft.copy(editingExisting=true),draft.copy(paymentStartDay=0),draft.copy(scheduleKind=BillScheduleKind.ONE_TIME,paymentStartDate="2026-10-14T00:00:00Z",dueDate="2026-10-13T00:00:00Z")
        ).forEach { assertTrue(repo.saveRecurringBill(owner,it,device,now).isFailure) }
        assertTrue(repo.saveRecurringBill(other,draft,device,now).isFailure)
        assertTrue(repo.observeRecurringBills(owner).first().isEmpty())
        assertTrue(store.outboxRows(owner.value).none { it.entity==CloudEntity.RECURRING_BILL_PLAN })
    }
    @Test fun `archived preferred references remain editable but cannot be chosen for new bills`()=runTest {
        val draft=draft()
        repo.saveRecurringBill(owner,draft,device,now).getOrThrow()
        repo.archiveWallet(owner,RecordId(draft.paymentWalletId!!),device,now).getOrThrow()
        // Imported archived references can exist even though native category archive blocks active bills.
        val category=repo.observeCategories(owner).first().single { it.id==draft.categoryId }.copy(isArchived=true)
        store.commitMutation(category.toCloudRecord(),PendingMutation(CloudEntity.TRANSACTION_CATEGORY,category.id,owner.value,MutationKind.UPSERT,
            category.toPayload(),now,category.syncVersion,device))
        assertTrue(repo.saveRecurringBill(owner,draft.copy(editingExisting=true),device,now).isSuccess)
        assertTrue(repo.saveRecurringBill(owner,draft.copy(id=null),device,now).isFailure)
    }
    @Test fun `forged payload owner cannot read edit pause resume or archive under viewer envelope`()=runTest {
        val draft=draft()
        val saved=repo.saveRecurringBill(owner,draft,device,now).getOrThrow()
        store.commitMutation(saved.copy(ownerUserId=other.value).toCloudRecord().copy(ownerUserId=owner.value),saved.pendingMutation())
        assertTrue(repo.observeRecurringBills(owner).first().isEmpty())
        assertTrue(repo.saveRecurringBill(owner,draft.copy(editingExisting=true),device,now).isFailure)
        assertTrue(repo.pauseRecurringBill(owner,RecordId(id),device,now).isFailure)
        assertTrue(repo.resumeRecurringBill(owner,RecordId(id),device,now).isFailure)
        assertTrue(repo.archiveRecurringBill(owner,RecordId(id),device,now).isFailure)
    }
    @Test fun `failed batch does not save bill and cancellation propagates`()=runTest {
        val draft=draft();store.failBatch=true
        assertTrue(repo.saveRecurringBill(owner,draft,device,now).isFailure)
        assertTrue(repo.observeRecurringBills(owner).first().isEmpty())
        val cancelling=object:LocalStore by store {
            override suspend fun commitMutations(mutations:List<Pair<CloudRecord,PendingMutation>>) { throw CancellationException("cancel") }
        }
        try { OfflineFirstFinanceRepository(cancelling,zone).saveRecurringBill(owner,draft,device,now);fail("cancellation swallowed") }
        catch(expected:CancellationException) { }
    }
    @Test fun `foreign paid occurrence under viewer envelope cannot unlock archive`()=runTest {
        val saved=repo.saveRecurringBill(owner,draft(),device,now).getOrThrow()
        val foreign=occurrence(saved,"2026-10","paid").copy(ownerUserId=other.value)
        store.commitMutation(foreign.toCloudRecord().copy(ownerUserId=owner.value),foreign.pendingMutation().copy(subjectUserId=owner.value))
        assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
        assertTrue(repo.archiveRecurringBill(owner,RecordId(saved.id),device,now).isFailure)
        assertFalse(repo.observeRecurringBills(owner).first().single().isArchived)
    }
    @Test fun `deleted imported bill cannot resurrect through stale edit or lifecycle actions`()=runTest {
        val draft=draft()
        val saved=repo.saveRecurringBill(owner,draft,device,now).getOrThrow().copy(deletedAt=now)
        store.commitMutation(saved.toCloudRecord(),saved.pendingMutation(MutationKind.DELETE))
        assertTrue(repo.observeRecurringBills(owner).first().isEmpty())
        assertTrue(repo.saveRecurringBill(owner,draft.copy(editingExisting=true),device,later).isFailure)
        assertTrue(repo.pauseRecurringBill(owner,RecordId(saved.id),device,later).isFailure)
        assertTrue(repo.resumeRecurringBill(owner,RecordId(saved.id),device,later).isFailure)
        assertTrue(repo.archiveRecurringBill(owner,RecordId(saved.id),device,later).isFailure)
        assertEquals(MutationKind.DELETE,store.outboxRows(owner.value).single { it.entity==CloudEntity.RECURRING_BILL_PLAN }.kind)
    }
    @Test fun `skip creates exact cycle occurrence without any ledger mutation and undo tombstones it`()=runTest {
        val bill=repo.saveRecurringBill(owner,draft(),device,now).getOrThrow()
        val skipped=repo.skipRecurringBill(owner,RecordId(bill.id),java.time.YearMonth.of(2026,10),device,now).getOrThrow()
        assertEquals("2026-10",skipped.selectedMonthKey)
        assertEquals("2026-11-09T15:00:00Z",skipped.scheduledDate)
        assertEquals("skipped",skipped.statusWireValue)
        assertNull(skipped.amountMinorSnapshot);assertNull(skipped.paidAt);assertNull(skipped.linkedTransactionId)
        assertEquals(1,store.batches.last().size)
        assertFalse(store.outboxRows(owner.value).any {it.entity==CloudEntity.LEDGER_TRANSACTION})
        val repeated=repo.skipRecurringBill(owner,RecordId(bill.id),java.time.YearMonth.of(2026,10),device,later).getOrThrow()
        assertEquals(skipped,repeated)
        repo.undoRecurringBillSkip(owner,RecordId(bill.id),java.time.YearMonth.of(2026,10),device,later).getOrThrow()
        assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
        val tombstone=store.record(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table,skipped.id)!!
        assertEquals(later,tombstone.deletedAt)
        assertEquals(MutationKind.DELETE,store.outboxRows(owner.value).single {it.recordId==skipped.id}.kind)
        val next=repo.skipRecurringBill(owner,RecordId(bill.id),java.time.YearMonth.of(2026,10),device,later).getOrThrow()
        assertNotEquals(skipped.id,next.id)
    }
    @Test fun `skip cannot alter paid occurrence foreign owner or unscheduled paused bill`()=runTest {
        val bill=repo.saveRecurringBill(owner,draft().copy(frequencyMonths=2),device,now).getOrThrow()
        val paid=occurrence(bill,"2026-10","paid").copy(syncVersion=9007199254740993L,linkedTransactionId=id)
        store.commitMutation(paid.toCloudRecord(),paid.pendingMutation())
        assertTrue(repo.skipRecurringBill(owner,RecordId(bill.id),java.time.YearMonth.of(2026,10),device,later).isFailure)
        assertTrue(repo.skipRecurringBill(other,RecordId(bill.id),java.time.YearMonth.of(2026,10),device,later).isFailure)
        assertTrue(repo.skipRecurringBill(owner,RecordId(bill.id),java.time.YearMonth.of(2026,11),device,later).isFailure)
        assertEquals(listOf(paid),repo.observeDueOccurrences(owner).first())
        repo.pauseRecurringBill(owner,RecordId(bill.id),device,now).getOrThrow()
        assertTrue(repo.skipRecurringBill(owner,RecordId(bill.id),java.time.YearMonth.of(2026,12),device,later).isFailure)
    }
    @Test fun `undo skip tombstones every duplicate but preserves paid and other cycles`()=runTest {
        val bill=repo.saveRecurringBill(owner,draft(),device,now).getOrThrow()
        val a=occurrence(bill,"2026-10","skipped").copy(syncVersion=9007199254740993L)
        val b=a.copy(id="88888888-8888-8888-8888-888888888888")
        val otherCycle=a.copy(id="66666666-6666-6666-6666-666666666666",selectedMonthKey="2026-09")
        val paid=a.copy(id="55555555-5555-5555-5555-555555555555",statusWireValue="paid")
        listOf(a,b,otherCycle,paid).forEach {store.commitMutation(it.toCloudRecord(),it.pendingMutation())}
        repo.undoRecurringBillSkip(owner,RecordId(bill.id),java.time.YearMonth.of(2026,10),device,later).getOrThrow()
        assertEquals(setOf(otherCycle.id,paid.id),repo.observeDueOccurrences(owner).first().map {it.id}.toSet())
        assertEquals(2,store.batches.last().size)
        assertEquals(9007199254740993L,store.outboxRows(owner.value).single {it.recordId==a.id}.baseVersion)
    }
    @Test fun `skip batch failure leaves cycle and outbox unchanged`()=runTest {
        val bill=repo.saveRecurringBill(owner,draft(),device,now).getOrThrow()
        store.failBatch=true
        assertTrue(repo.skipRecurringBill(owner,RecordId(bill.id),java.time.YearMonth.of(2026,10),device,now).isFailure)
        assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
        assertFalse(store.outboxRows(owner.value).any {it.entity==CloudEntity.DUE_OCCURRENCE_RECORD})
    }

    @Test fun `occurrence wire identity mismatch cannot retarget skip mutation`()=runTest {
        val bill=repo.saveRecurringBill(owner,draft(),device,now).getOrThrow()
        val pending=occurrence(bill,"2026-10","pending")
        store.replacePullSnapshot(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table,listOf(pending.toCloudRecord().copy(id="88888888-8888-8888-8888-888888888888")))
        assertTrue(repo.skipRecurringBill(owner,RecordId(bill.id),java.time.YearMonth.of(2026,10),device,now).isFailure)
        assertFalse(store.outboxRows(owner.value).any {it.entity==CloudEntity.DUE_OCCURRENCE_RECORD})
    }
    @Test fun `arriving paid cycle aborts skip without erasing synchronized record`()=runTest {
        val bill=repo.saveRecurringBill(owner,draft(),device,now).getOrThrow()
        val paid=occurrence(bill,"2026-10","paid").copy(syncVersion=9)
        val racing=object:LocalStore by store {
            override suspend fun commitBillCycleMutations(bill:CloudRecord,monthKey:String,expectedOccurrences:List<CloudRecord>,mutations:List<Pair<CloudRecord,PendingMutation>>) {
                store.replacePullSnapshot(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table,listOf(paid.toCloudRecord()))
                store.commitBillCycleMutations(bill,monthKey,expectedOccurrences,mutations)
            }
        }
        assertTrue(OfflineFirstFinanceRepository(racing,zone).skipRecurringBill(owner,RecordId(bill.id),java.time.YearMonth.of(2026,10),device,now).isFailure)
        assertEquals(listOf(paid),repo.observeDueOccurrences(owner).first())
        assertFalse(store.outboxRows(owner.value).any {it.entity==CloudEntity.DUE_OCCURRENCE_RECORD})
    }
    @Test fun `foreign viewer occurrence stays intact and cannot be skipped or undone`()=runTest {
        val bill=repo.saveRecurringBill(owner,draft(),device,now).getOrThrow()
        val foreign=occurrence(bill,"2026-10","skipped").copy(ownerUserId=other.value)
        store.replacePullSnapshot(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table,listOf(foreign.toCloudRecord().copy(ownerUserId=owner.value)))
        repo.undoRecurringBillSkip(owner,RecordId(bill.id),java.time.YearMonth.of(2026,10),device,now).getOrThrow()
        val saved=repo.skipRecurringBill(owner,RecordId(bill.id),java.time.YearMonth.of(2026,10),device,now).getOrThrow()
        assertNotEquals(foreign.id,saved.id)
        assertEquals(foreign.toPayload(),store.record(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table,foreign.id)!!.payload)
    }

    @Test fun `stale undo cannot delete skipped history after pause or schedule change`()=runTest {
        val original=draft()
        val bill=repo.saveRecurringBill(owner,original,device,now).getOrThrow()
        val skipped=repo.skipRecurringBill(owner,RecordId(bill.id),java.time.YearMonth.of(2026,10),device,now).getOrThrow()
        repo.pauseRecurringBill(owner,RecordId(bill.id),device,now).getOrThrow()
        assertTrue(repo.undoRecurringBillSkip(owner,RecordId(bill.id),java.time.YearMonth.of(2026,10),device,later).isFailure)
        assertEquals(listOf(skipped),repo.observeDueOccurrences(owner).first())
        repo.resumeRecurringBill(owner,RecordId(bill.id),device,later).getOrThrow()
        assertTrue(repo.undoRecurringBillSkip(owner,RecordId(bill.id),java.time.YearMonth.of(2026,10),device,later).isFailure)
        assertEquals(listOf(skipped),repo.observeDueOccurrences(owner).first())
    }

    @Test fun `new bill cannot select payment wallet with different currency`()=runTest {
        val draft=draft()
        val wallet=repo.saveWallet(owner,WalletDraft(name="VND cash",kind=WalletKind.CASH,currencyCode="VND"),device,now).getOrThrow()
        val failure=repo.saveRecurringBill(owner,draft.copy(paymentWalletId=wallet.id),device,now).exceptionOrNull()
        assertTrue(failure is RecurringBillValidationException)
        assertEquals("WALLET_CURRENCY_MISMATCH",(failure as RecurringBillValidationException).reason.name)
        assertTrue(repo.observeRecurringBills(owner).first().isEmpty())
        assertFalse(store.outboxRows(owner.value).any {it.entity==CloudEntity.RECURRING_BILL_PLAN})
        assertTrue(repo.saveRecurringBill(owner,draft.copy(paymentWalletId=wallet.id,currencyCode="VND"),device,now).isSuccess)
    }
    @Test fun `editing bill cannot change its retained currency to bypass wallet rule`()=runTest {
        val draft=draft()
        val saved=repo.saveRecurringBill(owner,draft,device,now).getOrThrow()
        val wallet=repo.saveWallet(owner,WalletDraft(name="VND cash",kind=WalletKind.CASH,currencyCode="VND"),device,now).getOrThrow()
        assertTrue(repo.saveRecurringBill(owner,draft.copy(editingExisting=true,paymentWalletId=wallet.id,currencyCode="VND"),device,later).isFailure)
        assertEquals(saved,repo.observeRecurringBills(owner).first().single())
    }

    private fun occurrence(bill:RecurringBillPlanRecord,month:String,status:String)=DueOccurrenceRecord(
        "77777777-7777-7777-7777-777777777777",owner.value,"recurringBill",bill.id,month,now,bill.amountMinor,status,
        null,null,now,now,null,0,device)
}
