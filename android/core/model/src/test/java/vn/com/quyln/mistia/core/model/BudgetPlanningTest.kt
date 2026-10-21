package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class BudgetPlanningTest {
    private val zone = ZoneId.of("Asia/Tokyo")
    private val october = YearMonth.of(2026, 10)
    private val reference = Instant.parse("2026-10-13T00:00:00Z")

    private fun assertMinor(expected:Long,actual:BigInteger?)=assertEquals(BigInteger.valueOf(expected),actual)
    private fun assertMinor(expected:BigInteger,actual:BigInteger?)=assertEquals(expected,actual)

    @Test fun `latest eligible continuity plan wins independently of currency and owner`() {
        val old = budget()
        val current = old.copy(id = OTHER_BUDGET_ID, monthAnchor = "2026-09-30T15:00:00Z", limitMinor = 2000)
        val future = old.copy(id = THIRD_BUDGET_ID, monthAnchor = "2026-10-31T15:00:00Z")
        val foreign = old.copy(id = FOURTH_BUDGET_ID, ownerUserId = OTHER_OWNER)
        val plans = activeBudgetPlans(UserId(OWNER_ID), listOf(old, current, future, foreign), october, zone)
        assertEquals(listOf(current.id), plans.map { it.id })
        assertEquals(listOf(old.id), activeBudgetPlans(UserId(OWNER_ID), listOf(old, current), YearMonth.of(2026,9),zone).map { it.id })
    }

    @Test fun `month spending uses Tokyo boundaries and only active posted reported expenses`() {
        val row = transactionRecord().copy(occurredAt = "2026-09-30T15:00:00Z")
        val records = listOf(row, row.copy(id = TX2, occurredAt = "2026-09-30T14:59:59Z"),
            row.copy(id = TX3, occurredAt = "2026-10-31T15:00:00Z"), row.copy(id = TX4, entryStatusWireValue = "draft"),
            row.copy(id = TX5, isArchived = true), row.copy(id = TX6, ownerUserId = OTHER_OWNER))
        assertMinor(100, project(listOf(budget()), records).branches.single().spentMinor)
    }

    @Test fun `rollover includes previous months since source plan without multiplying limit`() {
        val older = transactionRecord().copy(occurredAt = "2026-09-05T00:00:00Z")
        val current = older.copy(id = TX2, occurredAt = "2026-10-05T00:00:00Z")
        assertMinor(100, project(listOf(budget()), listOf(older,current)).branches.single().spentMinor)
        val rolled = project(listOf(budget().copy(rolloverEnabled = true)),listOf(older,current)).branches.single()
        assertMinor(200, rolled.spentMinor)
        assertMinor(1000, rolled.limitMinor)
    }

    @Test fun `FX uses source expense amount and retains unavailable conversion`() {
        val jpy = transactionRecord().copy(occurredAt = "2026-10-05T00:00:00Z", reportingAmountMinor = 999, reportingCurrencyCode = "VND")
        val plan = budget().copy(currencyCode = "VND")
        assertNull(project(listOf(plan),listOf(jpy)).branches.single().spentMinor)
        val rate = ExchangeRateSnapshot("JPY","VND","165.25","test",0,null)
        assertMinor(16525, project(listOf(plan),listOf(jpy), rates=listOf(rate)).branches.single().spentMinor)
        val vnd = jpy.copy(sourceCurrencyCode = "VND",amountMinor = 16525)
        assertMinor(100,project(listOf(budget()),listOf(vnd),rates=listOf(rate)).branches.single().spentMinor)
    }

    @Test fun `parent branch includes unbudgeted children once and summary never doubles children`() {
        val parent = budget().copy(id = PARENT_BUDGET_ID,categoryId = PARENT_ID, categoryIdSnapshot = PARENT_ID,
            categoryIsParentSnapshot = true, categoryHierarchyRoleSnapshotWireValue = "parent", categoryParentIdSnapshot = null,
            categoryNameSnapshot = "Living")
        val child = category(CATEGORY_ID, "Food", PARENT_ID)
        val sibling = category(OTHER_CHILD_ID,"Travel",PARENT_ID)
        val first = transactionRecord().copy(occurredAt = "2026-10-05T00:00:00Z")
        val second = first.copy(id = TX2, categoryId = OTHER_CHILD_ID,amountMinor = 200)
        val projection = project(listOf(parent,budget().copy(limitMinor=500)), listOf(first,second),listOf(child,sibling))
        assertEquals(1,projection.branches.size)
        assertMinor(300,projection.branches.single().spentMinor)
        assertMinor(100,projection.branches.single().children.single().spentMinor)
        assertMinor(1000,projection.totalLimitMinor)
        assertMinor(300,projection.totalSpentMinor)
        assertMinor(700,projection.remainingMinor)
    }
    @Test fun `reporting FX overflow stays exact in budget spending`() {
        val rate=ExchangeRateSnapshot("JPY","VND","200","fixture",0,null)
        val plan=budget().copy(currencyCode="VND")
        val expense=transactionRecord().copy(amountMinor=Long.MAX_VALUE)
        assertMinor(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.valueOf(200),project(listOf(plan),listOf(expense),rates=listOf(rate)).branches.single().spentMinor)
    }

    @Test fun `frozen localized category labels survive live rename and legacy hierarchy falls back`() {
        val renamed = category(CATEGORY_ID,"Dining",PARENT_ID)
        val frozen = project(listOf(budget()),emptyList(),listOf(renamed)).branches.single()
        assertEquals("Food",frozen.name)
        val legacy = budget().copy(categoryIsParentSnapshot=null,categoryParentIdSnapshot=null, categoryHierarchyRoleSnapshotWireValue=null)
        val allocation = legacy.allocationSnapshot(renamed)
        assertEquals(PARENT_ID,allocation.branchCategoryId)
        assertFalse(allocation.categoryIsParent)
        val parent = category(PARENT_ID,"Living",null)
        val parentLegacy = legacy.copy(categoryId=PARENT_ID,categoryIdSnapshot=null)
        assertTrue(parentLegacy.allocationSnapshot(parent).categoryIsParent)
    }

    @Test fun `spending exclusions and explicit reporting expense match iOS`() {
        val ordinary = transactionRecord().copy(occurredAt="2026-10-05T00:00:00Z")
        val lend = ordinary.copy(id=TX2, primaryKindWireValue="transfer",transferSubtypeWireValue="debt",debtIntentWireValue="lend")
        val reported = lend.copy(id=TX3,reportingExpenseMinor=200)
        val adjustment = ordinary.copy(id=TX4,title="Balance adjustment")
        val cardPayment = ordinary.copy(id=TX5,title="Card payment Visa")
        val records=listOf(ordinary,lend,reported,adjustment,cardPayment)
        assertMinor(300,project(listOf(budget()),records).branches.single().spentMinor)
    }

    @Test fun `large accounting sums retain precision beyond Long without saturation`() {
        val large=9007199254740993L
        val transaction=transactionRecord(amountMinor=large).copy(occurredAt="2026-10-05T00:00:00Z")
        assertMinor(large,project(listOf(budget()),listOf(transaction)).branches.single().spentMinor)
        val extreme=transaction.copy(amountMinor=Long.MAX_VALUE)
        assertMinor(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO,project(listOf(budget()),listOf(extreme,extreme.copy(id=TX2))).totalSpentMinor)
    }

    @Test fun `pace golden vectors preserve buffer projection days and exact allowance`() {
        val month=YearMonth.of(2026,4)
        val day3=Instant.parse("2026-04-02T15:00:00Z")
        val pace=budgetPace(25000,100000,month,day3,zone)
        assertEquals(BudgetHealth.CAUTION,pace.health)
        assertMinor(250000,pace.projectedSpentMinor)
        assertEquals(27,pace.daysRemaining)
        assertMinor(2777,pace.dailyAllowanceMinor)
        assertEquals(BudgetHealth.STABLE,budgetPace(11500,100000,month,day3,zone).health)
        assertEquals(BudgetHealth.CAUTION,budgetPace(11501,100000,month,day3,zone).health)
        assertEquals(BudgetHealth.EXCEEDED,budgetPace(100000,100000,month,day3,zone).health)
        assertEquals(BudgetHealth.STABLE,budgetPace(120000,100000,month.plusMonths(1),day3,zone).health)
        assertTrue(budgetPace(95000,100000,month.minusMonths(1),day3,zone).isPastMonth)
    }

    @Test fun `rollover normalizes a legacy month anchor to the full local month`() {
        val firstDay = transactionRecord().copy(occurredAt="2026-08-31T15:00:00Z")
        val current = firstDay.copy(id=TX2,occurredAt="2026-10-05T00:00:00Z")
        assertMinor(200,project(listOf(budget().copy(rolloverEnabled=true)),listOf(firstDay,current)).totalSpentMinor)
    }

    @Test fun `legacy parent snapshot falls back to live name icon and color`() {
        val parent=category(PARENT_ID,"Living",null)
        val legacy=budget().copy(categoryId=PARENT_ID,categoryIdSnapshot=null,categoryIsParentSnapshot=null,
            categoryHierarchyRoleSnapshotWireValue=null,categoryParentIdSnapshot=null,
            categoryNameSnapshot=null,categoryNameEnglishSnapshot=null,categoryNameJapaneseSnapshot=null,
            categoryIconSymbolNameSnapshot=null,categoryColorHexSnapshot=null)
        val branch=project(listOf(legacy),emptyList(),listOf(parent)).branches.single()
        assertEquals("Living",branch.name)
        assertEquals(parent.iconSymbolName,branch.icon)
        assertEquals(parent.iconColorHex,branch.colorHex)
    }

    @Test fun `canonical installment repayment is excluded even without a live category row`() {
        val loan="d872b8af-d28a-5b90-8822-839dfa097b23"
        val plan=budget().copy(categoryId=loan,categoryIdSnapshot=loan)
        val transaction=transactionRecord().copy(categoryId=loan)
        assertMinor(0,project(listOf(plan),listOf(transaction)).totalSpentMinor)
    }

    @Test fun `localized editor path keeps frozen hierarchy and falls back from missing locale`() {
        val frozen=budget()
        assertEquals("Living / Food",frozen.localizedBudgetPath(CategoryNameLanguage.ENGLISH))
        assertEquals("生活 / 食費",frozen.localizedBudgetPath(CategoryNameLanguage.JAPANESE))
        assertEquals("Sinh hoạt / Ăn uống",frozen.copy(categoryPathEnglishSnapshot="").localizedBudgetPath(CategoryNameLanguage.ENGLISH))
        assertEquals("Food",frozen.copy(categoryPathEnglishSnapshot=null,categoryPathSnapshot=null).localizedBudgetPath(CategoryNameLanguage.ENGLISH))
    }

    @Test fun `recent picker ignores unreadable recency while retaining known category usage`() {
        val food=category(CATEGORY_ID,"Food",PARENT_ID)
        val known=transactionRecord().copy(occurredAt="2026-10-12T00:00:00Z")
        val broken=known.copy(id=TX2,occurredAt="broken")
        assertEquals(listOf(food.id),budgetQuickCategories(UserId(OWNER_ID),listOf(food),listOf(broken,known),false,reference,zone).map {it.id})
        assertTrue(budgetQuickCategories(UserId(OWNER_ID),listOf(food),listOf(broken),false,reference,zone).isEmpty())
    }

    @Test fun `picker favorites exclude parents and recent ranks usage within ninety local days`() {
        val parent=category(PARENT_ID,"Living",null).copy(isFavorite=true)
        val food=category(CATEGORY_ID,"Food",PARENT_ID).copy(isFavorite=true)
        val travel=category(OTHER_CHILD_ID,"Travel",PARENT_ID)
        val record=transactionRecord().copy(occurredAt="2026-08-01T00:00:00Z")
        val records=listOf(record,record.copy(id=TX2),record.copy(id=TX3),
            record.copy(id=TX4,categoryId=OTHER_CHILD_ID,occurredAt="2026-10-12T00:00:00Z"),
            record.copy(id=TX5,categoryId=OTHER_CHILD_ID,occurredAt="2026-06-01T00:00:00Z"),
            record.copy(id=TX6,categoryId=OTHER_CHILD_ID,ownerUserId=OTHER_OWNER))
        assertEquals(listOf(food.id),budgetQuickCategories(UserId(OWNER_ID),listOf(parent,food,travel),records,true,reference,zone).map { it.id })
        assertEquals(listOf(food.id,travel.id),budgetQuickCategories(UserId(OWNER_ID),listOf(parent,food,travel),records,false,reference,zone).map { it.id })
    }

    @Test fun `iOS frozen canonical identity counts renamed live cloud category without changing snapshot`() {
        val owner=UserId(OWNER_ID)
        val parentId=SystemCategoryIdentity.cloudId("parent_expense_housing",owner)
        val childId=SystemCategoryIdentity.cloudId("rent",owner)
        val parent=category(parentId,"Renamed housing",null).copy(isSystem=true,systemKey="parent_expense_housing")
        val child=category(childId,"Renamed rent",parentId).copy(isSystem=true,systemKey="rent")
        val plan=budget().copy(categoryId=childId,categoryIdSnapshot=SystemCategoryIdentity.canonicalId("rent"),
            categoryParentIdSnapshot=SystemCategoryIdentity.canonicalId("parent_expense_housing"),categoryNameEnglishSnapshot="Frozen title")
        val before=plan.toPayload()
        val projection=project(listOf(plan),listOf(transactionRecord().copy(categoryId=childId)),listOf(parent,child))
        assertMinor(100,projection.branches.single().spentMinor)
        assertEquals("Frozen title",projection.branches.single().name)
        assertEquals(before,plan.toPayload())
        val foreign=child.copy(id=SystemCategoryIdentity.cloudId("rent",UserId(OTHER_OWNER)),ownerUserId=OTHER_OWNER)
        assertMinor(0,project(listOf(plan),listOf(transactionRecord().copy(categoryId=foreign.id)),listOf(parent,child,foreign)).totalSpentMinor)
    }
    @Test fun `canonical and cloud snapshots share one continuity plan and one summary branch`() {
        val owner=UserId(OWNER_ID)
        val parentId=SystemCategoryIdentity.cloudId("parent_expense_housing",owner)
        val childId=SystemCategoryIdentity.cloudId("rent",owner)
        val categories=listOf(category(parentId,"Housing",null).copy(isSystem=true,systemKey="parent_expense_housing"),
            category(childId,"Rent",parentId).copy(isSystem=true,systemKey="rent"))
        val old=budget().copy(categoryId=childId,categoryIdSnapshot=SystemCategoryIdentity.canonicalId("rent"),categoryParentIdSnapshot=SystemCategoryIdentity.canonicalId("parent_expense_housing"))
        val current=old.copy(id=OTHER_BUDGET_ID,categoryIdSnapshot=childId,categoryParentIdSnapshot=parentId,monthAnchor="2026-09-30T15:00:00Z",limitMinor=2000)
        val projection=project(listOf(old,current),emptyList(),categories)
        assertEquals(1,projection.branches.size);assertMinor(2000,projection.totalLimitMinor)
    }

    @Test fun `canonical parent branch counts unbudgeted children once and keeps frozen display`() {
        val owner=UserId(OWNER_ID)
        val parentId=SystemCategoryIdentity.cloudId("parent_expense_housing",owner)
        val rentId=SystemCategoryIdentity.cloudId("rent",owner)
        val internetId=SystemCategoryIdentity.cloudId("internet",owner)
        val categories=listOf(category(parentId,"New housing name",null).copy(isSystem=true,systemKey="parent_expense_housing"),
            category(rentId,"New rent name",parentId).copy(isSystem=true,systemKey="rent"),
            category(internetId,"New internet name",parentId).copy(isSystem=true,systemKey="internet",deletedAt=NOW))
        val parent=budget().copy(categoryId=parentId,categoryIdSnapshot=SystemCategoryIdentity.canonicalId("parent_expense_housing"),
            categoryIsParentSnapshot=true,categoryNameEnglishSnapshot="Frozen housing",limitMinor=2000)
        val rent=budget().copy(id=OTHER_BUDGET_ID,categoryId=rentId,categoryIdSnapshot=rentId,categoryParentIdSnapshot=parentId)
        val records=listOf(transactionRecord().copy(categoryId=rentId),transactionRecord().copy(id=TX2,categoryId=internetId,amountMinor=200))
        val projection=project(listOf(parent,rent),records,categories)
        assertEquals(1,projection.branches.size)
        assertMinor(2000,projection.totalLimitMinor)
        assertMinor(300,projection.totalSpentMinor)
        assertMinor(100,projection.branches.single().children.single().spentMinor)
        assertEquals("Frozen housing",projection.branches.single().name)
    }
    @Test fun `logical aliases preserve actual custom IDs and foreign owner boundaries`() {
        val owner=UserId(OWNER_ID)
        val legacy=category(CATEGORY_ID,"Rent",PARENT_ID).copy(isSystem=true,systemKey="rent",deletedAt=NOW)
        val custom=category(OTHER_CHILD_ID,"Custom rent",PARENT_ID).copy(systemKey="rent",isSystem=false)
        val foreign=legacy.copy(id=SystemCategoryIdentity.cloudId("rent",UserId(OTHER_OWNER)),ownerUserId=OTHER_OWNER)
        val index=CategoryIdentityIndex(owner,listOf(legacy,custom,foreign))
        assertEquals(SystemCategoryIdentity.canonicalId("rent"),index.logical(legacy.id))
        assertEquals(legacy,index.category(SystemCategoryIdentity.cloudId("rent",owner)))
        assertEquals(custom.id,index.logical(custom.id))
        assertEquals(foreign.id,index.logical(foreign.id))
    }

    private fun project(plans:List<BudgetPlanRecord>, records:List<LedgerTransactionRecord>, categories:List<TransactionCategoryRecord> = emptyList(), rates:List<ExchangeRateSnapshot> = emptyList()) =
        projectBudgets(UserId(OWNER_ID),plans,categories,records,emptyList(),october,reference,zone,rates,
            CategoryNameLanguage.ENGLISH,setOf("Balance adjustment"),"JPY")

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
