package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentTradePublicationParentsTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val asset="44444444-4444-4444-4444-444444444444"
    private val now="2026-10-26T00:00:00Z"
    private fun row(version:Long=7,note:String="old",time:String=now)=CloudRecord(CloudEntity.INVESTMENT_TRADE.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("asset_id",asset);put("channel_id",asset);put("kind_raw_value","buy")
        put("quantity_decimal_string","2");put("unit_label","box");put("gross_amount_minor",0);put("currency_code","VND")
        put("accounting_gross_amount_minor",0);put("accounting_currency_code","VND");put("funding_wallet_id",JsonNull);put("capital_return_wallet_id",JsonNull)
        put("created_at",now);put("occurred_at",now);put("updated_at",time);put("deleted_at",JsonNull);put("sync_version",version)
        put("last_modified_by_device_id",device);put("note",note)
    },time,null,version)
    private fun parent(raw:CloudRecord=row(),confirmed:Long?=null)=InvestmentTradePublicationParent(raw.syncVersion,confirmed,device,raw.deletedAt!=null,investmentTradeIntentFingerprint(raw.payload),asset)
    @Test fun causalJournalIsOwnedBoundedAndKeepsExactLongConfirmedReceipts() {
        val old=row(9007199254740993L);val p=parent(old,9007199254740997L)
        val changed=appendInvestmentTradePublicationParent(row(old.syncVersion,"new"),p)
        assertEquals(listOf(p),localInvestmentTradePublicationParents(changed))
        assertEquals(old.syncVersion,changed.syncVersion);assertEquals("new",changed.payload.financeRawString("note"))
    }
    @Test fun directLocalMutationRecordsThePriorUserIntentAndDoesNotChangeItsBase() {
        val old=row();val changed=investmentAssetChanged(old,buildJsonObject{put("note","new")},device,"2026-10-26T00:15:00Z")
        assertEquals(listOf(parent(old)),localInvestmentTradePublicationParents(changed));assertEquals(7L,changed.syncVersion)
    }
    @Test fun derivedOnlyRebuildDoesNotCreateAnUnrelatedUserIntentParent() {
        val old=appendInvestmentTradePublicationParent(row(7,"new"),parent())
        val changed=investmentAssetChanged(old,buildJsonObject{put("position_cost_basis_after_minor",0)},device,now)
        assertEquals(listOf(parent()),localInvestmentTradePublicationParents(changed))
    }
    @Test fun wireSerializerAndUserIntentFingerprintStripOnlyTheOwnedJournal() {
        val raw=row();val local=appendInvestmentTradePublicationParent(raw,parent())
        assertTrue(LOCAL_TRADE_PUBLICATION_PARENTS_KEY in local.payload)
        assertFalse(LOCAL_TRADE_PUBLICATION_PARENTS_KEY in investmentTradePayloadForCloud(local.payload))
        assertEquals(investmentTradeIntentFingerprint(raw.payload),investmentTradeIntentFingerprint(local.payload))
    }
    @Test fun olderOwnServerClockCannotSupersedeTheNewerLocalCausalDescendant() {
        val old=row();val local=appendInvestmentTradePublicationParent(row(7,"new","2026-10-26T00:15:00Z"),parent(old))
        assertTrue(isKnownPriorInvestmentTradePublication(local,row(9,"old","2026-10-26T00:30:00Z"),device))
        assertTrue(isKnownPriorInvestmentTradePublication(local,row(8,"old","2026-10-26T00:30:00Z"),device))
    }
    @Test fun confirmedReceiptRecognizesHigherComparedBaseButUnknownGapStaysUnresolved() {
        val local=appendInvestmentTradePublicationParent(row(7,"new"),parent(confirmed=13))
        assertTrue(isKnownPriorInvestmentTradePublication(local,row(13),device))
        assertFalse(isKnownPriorInvestmentTradePublication(local,row(12),device))
        assertFalse(isKnownPriorInvestmentTradePublication(appendInvestmentTradePublicationParent(row(7,"new"),parent()),row(13),device))
    }
    @Test fun journalCannotAuthorizeAnotherDeviceOwnerIdentityIntentOrDeletion() {
        val local=appendInvestmentTradePublicationParent(row(7,"new"),parent())
        val other="55555555-5555-5555-5555-555555555555"
        for(remote in listOf(row(9,"different"),row(9).copy(ownerUserId=other),row(9).copy(id=other),
            row(9).let{it.copy(payload=JsonObject(it.payload+("last_modified_by_device_id" to JsonPrimitive(other))))},
            row(9).let{it.copy(deletedAt=now,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(now))))}))
            assertFalse(isKnownPriorInvestmentTradePublication(local,remote,device))
    }
    @Test fun malformedOrForeignPrivateJournalCannotBeSilentlyReplaced() {
        val raw=row();val local=appendInvestmentTradePublicationParent(raw,parent())
        for(value in listOf(JsonNull,JsonPrimitive("bad"),buildJsonObject{put("owner_user_id",asset)})) {
            val broken=local.copy(payload=JsonObject(local.payload+(LOCAL_TRADE_PUBLICATION_PARENTS_KEY to value)))
            assertThrows(IllegalArgumentException::class.java){localInvestmentTradePublicationParents(broken)}
            assertThrows(IllegalArgumentException::class.java){investmentAssetChanged(broken,buildJsonObject{put("note","other")},device,now)}
        }
    }
    @Test fun remoteIngressRejectsPrivateJournalEvenIfItsOwnedShapeIsValid() {
        val local=appendInvestmentTradePublicationParent(row(),parent())
        assertThrows(IllegalArgumentException::class.java){requireInvestmentTradeForPublication(owner,local,forWrite=false,allowLocalEvidence=false)}
        requireInvestmentTradeForPublication(owner,local,forWrite=false)
    }
    @Test fun journalRetainsTheMostRecent64DistinctEntriesAndRefusesVersionOverflow() {
        var local=row()
        for(n in 1..65)local=appendInvestmentTradePublicationParent(local,parent(row(note="p$n")))
        val parents=localInvestmentTradePublicationParents(local);assertEquals(64,parents.size)
        assertEquals(parent(row(note="p2")),parents.first());assertEquals(parent(row(note="p65")),parents.last())
        assertThrows(IllegalArgumentException::class.java){appendInvestmentTradePublicationParent(local,parent().copy(baseVersion=Long.MAX_VALUE))}
        assertThrows(IllegalArgumentException::class.java){appendInvestmentTradePublicationParent(local,parent().copy(confirmedVersion=7))}
    }
    private fun snapshot(vararg rows:CloudRecord)=InvestmentTradePublicationSnapshot(owner,id,rows.toList(),rows.map{raw->
        QueuedMutation(PendingMutation(CloudEntity.INVESTMENT_TRADE,raw.id,owner.value,if(raw.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE,raw.payload,raw.updatedAt!!,raw.syncVersion,device),3,5000,"network_io",false)
    },rows.map{it.entity to it.id}.toSet())
    private fun version(raw:CloudRecord,v:Long)=raw.copy(syncVersion=v,payload=JsonObject(raw.payload+("sync_version" to JsonPrimitive(v))))
    @Test fun aDefiniteHigherBaseReplyAddsAnExactReceiptWithoutChangingTheNewerIntentOrQueueStamps() {
        val old=row();val current=investmentAssetChanged(old,buildJsonObject{put("note","new")},device,"2026-10-26T00:15:00Z")
        val receipt=InvestmentTradePublicationReceipt(snapshot(old),version(old,12),11,listOf(version(old,13)))
        val changed=planInvestmentTradePublicationReceipt(receipt,snapshot(current)).single()
        assertEquals("new",changed.payload.financeRawString("note"));assertEquals(7L,changed.syncVersion);assertEquals(current.updatedAt,changed.updatedAt)
        assertTrue(isKnownPriorInvestmentTradePublication(changed,version(old,13),device))
        assertFalse(isKnownPriorInvestmentTradePublication(changed,version(old,12),device))
        assertEquals(current.payload,JsonObject(changed.payload-LOCAL_TRADE_PUBLICATION_PARENTS_KEY).let{JsonObject(it+(LOCAL_TRADE_PUBLICATION_PARENTS_KEY to current.payload.getValue(LOCAL_TRADE_PUBLICATION_PARENTS_KEY)))})
    }
    @Test fun receiptsAlsoCoverOtherPendingTradesRebuiltByTheRequestedRpc() {
        val second="88888888-8888-8888-8888-888888888888"
        val old=row().let{it.copy(id=second,payload=JsonObject(it.payload+("id" to JsonPrimitive(second))))}
        val current=investmentAssetChanged(old,buildJsonObject{put("note","other newer")},device,now)
        val source=snapshot(row(),old);val remoteOther=version(old,10)
        val receipt=InvestmentTradePublicationReceipt(source,version(row(),8),7,listOf(version(row(),9),remoteOther))
        val changed=planInvestmentTradePublicationReceipt(receipt,snapshot(row(),current))
        assertEquals(2,changed.size);assertTrue(isKnownPriorInvestmentTradePublication(changed.single{it.id==second},remoteOther,device))
    }
    @Test fun unchangedPendingIntentStillGetsADefiniteReceiptForAFutureConcurrentEdit() {
        val old=row();val receipt=InvestmentTradePublicationReceipt(snapshot(old),version(old,8),7,listOf(version(old,9)))
        val changed=planInvestmentTradePublicationReceipt(receipt,snapshot(old)).single()
        val edited=investmentAssetChanged(changed,buildJsonObject{put("note","later")},device,now)
        assertTrue(isKnownPriorInvestmentTradePublication(edited,version(old,9),device))
        assertTrue(planInvestmentTradePublicationReceipt(receipt,snapshot(changed)).isEmpty())
    }
    @Test fun aReceiptCannotBeAttachedToAnUnrelatedCurrentProposalWithoutTheActualCausalParent() {
        val old=row();val receipt=InvestmentTradePublicationReceipt(snapshot(old),version(old,8),7,listOf(version(old,9)))
        assertTrue(planInvestmentTradePublicationReceipt(receipt,snapshot(row(note="unrelated"))).isEmpty())
        assertTrue(planInvestmentTradePublicationReceipt(receipt,snapshot(row(8,"new base"))).isEmpty())
    }
    @Test fun anOtherTradeWhoseBusinessIntentChangedRemotelyIsNotTurnedIntoAnOwnAncestor() {
        val second="88888888-8888-8888-8888-888888888888"
        val other=row().let{it.copy(id=second,payload=JsonObject(it.payload+("id" to JsonPrimitive(second))))}
        val newer=investmentAssetChanged(other,buildJsonObject{put("note","new local")},device,now)
        val foreignIntent=version(other,10).let{it.copy(payload=JsonObject(it.payload+("note" to JsonPrimitive("other device business intent"))))}
        val receipt=InvestmentTradePublicationReceipt(snapshot(row(),other),version(row(),8),7,listOf(version(row(),9),foreignIntent))
        assertEquals(listOf(id),planInvestmentTradePublicationReceipt(receipt,snapshot(row(),newer)).map{it.id})
    }
    @Test fun receiptRequiresOwnedExactRequestedIntentActorAndEffectiveRebuildVersion() {
        val old=row();val valid=InvestmentTradePublicationReceipt(snapshot(old),version(old,8),7,listOf(version(old,9)))
        for(broken in listOf(valid.copy(returned=listOf(version(old,8))),valid.copy(returned=listOf(version(row(note="bad"),9))),
            valid.copy(expectedVersion=8),valid.copy(returned=valid.returned+valid.returned),valid.copy(returned=emptyList()),
            valid.copy(returned=listOf(version(old,9).let{it.copy(payload=JsonObject(it.payload+("last_modified_by_device_id" to JsonPrimitive(asset))))}))))
            assertThrows(IllegalArgumentException::class.java){planInvestmentTradePublicationReceipt(broken,snapshot(old))}
    }
    @Test fun createVersionTwoAndDeleteVersionPlusOneAreDistinctDefiniteReceiptRules() {
        val fresh=row(0);val create=InvestmentTradePublicationReceipt(snapshot(fresh),version(fresh,1),0,listOf(version(fresh,2)))
        assertTrue(isKnownPriorInvestmentTradePublication(planInvestmentTradePublicationReceipt(create,snapshot(fresh)).single(),version(fresh,2),device))
        val dead=row().let{it.copy(deletedAt=now,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(now))))}
        val deletion=InvestmentTradePublicationReceipt(snapshot(dead),dead,7,listOf(version(dead,8)))
        assertTrue(isKnownPriorInvestmentTradePublication(planInvestmentTradePublicationReceipt(deletion,snapshot(dead)).single(),version(dead,8),device))
    }

    @Test fun aReassignmentReceiptCoversRebuiltTradesFromTheComparedOriginalAssetAndDestination() {
        val otherAsset="77777777-7777-7777-7777-777777777777";val second="88888888-8888-8888-8888-888888888888"
        val old=row().let{it.copy(id=second,payload=JsonObject(it.payload+buildJsonObject{put("id",second);put("asset_id",otherAsset)}))}
        val source=snapshot(row(),old)
        val receipt=InvestmentTradePublicationReceipt(source,version(row(),8),7,listOf(version(row(),9),version(old,8)),setOf(asset,otherAsset))
        assertEquals(setOf(id,second),planInvestmentTradePublicationReceipt(receipt,source).map{it.id}.toSet())
        assertThrows(IllegalArgumentException::class.java){planInvestmentTradePublicationReceipt(receipt.copy(affectedAssetIds=setOf(otherAsset)),source)}
    }

    @Test fun deleteReceiptUsesTheSamePostgresMicrosecondPrecisionAsTheClosedHttpPort() {
        val localTime="2026-10-26T00:00:00.123456789Z";val serverTime="2026-10-26T00:00:00.123457Z"
        val dead=row().let{it.copy(deletedAt=localTime,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(localTime))))}
        val remote=version(dead,8).let{it.copy(deletedAt=serverTime,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(serverTime))))}
        val receipt=InvestmentTradePublicationReceipt(snapshot(dead),dead,7,listOf(remote))
        assertEquals(1,planInvestmentTradePublicationReceipt(receipt,snapshot(dead)).size)
    }

    @Test fun definiteRebuildReceiptsKeepAnAlreadyEditedSiblingPublishableBeyondTwoServerIncrements() {
        val bId="88888888-8888-8888-8888-888888888888"
        val aIds=listOf(id,"55555555-5555-5555-5555-555555555555","99999999-9999-9999-9999-999999999999")
        fun identified(raw:CloudRecord,identity:String)=raw.copy(id=identity,payload=JsonObject(raw.payload+("id" to JsonPrimitive(identity))))
        val oldB=identified(row(10,"server intent"),bId)
        val editedB=investmentAssetChanged(oldB,buildJsonObject{put("note","new pending user edit")},device,now)
        var rows=aIds.map{identified(row(0,"new sibling"),it)}+editedB
        for((index,aId) in aIds.withIndex()) {
            val current=snapshot(*rows.toTypedArray()).copy(tradeId=aId)
            val a=current.requestedRecord!!
            val receipt=InvestmentTradePublicationReceipt(current,version(a,1),0,listOf(version(a,2),version(oldB,11L+index)))
            val changes=planInvestmentTradePublicationReceipt(receipt,current).associateBy{it.id}
            rows=rows.map{changes[it.id] ?: it}
        }
        val currentB=rows.single{it.id==bId}
        assertEquals("new pending user edit",currentB.payload.financeRawString("note"));assertEquals(10L,currentB.syncVersion)
        assertTrue(isKnownPriorInvestmentTradePublication(currentB,version(oldB,13),device))
        assertEquals(RecordConflictWinner.LOCAL,resolveInvestmentTradePublication(currentB,version(oldB,13),device).winner)
    }

    @Test fun definiteSiblingReceiptCanCertifyThePriorCloudIntentFromAnotherDevice() {
        val bId="88888888-8888-8888-8888-888888888888"
        val oldB=row(10,"server intent").let{it.copy(id=bId,payload=JsonObject(it.payload+buildJsonObject{put("id",bId);put("last_modified_by_device_id",asset)}))}
        val editedB=investmentAssetChanged(oldB,buildJsonObject{put("note","new local intent")},device,now)
        val current=snapshot(row(0),editedB)
        val rebuilt=version(oldB,13).let{it.copy(payload=JsonObject(it.payload+("last_modified_by_device_id" to JsonPrimitive(device))))}
        val receipt=InvestmentTradePublicationReceipt(current,version(row(0),1),0,listOf(version(row(0),2),rebuilt))
        val changed=planInvestmentTradePublicationReceipt(receipt,current).single{it.id==bId}
        assertTrue(isKnownPriorInvestmentTradePublication(changed,rebuilt,device));assertEquals("new local intent",changed.payload.financeRawString("note"))
    }

    @Test fun aClosedDeleteRetiresTheCloudIntentEvenIfTheLocalNoteWasEditedBeforeDeletion() {
        val old=row();val edited=investmentAssetChanged(old,buildJsonObject{put("note","discarded edit")},device,now)
        val dead=investmentAssetChanged(edited,buildJsonObject{put("deleted_at",now)},device,now).copy(deletedAt=now)
        val saved=version(old,8).let{it.copy(deletedAt=now,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(now))))}
        val current=snapshot(dead);val sent=dead.copy(payload=investmentTradePayloadForCloud(dead.payload))
        val r=InvestmentTradePublicationReceipt(current,sent,7,listOf(saved))
        val changed=planInvestmentTradePublicationReceipt(r,current).single()
        assertEquals("discarded edit",changed.payload.financeRawString("note"));assertEquals(7L,changed.syncVersion)
        assertTrue(isKnownPriorInvestmentTradePublication(changed,saved,device))
    }

}
