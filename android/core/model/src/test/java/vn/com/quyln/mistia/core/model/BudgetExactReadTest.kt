package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.time.*
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class BudgetExactReadTest {
    private val zone=ZoneId.of("Asia/Tokyo")
    private val october=YearMonth.of(2026,10)
    private val reference=Instant.parse("2026-10-13T00:00:00Z")
    private fun project(plans:List<BudgetPlanRecord>,records:List<LedgerTransactionRecord>,categories:List<TransactionCategoryRecord> = emptyList(),wallets:List<LedgerWalletRecord> = emptyList(),rates:List<ExchangeRateSnapshot> = emptyList(),currency:String="JPY")=
        projectBudgets(UserId(OWNER_ID),plans,categories,records,wallets,october,reference,zone,rates,CategoryNameLanguage.ENGLISH,setOf("Balance adjustment"),currency)
    private fun minor(expected:BigInteger,actual:Any?)=assertEquals(expected.toString(),actual?.toString())
    private fun minor(expected:Long,actual:Any?)=minor(BigInteger.valueOf(expected),actual)
    @Test fun `sum of two maximum expenses stays exact at branch and reporting summary`() {
        val first=transactionRecord(amountMinor=Long.MAX_VALUE);val projection=project(listOf(budget()),listOf(first,first.copy(id=TX2)))
        val exact=BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO
        minor(exact,projection.branches.single().spentMinor);minor(exact,projection.totalSpentMinor);minor(0,projection.remainingMinor)
    }
    @Test fun `child allocations without parent retain twice maximum branch and summary limit`() {
        val first=budget().copy(limitMinor=Long.MAX_VALUE)
        val second=first.copy(id=OTHER_BUDGET_ID,categoryId=OTHER_CHILD_ID,categoryIdSnapshot=OTHER_CHILD_ID,categoryNameSnapshot="Travel",categoryNameEnglishSnapshot="Travel")
        val projection=project(listOf(first,second),emptyList());val exact=BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO
        minor(exact,projection.branches.single().limitMinor);minor(exact,projection.totalLimitMinor);minor(exact,projection.remainingMinor)
    }
    @Test fun `missing required expense FX cannot claim zero spent and stable pace`() {
        val projection=project(listOf(budget().copy(currencyCode="VND")),listOf(transactionRecord()))
        assertNull(projection.branches.single().spentMinor);assertNull(projection.branches.single().pace.health);assertNull(projection.totalSpentMinor);assertNull(projection.remainingMinor)
    }
    @Test fun `unavailable summary FX cannot leave a partial known limit or spending`() {
        val vnd=budget().copy(currencyCode="VND",limitMinor=330)
        val row=transactionRecord(amountMinor=165,sourceCurrencyCode="VND")
        val projection=project(listOf(vnd),listOf(row));minor(165,projection.branches.single().spentMinor);minor(330,projection.branches.single().limitMinor)
        assertNull(projection.totalLimitMinor);assertNull(projection.totalSpentMinor);assertNull(projection.remainingMinor)
    }
    @Test fun `legacy missing source currency uses owned wallet currency and explicit source wins`() {
        val wallet=LedgerWalletRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_WALLET.table,SOURCE_WALLET_ID,OWNER_ID,buildJsonObject {
            put("id",SOURCE_WALLET_ID);put("user_id",OWNER_ID);put("name","VND");put("kind_raw_value","cash");put("currency_code","VND");put("opening_balance_minor",0)
        },NOW,null,0))
        val row=transactionRecord(amountMinor=165,sourceCurrencyCode=null)
        val projection=project(listOf(budget().copy(currencyCode="VND")),listOf(row),wallets=listOf(wallet),currency="VND")
        minor(165,projection.branches.single().spentMinor);minor(165,projection.totalSpentMinor)
        val explicit=project(listOf(budget()),listOf(row.copy(sourceCurrencyCode="JPY")),wallets=listOf(wallet));minor(165,explicit.totalSpentMinor)
        for(excluded in listOf(wallet.copy(ownerUserId=OTHER_OWNER),wallet.copy(deletedAt=NOW))) {
            assertNull(project(listOf(budget().copy(currencyCode="VND")),listOf(row),wallets=listOf(excluded),currency="VND").totalSpentMinor)
        }
    }
    @Test fun `malformed explicit source code is unknown while imported same ISO money keeps identity`() {
        assertNull(project(listOf(budget()),listOf(transactionRecord(sourceCurrencyCode="???"))).totalSpentMinor)
        val imported=project(listOf(budget().copy(currencyCode="USD")),listOf(transactionRecord(amountMinor=1375,sourceCurrencyCode="USD")),currency="USD")
        minor(1375,imported.totalSpentMinor)
        assertNull(project(listOf(budget()),listOf(transactionRecord(amountMinor=1375,sourceCurrencyCode="USD"))).totalSpentMinor)
    }
    @Test fun `pace projected money and refund allowance do not saturate at Long maximum`() {
        val first=budgetPace(Long.MAX_VALUE,Long.MAX_VALUE,october,Instant.parse("2026-09-30T15:00:00Z"),zone)
        minor(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.valueOf(31),first.projectedSpentMinor)
        val refund=budgetPace(Long.MIN_VALUE,Long.MAX_VALUE,october,Instant.parse("2026-10-29T15:00:00Z"),zone)
        minor(BigInteger.valueOf(Long.MAX_VALUE)-BigInteger.valueOf(Long.MIN_VALUE),refund.dailyAllowanceMinor)
    }
    @Test fun `per record rounding zero no FX cancellation and inactive owner controls remain truthful`() {
        val rate=ExchangeRateSnapshot("JPY","VND","2.5","fixture",0,null);val row=transactionRecord(amountMinor=3)
        minor(16,project(listOf(budget().copy(currencyCode="VND")),listOf(row,row.copy(id=TX2)),rates=listOf(rate),currency="VND").totalSpentMinor)
        minor(0,project(listOf(budget().copy(currencyCode="VND")),listOf(row.copy(amountMinor=0,sourceCurrencyCode="???")),currency="VND").totalSpentMinor)
        minor(-1,project(listOf(budget()),listOf(row.copy(amountMinor=Long.MAX_VALUE),row.copy(id=TX2,amountMinor=Long.MIN_VALUE))).totalSpentMinor)
        val excluded=listOf(row.copy(ownerUserId=OTHER_OWNER),row.copy(id=TX2,deletedAt=NOW),row.copy(id=TX3,isArchived=true),row.copy(id=TX4,entryStatusWireValue="draft"))
        minor(0,project(listOf(budget()),excluded).totalSpentMinor)
    }
    @Test fun `unknown required transfer classification cannot prove no budget expense`() {
        val paid=transactionRecord(primaryKindWireValue="transfer",transferSubtypeWireValue="futureSubtype").copy(debtIntentWireValue="borrow",sourceWalletId=null)
        assertNull(project(listOf(budget()),listOf(paid)).totalSpentMinor)
        assertNull(project(listOf(budget()),listOf(paid.copy(transferSubtypeWireValue="debt",debtIntentWireValue="futureIntent"))).totalSpentMinor)
        minor(0,project(listOf(budget()),listOf(paid.copy(debtIntentWireValue="lend"))).totalSpentMinor)
        minor(100,project(listOf(budget()),listOf(paid.copy(primaryKindWireValue="expense"))).totalSpentMinor)
        for(record in listOf(transactionRecord().copy(primaryKindWireValue="futureKind"),transactionRecord().copy(entryStatusWireValue="futureStatus"),transactionRecord().copy(occurredAt="broken"))) {
            assertNull(project(listOf(budget()),listOf(record)).totalSpentMinor)
        }
    }
    @Test fun `known parent limit and allocations survive an unavailable spending dependency`() {
        val parent=budget().copy(id=PARENT_BUDGET_ID,categoryId=PARENT_ID,categoryIdSnapshot=PARENT_ID,categoryIsParentSnapshot=true,categoryHierarchyRoleSnapshotWireValue="parent",categoryParentIdSnapshot=null,limitMinor=2000)
        val child=budget().copy(limitMinor=400)
        val projection=project(listOf(parent,child),listOf(transactionRecord(sourceCurrencyCode="VND")),categories=listOf(category(CATEGORY_ID,"Food",PARENT_ID)))
        val branch=projection.branches.single();minor(2000,branch.limitMinor);minor(400,branch.allocatedMinor);minor(1600,branch.unallocatedMinor)
        assertNull(branch.spentMinor);assertNull(branch.pace.health);minor(2000,projection.totalLimitMinor);assertNull(projection.totalSpentMinor)
    }
    @Test fun `unneeded calendar and foreign wallet metadata do not poison proved neutral spending`() {
        val neutral=transactionRecord(primaryKindWireValue="income",sourceCurrencyCode="???").copy(occurredAt="broken")
        minor(0,project(listOf(budget()),listOf(neutral)).totalSpentMinor)
        val excluded=transactionRecord(sourceCurrencyCode="VND").copy(occurredAt="2026-11-01T00:00:00Z")
        minor(0,project(listOf(budget()),listOf(excluded)).totalSpentMinor)
    }
    @Test fun `wallet kind uncertainty matters only when it changes card payment classification`() {
        val wallet=LedgerWalletRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_WALLET.table,SOURCE_WALLET_ID,OWNER_ID,buildJsonObject {
            put("id",SOURCE_WALLET_ID);put("user_id",OWNER_ID);put("name","Kind metadata");put("kind_raw_value","futureKind");put("currency_code","???");put("opening_balance_minor",0)
        },NOW,null,0))
        val row=transactionRecord().copy(title="Card payment")
        assertNull(project(listOf(budget()),listOf(row),wallets=listOf(wallet)).totalSpentMinor)
        minor(100,project(listOf(budget()),listOf(row),wallets=listOf(wallet.copy(kindWireValue="creditCard"))).totalSpentMinor)
        minor(0,project(listOf(budget()),listOf(row),wallets=listOf(wallet.copy(kindWireValue="cash"))).totalSpentMinor)
        minor(100,project(listOf(budget()),listOf(row.copy(title="Ordinary")),wallets=listOf(wallet)).totalSpentMinor)
    }
    private fun category(id:String,name:String,parent:String?): TransactionCategoryRecord = CategoryDraft(id=id,name=name,nameLanguage=CategoryNameLanguage.ENGLISH,
        kind=TransactionCategoryKind.EXPENSE,hierarchyRole=if(parent==null)CategoryHierarchyRole.PARENT else CategoryHierarchyRole.CHILD,
        parentCategoryId=parent).toMutation(UserId(OWNER_ID),null,
            parent?.let { category(it,"Living",null) },DEVICE,NOW).record

    private fun budget() = BudgetPlanRecord(
        id = BUDGET_ID,
        ownerUserId = OWNER_ID,
        categoryId = CATEGORY_ID,
        categoryIdSnapshot = CATEGORY_ID,
        categoryNameSnapshot = "Ăn uống",
        categoryNameEnglishSnapshot = "Food",
        categoryNameJapaneseSnapshot = "食費",
        categoryPathSnapshot = "Sinh hoạt / Ăn uống",
        categoryPathEnglishSnapshot = "Living / Food",
        categoryPathJapaneseSnapshot = "生活 / 食費",
        categoryIconSymbolNameSnapshot = "mistia.category.food",
        categoryColorHexSnapshot = "#FF7A59",
        categoryParentIdSnapshot = PARENT_ID,
        categoryParentNameSnapshot = "Sinh hoạt",
        categoryParentNameEnglishSnapshot = "Living",
        categoryParentNameJapaneseSnapshot = "生活",
        categoryParentIconSymbolNameSnapshot = "mistia.category.living",
        categoryParentColorHexSnapshot = "#5B7BFF",
        categoryHierarchyRoleSnapshotWireValue = "child",
        categoryIsParentSnapshot = false,
        includesFamilySpending = false,
        monthAnchor = MONTH,
        limitMinor = 1000,
        rolloverEnabled = false,
        currencyCode = "JPY",
        isArchived = false,
        createdAt = MONTH,
        updatedAt = "2026-09-25T01:02:03Z",
        deletedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = null,
    )

    private fun transactionRecord(
        primaryKindWireValue: String = TransactionPrimaryKind.EXPENSE.wireValue,
        transferSubtypeWireValue: String? = null,
        amountMinor: Long = 100,
        note: String? = null,
        sourceCurrencyCode: String? = "JPY",
        destinationCurrencyCode: String? = null,
        destinationAmountMinor: Long? = null,
        conversionModeWireValue: String? = null,
        exchangeRateDecimalString: String? = null,
        exchangeRateProvider: String? = null,
        exchangeRateDate: String? = null,
        syncVersion: Long = 0,
    ) = LedgerTransactionRecord(
        id = TRANSACTION_ID,
        ownerUserId = OWNER_ID,
        primaryKindWireValue = primaryKindWireValue,
        transferSubtypeWireValue = transferSubtypeWireValue,
        debtIntentWireValue = null,
        entryStatusWireValue = TransactionEntryStatus.POSTED.wireValue,
        title = "Entry",
        note = note,
        amountMinor = amountMinor,
        sourceCurrencyCode = sourceCurrencyCode,
        destinationCurrencyCode = destinationCurrencyCode,
        destinationAmountMinor = destinationAmountMinor,
        reportingCurrencyCode = null,
        reportingAmountMinor = null,
        conversionModeWireValue = conversionModeWireValue,
        exchangeRateDecimalString = exchangeRateDecimalString,
        exchangeRateProvider = exchangeRateProvider,
        exchangeRateDate = exchangeRateDate,
        occurredAt = OCCURRED_AT,
        createdAt = NOW,
        updatedAt = NOW,
        createdByUserId = OWNER_ID,
        lastModifiedByUserId = OWNER_ID,
        counterpartyName = null,
        normalizedCounterpartyKey = null,
        settlementGroupId = null,
        settlementObligationId = null,
        settlementRoleWireValue = null,
        reportingExpenseMinor = null,
        reportingIncomeMinor = null,
        sourceWalletId = SOURCE_WALLET_ID,
        destinationWalletId = null,
        categoryId = CATEGORY_ID,
        deletedAt = null,
        isArchived = false,
        archivedAt = null,
        syncVersion = syncVersion,
        lastModifiedByDeviceId = DEVICE,
    )

    companion object {
        const val OWNER_ID="11111111-1111-4111-8111-111111111111"
        const val OTHER_OWNER="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        const val BUDGET_ID="22222222-2222-4222-8222-222222222222"
        const val OTHER_BUDGET_ID="33333333-3333-4333-8333-333333333333"
        const val THIRD_BUDGET_ID="44444444-4444-4444-8444-444444444444"
        const val FOURTH_BUDGET_ID="55555555-5555-4555-8555-555555555555"
        const val PARENT_BUDGET_ID="66666666-6666-4666-8666-666666666666"
        const val PARENT_ID="77777777-7777-4777-8777-777777777777"
        const val CATEGORY_ID="99999999-9999-4999-8999-999999999999"
        const val OTHER_CHILD_ID="88888888-8888-4888-8888-888888888888"
        const val MONTH="2026-09-01T00:00:00Z"
        const val NOW="2026-10-13T00:00:00Z"
        const val OCCURRED_AT="2026-10-05T00:00:00Z"
        const val TRANSACTION_ID="11111111-1111-1111-1111-111111111111"
        const val TX2="22222222-2222-2222-2222-222222222222"
        const val TX3="33333333-3333-3333-3333-333333333333"
        const val TX4="44444444-4444-4444-4444-444444444444"
        const val TX5="55555555-5555-5555-5555-555555555555"
        const val TX6="66666666-6666-6666-6666-666666666666"
        const val SOURCE_WALLET_ID="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        const val DEVICE="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    }
}
