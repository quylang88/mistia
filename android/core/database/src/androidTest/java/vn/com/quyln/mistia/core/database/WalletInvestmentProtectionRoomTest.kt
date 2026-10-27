package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class WalletInvestmentProtectionRoomTest {
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="22222222-2222-2222-2222-222222222222"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val now="2026-10-28T00:00:00Z"
    private val later="2026-10-28T00:01:00Z"
    private fun draft()=WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=1000)
    @Before fun setup()=runBlocking {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={owner});repo=OfflineFirstFinanceRepository(store);repo.saveWallet(owner,draft(),device,now).getOrThrow();Unit
    }
    @After fun close(){db.close()}
    private fun cash(n:Int=10,amount:Long=50,subject:UserId=owner,deleted:Boolean=false)=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(n),subject.value,buildJsonObject {
        put("id",id(n));put("user_id",subject.value);put("wallet_id",id(1));put("event_id",id(n+100));put("ledger_transaction_id",id(n+100));put("role_raw_value","cashAccrual")
        put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived");put("accounting_amount_minor",amount);put("accounting_currency_code","JPY");put("amount_minor",amount);put("currency_code","JPY")
        put("created_at",now);put("occurred_at",now);put("updated_at",now);put("deleted_at",if(deleted)JsonPrimitive(now) else JsonNull);put("sync_version",1)
    },now,if(deleted)now else null,1)
    private suspend fun root(link:String?=id(1)) {
        val r=WalletDraft(id=investmentSystemWalletId(owner),name="Investment",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,now).record
        val system=r.copy(payload=JsonObject(r.payload+buildJsonObject{put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",link?.let(::JsonPrimitive) ?: JsonNull)}))
        store.commitMutation(system,PendingMutation(CloudEntity.LEDGER_WALLET,system.id,owner.value,MutationKind.UPSERT,system.payload,now,0,device))
    }
    private suspend fun row()=store.record(owner,CloudEntity.LEDGER_WALLET.table,id(1))!!
    private suspend fun queues()=store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE)
    private suspend fun assertHeld(action:suspend ()->Result<*>) {
        val before=row();val pending=queues();val result=action();assertTrue(result.isFailure)
        assertEquals("INVESTMENT_CASH_PROTECTED",(result.exceptionOrNull() as? WalletValidationException)?.reason?.name)
        assertEquals(before,row());assertEquals(pending,queues())
    }
    @Test fun linkedWalletWithNoCashCannotArchiveOrChangeTypeOrCurrency()=runBlocking {
        root();assertHeld{repo.archiveWallet(owner,RecordId(id(1)),device,later)}
        assertHeld{repo.saveWallet(owner,draft().copy(kind=WalletKind.OTHER),device,later)}
        assertHeld{repo.saveWallet(owner,draft().copy(currencyCode="VND"),device,later)}
    }
    @Test fun nonzeroPositiveNegativeAndHugeCashPreventArchiveWithoutTouchingEitherQueue()=runBlocking {
        for(posts in listOf(listOf(cash()),listOf(cash(amount=-1)),listOf(cash(amount=Long.MAX_VALUE),cash(11,Long.MAX_VALUE),cash(12,2)))) {
            store.replacePullSnapshot(owner,CloudEntity.INVESTMENT_POSTING.table,posts)
            assertHeld{repo.archiveWallet(owner,RecordId(id(1)),device,later)}
        }
    }
    @Test fun currentCashArrivingAfterTheWalletReadStillBlocksDirectAtomicCommit()=runBlocking {
        val before=row();val archived=LedgerWalletRecord.fromCloudRecord(before).toArchiveMutation(device,later)
        store.replacePullSnapshot(owner,CloudEntity.INVESTMENT_POSTING.table,listOf(cash()))
        val pending=queues();val error=runCatching{store.commitMutation(archived.record,archived.pending)}.exceptionOrNull()
        assertEquals("INVESTMENT_CASH_PROTECTED",(error as? WalletValidationException)?.reason?.name);assertEquals(before,row());assertEquals(pending,queues())
    }
    @Test fun currentRootLinkArrivingAfterTheWalletReadAlsoBlocksCurrencyCommit()=runBlocking {
        val before=row();val changed=draft().copy(currencyCode="VND").toMutation(owner,LedgerWalletRecord.fromCloudRecord(before),device,later)
        root();val pending=queues();val error=runCatching{store.commitWalletCurrencyMutation(before,changed.record,changed.pending)}.exceptionOrNull()
        assertEquals("INVESTMENT_CASH_PROTECTED",(error as? WalletValidationException)?.reason?.name);assertEquals(before,row());assertEquals(pending,queues())
    }
    @Test fun protectedWalletNameAndIconRemainEditable()=runBlocking {
        root();store.replacePullSnapshot(owner,CloudEntity.INVESTMENT_POSTING.table,listOf(cash()))
        val saved=repo.saveWallet(owner,draft().copy(name="Renamed",iconColorHex="#123456"),device,later).getOrThrow()
        assertEquals("Renamed",saved.name);assertEquals("#123456",saved.iconColorHex);assertEquals(50L,store.recordsIncludingDeleted(owner,CloudEntity.INVESTMENT_POSTING.table).single().payload.financeRawLong("accounting_amount_minor"))
    }
    @Test fun zeroAllocationOrDeletedCashAndOtherOwnerCashDoNotBlockAnUnlinkedWallet()=runBlocking {
        for(posts in listOf(listOf(cash(),cash(11,-50)),listOf(cash(deleted=true)))) {
            store.replacePullSnapshot(owner,CloudEntity.INVESTMENT_POSTING.table,posts)
            val changed=repo.saveWallet(owner,draft().copy(currencyCode="VND"),device,later).getOrThrow();assertEquals("VND",changed.currencyCode)
            repo.saveWallet(owner,draft(),device,later).getOrThrow()
        }
        store.replacePullSnapshot(owner,CloudEntity.INVESTMENT_POSTING.table,emptyList());store.replacePullSnapshot(other,CloudEntity.INVESTMENT_POSTING.table,listOf(cash(subject=other)))
        repo.archiveWallet(owner,RecordId(id(1)),device,later).getOrThrow();assertTrue(LedgerWalletRecord.fromCloudRecord(row()).isArchived)
    }
    @Test fun aRejectedWalletInABatchRollsBackAnEarlierUnrelatedMutation()=runBlocking {
        store.replacePullSnapshot(owner,CloudEntity.INVESTMENT_POSTING.table,listOf(cash()))
        val before=row();val pending=queues();val other=WalletDraft(id=id(2),name="Unrelated",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,later)
        val archived=LedgerWalletRecord.fromCloudRecord(before).toArchiveMutation(device,later)
        assertTrue(runCatching{store.commitMutations(listOf(other.record to other.pending,archived.record to archived.pending))}.isFailure)
        assertNull(store.record(owner,CloudEntity.LEDGER_WALLET.table,id(2)));assertEquals(before,row());assertEquals(pending,queues())
    }    @Test fun finalOwnerRotationRollsBackTheAllowedArchiveAndItsOutboxWrite()=runBlocking {
        val before=row();val pending=queues();var checks=0
        val changing=RoomLocalStore(db,currentBillOwner={if(++checks<2)owner else other})
        val archived=LedgerWalletRecord.fromCloudRecord(before).toArchiveMutation(device,later)
        assertTrue(runCatching{changing.commitMutation(archived.record,archived.pending)}.exceptionOrNull() is kotlinx.coroutines.CancellationException)
        assertEquals(2,checks);assertEquals(before,row());assertEquals(pending,queues())
    }
    @Test fun malformedInvestmentMetadataCannotBeUsedAsProofThatTheWalletIsEmpty()=runBlocking {
        val corrupt=cash().let{it.copy(payload=JsonObject(it.payload+("accounting_amount_minor" to JsonPrimitive("50"))))}
        store.replacePullSnapshot(owner,CloudEntity.INVESTMENT_POSTING.table,listOf(corrupt))
        val before=row();val pending=queues();val error=repo.archiveWallet(owner,RecordId(id(1)),device,later).exceptionOrNull()
        assertEquals(WalletValidationError.STALE_EDIT,(error as? WalletValidationException)?.reason);assertEquals(before,row());assertEquals(pending,queues())
    }

}
