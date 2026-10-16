package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class TransactionReportingRoomTest {
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private lateinit var wallet: LedgerWalletRecord
    private lateinit var expense: TransactionCategoryRecord
    private lateinit var income: TransactionCategoryRecord
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val now = "2026-10-16T00:00:00Z"
    @Before fun setup() = kotlinx.coroutines.runBlocking {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store)
        wallet = repo.saveWallet(owner, WalletDraft(name = "JPY", kind = WalletKind.CASH, currencyCode = "JPY", openingBalanceMinor = 100000), device, now).getOrThrow()
        suspend fun category(kind: TransactionCategoryKind): TransactionCategoryRecord {
            val parent = repo.saveCategory(owner, CategoryDraft(name = kind.name, kind = kind, hierarchyRole = CategoryHierarchyRole.PARENT), device, now).getOrThrow()
            return repo.saveCategory(owner, CategoryDraft(name = kind.name + " child", kind = kind, hierarchyRole = CategoryHierarchyRole.CHILD, parentCategoryId = parent.id), device, now).getOrThrow()
        }
        expense = category(TransactionCategoryKind.EXPENSE); income = category(TransactionCategoryKind.INCOME)
    }
    @After fun close() { db.close() }
    private fun draft(kind: TransactionPrimaryKind = TransactionPrimaryKind.EXPENSE) = TransactionDraft(primaryKind = kind, title = "Report", amountMinor = 100,
        occurredAt = now, sourceWalletId = wallet.id, categoryId = if (kind == TransactionPrimaryKind.EXPENSE) expense.id else income.id)
    @Test fun manualReportingPairQueuesExactMoneyAndNilRateWithoutRetaggingWallet() = runTest {
        wallet = wallet.copy(openingBalanceMinor = Long.MAX_VALUE)
        val funded = wallet.toCloudRecord()
        store.commitMutation(funded, PendingMutation(CloudEntity.LEDGER_WALLET, funded.id, owner.value, MutationKind.UPSERT, funded.payload, now, 0, device))
        val input = draft().copy(amountMinor = 9007199254740993L, reportingCurrencyCode = "VND", reportingAmountMinor = 18014398509481986L, conversionMode = CurrencyConversionMode.MANUAL)
        val saved = repo.saveTransaction(owner, input, device, now).getOrThrow()
        Assert.assertEquals(9007199254740993L, saved.amountMinor); Assert.assertEquals(18014398509481986L, saved.reportingAmountMinor)
        Assert.assertEquals("JPY", saved.sourceCurrencyCode); Assert.assertEquals("VND", saved.reportingCurrencyCode)
        val pending = store.pendingMutations(owner, CloudEntity.LEDGER_TRANSACTION, Long.MAX_VALUE).single().mutation
        Assert.assertEquals(JsonPrimitive(18014398509481986L), pending.payload!!["reporting_amount_minor"])
        Assert.assertEquals(JsonPrimitive("manual"), pending.payload!!["exchange_rate_provider"])
        Assert.assertEquals(JsonNull, pending.payload!!["exchange_rate_decimal_string"]); Assert.assertEquals(JsonNull, pending.payload!!["exchange_rate_date"])
        Assert.assertEquals(listOf(wallet), repo.observeWallets(owner).first()); Assert.assertTrue(repo.observeTransactions(other).first().isEmpty())
        val persisted = repo.observeTransactions(owner).first()
        Assert.assertEquals(listOf(saved), persisted)
        Assert.assertEquals(9214364837600034814L, TransactionWalletBalanceIndex(repo.observeWallets(owner).first(), persisted).balance(wallet.id))
    }
    @Test fun incomeReportingAppRatePersistsConversionMetadataAndExactOutbox() = runTest {
        val saved = repo.saveTransaction(owner, draft(TransactionPrimaryKind.INCOME).copy(reportingCurrencyCode = "VND", reportingAmountMinor = 16550,
            conversionMode = CurrencyConversionMode.APP_RATE, exchangeRateDecimalString = "165.5", exchangeRateProvider = "fixture", exchangeRateDate = "2026-10-16"), device, now).getOrThrow()
        Assert.assertEquals(saved, repo.observeTransactions(owner).first().single())
        Assert.assertEquals(100L, saved.amountMinor); Assert.assertEquals(16550L, saved.reportingAmountMinor)
        Assert.assertEquals(CurrencyConversionMode.APP_RATE, saved.conversionMode); Assert.assertEquals("165.5", saved.exchangeRateDecimalString)
        Assert.assertEquals("fixture", saved.exchangeRateProvider); Assert.assertEquals("2026-10-16", saved.exchangeRateDate)
        Assert.assertEquals(saved.toPayload(), store.pendingMutations(owner, CloudEntity.LEDGER_TRANSACTION, Long.MAX_VALUE).single().mutation.payload)
        Assert.assertEquals(listOf(wallet), repo.observeWallets(owner).first())
    }
    @Test fun changingReportingTargetToSourceClearsOldConversionWithLargeBaseVersion() = runTest {
        val input = draft(); val original = repo.saveTransaction(owner, input, device, now).getOrThrow()
        val imported = original.copy(reportingCurrencyCode = "VND", reportingAmountMinor = 16500, conversionModeWireValue = "appRate", exchangeRateDecimalString = "165",
            exchangeRateProvider = "fixture", exchangeRateDate = "2026-10-16", syncVersion = 9007199254740993L).toCloudRecord()
        store.commitMutation(imported, PendingMutation(CloudEntity.LEDGER_TRANSACTION, imported.id, owner.value, MutationKind.UPSERT, imported.payload, now, imported.syncVersion, device))
        val saved = repo.saveTransaction(owner, input.copy(id = original.id, reportingCurrencyCode = "JPY"), device, "2026-10-16T00:00:01Z").getOrThrow()
        Assert.assertEquals(saved, repo.observeTransactions(owner).first().single())
        Assert.assertNull(saved.reportingCurrencyCode); Assert.assertNull(saved.reportingAmountMinor); Assert.assertNull(saved.conversionMode)
        Assert.assertNull(saved.exchangeRateDecimalString); Assert.assertNull(saved.exchangeRateProvider); Assert.assertNull(saved.exchangeRateDate)
        Assert.assertEquals(original.id, saved.id); Assert.assertEquals(100L, saved.amountMinor)
        val pending = store.pendingMutations(owner, CloudEntity.LEDGER_TRANSACTION, Long.MAX_VALUE).single().mutation
        Assert.assertEquals(9007199254740993L, pending.baseVersion); Assert.assertEquals(JsonNull, pending.payload!!["reporting_amount_minor"])
    }
}
