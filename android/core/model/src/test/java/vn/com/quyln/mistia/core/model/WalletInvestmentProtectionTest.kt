package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class WalletInvestmentProtectionTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="22222222-2222-2222-2222-222222222222"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val now="2026-10-28T00:00:00Z"
    private fun wallet(n:Int=1)=WalletDraft(id=id(n),name="Cash",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,now).record
    private fun root(link:String?=id(1))=wallet(99).let{it.copy(id=investmentSystemWalletId(owner),payload=JsonObject(it.payload+buildJsonObject {
        put("id",investmentSystemWalletId(owner));put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",link?.let(::JsonPrimitive) ?: JsonNull)
    }))}
    private fun posting(n:Int=10,amount:Long=50,deleted:Boolean=false,bucket:String?="booked")=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(n),owner.value,buildJsonObject {
        put("id",id(n));put("user_id",owner.value);put("wallet_id",id(1));put("event_id",id(n+100));put("role_raw_value",if(bucket==null)"funding" else "cashAccrual")
        put("cash_bucket_raw_value",bucket?.let(::JsonPrimitive) ?: JsonNull);put("cash_origin_raw_value",if(bucket==null)JsonNull else JsonPrimitive("derived"))
        put("accounting_amount_minor",amount);put("accounting_currency_code","JPY");put("currency_code","JPY");put("amount_minor",amount)
        put("deleted_at",if(deleted)JsonPrimitive(now) else JsonNull);put("sync_version",0);put("created_at",now);put("updated_at",now)
    },now,if(deleted)now else null,0)
    private fun check(vararg rows:CloudRecord)=walletHasProtectedInvestmentCash(owner,id(1),listOf(wallet())+rows)
    @Test fun linkedWalletIsProtectedEvenWithoutAnyCashOrWithZeroTotal() {assertTrue(check(root()));assertTrue(check(root(),posting(amount=0)))}
    @Test fun positiveNegativeAndUnreconciledBalancesRemainProtected() {
        assertTrue(check(posting()));assertTrue(check(posting(amount=-1)));assertTrue(check(posting(bucket="unreconciled")))
    }
    @Test fun zeroAcrossBucketsDeletedAndNoncashRowsDoNotLockAnUnlinkedWallet() {
        assertFalse(check(root(null),posting(),posting(11,-50,bucket="unreconciled")));assertFalse(check(posting(deleted=true)));assertFalse(check(posting(bucket=null)))
    }
    @Test fun signedCashSumNeverOverflowsLongOrRoundsBeyondDoublePrecision() {
        assertTrue(check(posting(amount=Long.MAX_VALUE),posting(11,Long.MAX_VALUE),posting(12,2)))
        assertFalse(check(posting(amount=Long.MAX_VALUE),posting(11,Long.MIN_VALUE),posting(12,1)))
        assertTrue(check(posting(amount=9007199254740993),posting(11,-9007199254740992)))
    }
    @Test fun foreignDuplicateMalformedOrAmbiguousReferencesCannotProveAnUnlockedWallet() {
        val p=posting();val bad=listOf(listOf(p.copy(ownerUserId=device)),listOf(p,p),listOf(p.copy(payload=JsonObject(p.payload+("accounting_amount_minor" to JsonPrimitive("50"))))),
            listOf(p.copy(payload=JsonObject(p.payload+("wallet_id" to JsonPrimitive("bad"))))),listOf(root().copy(payload=JsonObject(root().payload+("investment_linked_wallet_id" to JsonPrimitive("bad"))))),
            listOf(p.copy(deletedAt=now)),listOf(p.copy(payload=JsonObject(p.payload+("cash_bucket_raw_value" to JsonPrimitive("unknown"))))))
        for(rows in bad)assertTrue(runCatching{check(*rows.toTypedArray())}.isFailure)
    }
    @Test fun otherWalletAllocationsAndOtherLinksDoNotBlockTheSelectedWallet() {
        val p=posting().let{it.copy(payload=JsonObject(it.payload+("wallet_id" to JsonPrimitive(id(2)))))}
        assertFalse(check(root(id(2)),wallet(2),p))
    }    @Test fun differentAccountingUnitsCannotCancelIntoAnUnlockedWallet() {
        val foreign=posting(11,-50).let{it.copy(payload=JsonObject(it.payload+("accounting_currency_code" to JsonPrimitive("VND"))))}
        assertTrue(check(posting(),foreign))
    }
    @Test fun onlyFinancialShapeOrArchiveStateChangesInvokeTheGuard() {
        val before=wallet();val renamed=before.copy(payload=JsonObject(before.payload+("name" to JsonPrimitive("Renamed"))))
        assertFalse(walletMutationNeedsInvestmentProtection(before,renamed))
        for((key,v) in listOf("kind_raw_value" to JsonPrimitive("other"),"currency_code" to JsonPrimitive("VND"),"is_archived" to JsonPrimitive(true)))
            assertTrue(walletMutationNeedsInvestmentProtection(before,before.copy(payload=JsonObject(before.payload+(key to v)))))
    }

}
