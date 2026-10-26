package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentWalletPublicationParentsTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="33333333-3333-3333-3333-333333333333"
    private val oldLink="44444444-4444-4444-4444-444444444444"
    private val newLink="55555555-5555-5555-5555-555555555555"
    private val event="66666666-6666-6666-6666-666666666666"
    private val id=investmentSystemWalletId(owner)
    private val now="2026-10-26T00:00:00Z"
    private fun wallet(id:String)=WalletDraft(id=id,name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=100).toMutation(owner,null,device,now).record
    private fun root(v:Long=0)=wallet(id).let{it.copy(syncVersion=v,payload=JsonObject(it.payload+buildJsonObject {
        put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("opening_balance_minor",0)
        put("investment_linked_wallet_id",oldLink);put("sync_version",v)
    }))}
    private fun changed(before:CloudRecord,target:CloudRecord=wallet(newLink),others:List<CloudRecord> = listOf(wallet(oldLink))):CloudRecord {
        val source=InvestmentWalletSnapshot(owner,listOf(before,target)+others)
        val request=InvestmentWalletLinkRequest(LedgerWalletRecord.fromCloudRecord(before),LedgerWalletRecord.fromCloudRecord(target),event,false,0,"Move cash")
        val (row,queue)=planInvestmentWalletLink(source,request,device,"2026-10-26T00:15:00Z").mutations.single()
        assertEquals(row.payload,queue.payload)
        return row
    }
    private fun marker(v:Long=0)=buildJsonObject {
        put("version",1);put("owner_user_id",owner.value);put("wallet_id",id)
        put("parents",JsonArray(listOf(buildJsonObject {
            put("base_version",v);put("confirmed_version",JsonNull);put("device_id",device);put("fingerprint","0".repeat(64))
        })))
    }
    private fun marked(row:CloudRecord,value:JsonElement=marker(row.syncVersion))=row.copy(payload=JsonObject(row.payload+(LOCAL_INVESTMENT_WALLET_PARENTS_KEY to value)))
    private fun server(before:CloudRecord,version:Long=before.syncVersion+1)=before.copy(syncVersion=version,updatedAt="2026-10-26T00:30:00Z",payload=JsonObject(investmentWalletPayloadForCloud(before.payload)+buildJsonObject {
        put("sync_version",version);put("updated_at","2026-10-26T00:30:00Z");put("name","Investment Wallet");put("current_balance_minor",999L)
    }))
    @Test fun actualLinkProducerCarriesThePreviousProposalInItsExactLocalOutbox() {
        val old=root();val row=changed(old)
        assertTrue(row.payload[LOCAL_INVESTMENT_WALLET_PARENTS_KEY] is JsonObject)
        assertEquals(1,localInvestmentWalletPublicationParents(row).size)
        assertTrue(isKnownPriorInvestmentWalletPublication(row,server(old),device))
    }
    @Test fun persistedEvidenceStillProvesTheOldWriteAfterJsonRoundTrip() {
        val old=root(9007199254740993L);val row=changed(old)
        val restored=row.copy(payload=Json.parseToJsonElement(row.payload.toString()).jsonObject)
        val entries=localInvestmentWalletPublicationParents(restored);assertEquals(1,entries.size)
        val parent=entries.single()
        assertEquals(9007199254740993L,parent.baseVersion)
        assertTrue(isKnownPriorInvestmentWalletPublication(restored,server(old),device))
    }
    @Test fun strictLiteralMarkerPreservesLongVersionsAndDoesNotAcceptAnotherGeneration() {
        val row=marked(root(9007199254740993L))
        assertEquals(listOf(InvestmentWalletPublicationParent(9007199254740993L,null,device,"0".repeat(64))),localInvestmentWalletPublicationParents(row))
        assertTrue(runCatching{localInvestmentWalletPublicationParents(marked(root(1),marker(0)))}.isFailure)
    }
    @Test fun unknownMalformedForeignAndOversizedEvidenceIsHeld() {
        val m=marker();val entry=m.getValue("parents").jsonArray.single().jsonObject
        val bad=listOf<JsonElement>(JsonNull,JsonPrimitive("parent"),JsonObject(m+("version" to JsonPrimitive(2))),
            JsonObject(m+("owner_user_id" to JsonPrimitive(newLink))),JsonObject(m+("wallet_id" to JsonPrimitive(newLink))),
            JsonObject(m+("unknown" to JsonNull)),JsonObject(m+("parents" to JsonArray(emptyList()))),
            JsonObject(m+("parents" to JsonArray(List(65){entry}))),
            JsonObject(m+("parents" to JsonArray(listOf(JsonObject(entry+("base_version" to JsonPrimitive("0"))))))),
            JsonObject(m+("parents" to JsonArray(listOf(JsonObject(entry+("confirmed_version" to JsonPrimitive(0))))))),
            JsonObject(m+("parents" to JsonArray(listOf(JsonObject(entry+("fingerprint" to JsonPrimitive("short"))))))))
        for(value in bad)assertTrue(runCatching{localInvestmentWalletPublicationParents(marked(root(),value))}.isFailure)
    }
    @Test fun rootEvidenceCannotAuthorizeAnOrdinaryWalletEvenWithAMatchingOwner() {
        val ordinary=wallet(newLink).let{it.copy(payload=JsonObject(it.payload+(LOCAL_INVESTMENT_WALLET_PARENTS_KEY to marker())))}
        assertTrue(runCatching{localInvestmentWalletPublicationParents(ordinary)}.isFailure)
    }
    @Test fun aMalformedPriorJournalCannotBeLaunderedByTheActualLinkProducer() {
        assertTrue(runCatching{changed(marked(root(),JsonNull))}.isFailure)
    }
    @Test fun historyIsBoundedAndRecentParentsRemainUsableWithoutRecursivePayloads() {
        val targets=(0 until 100).map{wallet("77777777-7777-7777-7777-"+it.toString().padStart(12,'0'))}
        var current=root();var prior=current
        for(target in targets) {prior=current;current=changed(current,target,targets.filter{it.id!=target.id}+wallet(oldLink))}
        val entries=localInvestmentWalletPublicationParents(current)
        assertEquals(64,entries.size);assertEquals(64,entries.distinct().size)
        assertTrue(current.payload.getValue(LOCAL_INVESTMENT_WALLET_PARENTS_KEY).toString().length<18000)
        assertTrue(isKnownPriorInvestmentWalletPublication(current,server(prior),device))
        assertFalse(isKnownPriorInvestmentWalletPublication(current,server(root()),device))
    }
    @Test fun ownActorExactVersionActiveStateAndMetadataMustAllMatch() {
        val old=root();val local=changed(old);val remote=server(old)
        val bad=listOf(server(old,2),remote.copy(deletedAt=now),
            remote.copy(payload=JsonObject(remote.payload+("last_modified_by_device_id" to JsonPrimitive(newLink)))),
            remote.copy(payload=JsonObject(remote.payload+("investment_linked_wallet_id" to JsonNull))),
            remote.copy(payload=JsonObject(remote.payload+("is_archived" to JsonPrimitive(true)))))
        for(row in bad)assertFalse(isKnownPriorInvestmentWalletPublication(local,row,device))
    }
    @Test fun privateEvidenceAndDerivedMoneyNeverLeaveTheClosedWalletPort() {
        val p=JsonObject(marked(root()).payload+mapOf("current_balance_minor" to JsonPrimitive(Long.MAX_VALUE),"future_null" to JsonNull,"future_large" to JsonPrimitive(Long.MAX_VALUE)))
        val wire=investmentWalletPayloadForCloud(p)
        assertFalse(LOCAL_INVESTMENT_WALLET_PARENTS_KEY in wire);assertFalse("current_balance_minor" in wire)
        assertSame(JsonNull,wire["future_null"]);assertEquals(JsonPrimitive(Long.MAX_VALUE),wire["future_large"])
        assertTrue(LOCAL_INVESTMENT_WALLET_PARENTS_KEY in p)
    }
    @Test fun comparisonIgnoresOnlyOwnedEvidenceAndServerReadonlyFields() {
        val p=root().payload
        val normalized=JsonObject(p+buildJsonObject{put(LOCAL_INVESTMENT_WALLET_PARENTS_KEY,marker());put("name","Investment Wallet");put("current_balance_minor",Long.MAX_VALUE)})
        assertEquals(investmentWalletPublicationFingerprint(p),investmentWalletPublicationFingerprint(normalized))
        assertNotEquals(investmentWalletPublicationFingerprint(p),investmentWalletPublicationFingerprint(JsonObject(p+("future_note" to JsonPrimitive("Changed")))))
        assertNotEquals(investmentWalletPublicationFingerprint(p),investmentWalletPublicationFingerprint(JsonObject(p+("investment_linked_wallet_id" to JsonNull))))
    }
}
