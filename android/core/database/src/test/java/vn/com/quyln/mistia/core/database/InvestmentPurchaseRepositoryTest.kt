package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InvestmentPurchaseRepositoryTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val device="66666666-6666-6666-6666-666666666666"
    @Test fun purchaseObserverRejectsAReplacementOwnerSnapshotBeforePublishing()=runTest {
        val source=object:LocalStore by BudgetMemoryStore(){
            override fun observeInvestmentPurchaseSnapshot(owner:UserId)=flowOf(InvestmentPurchaseSnapshot(other,emptyList()))
        }
        assertTrue(runCatching{OfflineFirstInvestmentRepository(source).observePurchaseSnapshot(owner).first()}.isFailure)
    }
    @Test fun purchaseObserverRejectsForeignRowsInsideAnOtherwiseOwnedSnapshot()=runTest {
        val foreign=WalletDraft(id="44444444-4444-4444-4444-444444444444",name="Private",kind=WalletKind.CASH,currencyCode="VND").toMutation(other,null,device,"2026-10-23T00:00:00Z").record
        val source=object:LocalStore by BudgetMemoryStore(){
            override fun observeInvestmentPurchaseSnapshot(owner:UserId)=flowOf(InvestmentPurchaseSnapshot(owner,listOf(foreign)))
        }
        assertTrue(runCatching{OfflineFirstInvestmentRepository(source).observePurchaseSnapshot(owner).first()}.isFailure)
    }
}
