package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentWalletPublicationSnapshotTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val id=investmentSystemWalletId(owner)
    private val device="33333333-3333-3333-3333-333333333333"
    private val now="2026-10-26T00:00:00Z"
    private fun root(version:Long=9007199254740993L)=CloudRecord(CloudEntity.LEDGER_WALLET.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("name","Investment wallet");put("kind_raw_value","investment")
        put("currency_code","VND");put("opening_balance_minor",0L);put("system_purpose_raw_value","investmentProfit")
        put("investment_linked_wallet_id",JsonNull);put("icon_symbol_name",WalletKind.INVESTMENT.defaultIcon);put("icon_color_hex",WalletKind.INVESTMENT.defaultColorHex)
        put("institution_display_name",JsonNull);put("institution_preset_key",JsonNull);put("sort_order",Int.MAX_VALUE-100)
        put("is_archived",false);put("archived_at",JsonNull);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now)
        put("sync_version",version);put("last_modified_by_device_id",device);put("future_null",JsonNull);put("future_object",buildJsonObject{put("large",Long.MAX_VALUE)})
    },now,null,version)
    private val targetId="44444444-4444-4444-4444-444444444444"
    private fun target()=root().let{it.copy(id=targetId,payload=JsonObject(it.payload+mapOf("id" to JsonPrimitive(targetId),"name" to JsonPrimitive("Cash"),"kind_raw_value" to JsonPrimitive("cash"),"system_purpose_raw_value" to JsonNull)))}
    private fun linked()=root().let{it.copy(payload=JsonObject(it.payload+("investment_linked_wallet_id" to JsonPrimitive(targetId))))}
    private fun queue(row:CloudRecord)=QueuedMutation(PendingMutation(CloudEntity.LEDGER_WALLET,row.id,row.ownerUserId,
        if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE,row.payload,row.updatedAt!!,row.syncVersion,device),0,0,null)
    @Test fun exactUnlinkedRootBindsItsEntireQueueAndNeedsNoOtherWallet() {
        val row=root();val q=queue(row);val source=InvestmentWalletPublicationSnapshot(owner,row,q,true)
        assertTrue(source.matches(q));assertEquals(InvestmentWalletPublicationDependency.READY,source.dependency())
    }
    @Test fun anOwnedActiveCashWalletInTheAccountingCurrencyIsAReadyDependency() {
        val row=linked();val source=InvestmentWalletPublicationSnapshot(owner,row,queue(row),true,target())
        assertTrue(source.matches(source.pending!!));assertEquals(InvestmentWalletPublicationDependency.READY,source.dependency())
    }
    @Test fun aCoherentPendingOrdinaryWalletDefersRootPublication() {
        val row=linked();val cash=target()
        val source=InvestmentWalletPublicationSnapshot(owner,row,queue(row),true,cash,queue(cash),true)
        assertEquals(InvestmentWalletPublicationDependency.WAITING_FOR_LINKED_WALLET,source.dependency())
        assertTrue(source.matches(source.pending!!))
    }
    @Test fun newerRowsAttemptsBaseKindOrDeviceColumnsCannotPassAnOldQueueProof() {
        val row=root();val q=queue(row);val base=InvestmentWalletPublicationSnapshot(owner,row,q,true)
        assertFalse(base.copy(record=row.copy(payload=JsonObject(row.payload+("name" to JsonPrimitive("Newer"))))).matches(q))
        assertFalse(base.copy(pending=q.copy(attemptCount=1)).matches(q))
        assertFalse(base.copy(hasPendingMutation=false).matches(q))
        for(mutation in listOf(q.mutation.copy(baseVersion=q.mutation.baseVersion-1),q.mutation.copy(kind=MutationKind.DELETE),q.mutation.copy(deviceId=targetId))) {
            val changed=q.copy(mutation=mutation)
            assertFalse(base.copy(pending=changed).matches(changed))
        }
        assertFalse(base.copy(owner=other).matches(q))
        assertFalse(base.copy(record=target(),pending=queue(target())).matches(queue(target())))
    }
    @Test fun foreignCreditReservedArchivedDeletedOrDifferentCurrencyTargetsAreInvalid() {
        val row=linked();val cash=target();val source=InvestmentWalletPublicationSnapshot(owner,row,queue(row),true,cash)
        val bad=listOf(cash.copy(ownerUserId=other.value),cash.copy(id=other.value),
            cash.copy(payload=JsonObject(cash.payload+("kind_raw_value" to JsonPrimitive("creditCard")))),
            cash.copy(payload=JsonObject(cash.payload+("kind_raw_value" to JsonPrimitive("investment")))),
            cash.copy(payload=JsonObject(cash.payload+("system_purpose_raw_value" to JsonPrimitive("futureReserved")))),
            cash.copy(payload=JsonObject(cash.payload+("currency_code" to JsonPrimitive("JPY")))),
            cash.copy(payload=JsonObject(cash.payload+mapOf("is_archived" to JsonPrimitive(true),"archived_at" to JsonPrimitive(now)))),
            cash.copy(deletedAt=now,payload=JsonObject(cash.payload+("deleted_at" to JsonPrimitive(now)))))
        for(target in bad)assertEquals(InvestmentWalletPublicationDependency.INVALID_LINK,source.copy(linkedRecord=target).dependency())
        assertEquals(InvestmentWalletPublicationDependency.INVALID_LINK,source.copy(linkedRecord=null).dependency())
    }
    @Test fun dirtyMissingOrUnqueuedTargetProofsAreHeldRatherThanConsideredReady() {
        val row=linked();val cash=target();val q=queue(cash)
        val source=InvestmentWalletPublicationSnapshot(owner,row,queue(row),true,cash)
        assertEquals(InvestmentWalletPublicationDependency.UNREADABLE_SOURCE,source.copy(linkedHasPendingMutation=true).dependency())
        assertEquals(InvestmentWalletPublicationDependency.UNREADABLE_SOURCE,source.copy(linkedPending=q).dependency())
        assertEquals(InvestmentWalletPublicationDependency.UNREADABLE_SOURCE,source.copy(linkedPending=q.copy(mutation=q.mutation.copy(deviceId=id)),linkedHasPendingMutation=true).dependency())
    }
    @Test fun aClearedLinkCannotRetainAStaleDependencyPointer() {
        val row=root();val source=InvestmentWalletPublicationSnapshot(owner,row,queue(row),true,target())
        assertEquals(InvestmentWalletPublicationDependency.UNREADABLE_SOURCE,source.dependency())
    }
}
