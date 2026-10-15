package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.saveable.SaverScope
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InstallmentEditorStateTest {
    private val owner = "11111111-1111-1111-1111-111111111111"
    private val id = "22222222-2222-2222-2222-222222222222"
    private val walletId = "33333333-3333-3333-3333-333333333333"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val now = "2026-01-15T00:00:00Z"
    private fun wallet() = LedgerWalletRecord.fromCloudRecord(WalletDraft(id = walletId, name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY")
        .toMutation(UserId(owner), null, id, now).record)
    private fun plan(currency: String = "JPY") = InstallmentPlanRecord(id, owner, "Loan", "mistia.plan.loan", 9007199254740993L,
        31, 12, 2, walletId, currency, false, now, now, null, 9007199254740995L, walletId)
    private fun fresh() = InstallmentEditorState.fresh(owner, id, "JPY").copy(name = " Loan ", amountText = "9,007,199,254,740,993", paymentWalletId = walletId)
    private fun reason(block: () -> Unit): InstallmentValidationError? = try { block(); null }
        catch (e: InstallmentValidationException) { e.reason }
    @Test fun `picker excludes differently denominated preferred archived and ordinary wallets`() {
        val cash = wallet(); val foreignMoney = cash.copy(id = other, currencyCode = "VND")
        assertEquals(listOf(cash), eligibleInstallmentWallets(owner, other, listOf(cash, foreignMoney), "JPY"))
        assertTrue(eligibleInstallmentWallets(owner, other, listOf(foreignMoney.copy(isArchived = true)), "JPY").isEmpty())
        assertEquals(listOf(foreignMoney), eligibleInstallmentWallets(owner, null, listOf(cash, foreignMoney), "vnd"))
    }
    @Test fun `restored mixed currency wallet cannot be submitted even when it is the preferred ID`() {
        val state = InstallmentEditorState.from(owner, plan("USD"))
        assertEquals(InstallmentValidationError.WALLET_CURRENCY_MISMATCH, reason { state.toDraft(listOf(wallet())) })
        val saved = with(InstallmentEditorState.saver(owner, id)) { SaverScope { true }.save(state) }!!
        val restored = InstallmentEditorState.saver(owner, id).restore(saved)!!
        assertEquals(InstallmentValidationError.WALLET_CURRENCY_MISMATCH, reason { restored.toDraft(listOf(wallet())) })
    }
    @Test fun `fresh form keeps stable client ID and default schedule and no implicit wallet`() {
        val state = InstallmentEditorState.fresh(owner, id, "JPY")
        assertEquals(id, state.id); assertEquals(15, state.dueDay); assertEquals(1, state.frequencyMonths); assertNull(state.paymentWalletId)
        val draft = fresh().toDraft(listOf(wallet())); assertEquals(id, draft.id); assertEquals("Loan", draft.name); assertNull(draft.expected)
        assertEquals(9007199254740993L, draft.amountPerCycleMinor)
    }
    @Test fun `edited form retains original owned baseline currency creation and Long version`() {
        val plan = plan("USD"); val state = InstallmentEditorState.from(owner, plan)
        assertEquals(plan, state.baseline()); assertEquals(plan.amountPerCycleMinor, state.amountMinor())
        assertEquals(plan, state.copy(name = "Changed").toDraft(listOf(wallet().copy(currencyCode = "USD"))).expected)
        assertEquals("USD", state.currencyCode); assertEquals(12, state.toDraft(listOf(wallet().copy(currencyCode = "USD"))).totalCycles)
    }
    @Test fun `currency input follows Swift grouped minor values without Double or multiplying by fraction digits`() {
        listOf("JPY", "VND", "USD").forEach { currency ->
            val state = fresh().copy(currencyCode = currency, amountText = "1,375")
            assertEquals(1375L, state.toDraft(listOf(wallet().copy(currencyCode = currency))).amountPerCycleMinor)
        }
        assertEquals("9,007,199,254,740,993", installmentAmountInput("9007199254740993"))
        assertEquals("1,234", installmentAmountInput("1,23,4"))
        assertEquals("13.75", installmentAmountInput("13.75"))
    }
    @Test fun `fraction scientific malformed overflow and non positive input cannot silently change money`() {
        listOf("", "0", "-1", "13.75", "1e3", "1a2", "9223372036854775808").forEach { value ->
            assertEquals(value, InstallmentValidationError.INVALID_AMOUNT, reason { fresh().copy(amountText = value).toDraft(listOf(wallet())) })
        }
    }
    @Test fun `optional count is exact Int32 and blank clears while legacy zero and negative remain explicit`() {
        val state = fresh()
        assertNull(state.toDraft(listOf(wallet())).totalCycles)
        listOf(0, -1, Int.MAX_VALUE).forEach { count -> assertEquals(count, state.copy(totalCyclesText = count.toString()).toDraft(listOf(wallet())).totalCycles) }
        listOf("1.5", "invalid", "2147483648", "999999999999999999999").forEach { value ->
            assertEquals(InstallmentValidationError.INVALID_TOTAL_CYCLES, reason { state.copy(totalCyclesText = value).toDraft(listOf(wallet())) })
        }
    }
    @Test fun `wallet list excludes foreign deleted unknown card and newly archived while retaining existing archived link`() {
        val cash = wallet(); val archived = cash.copy(id = other, isArchived = true)
        val records = listOf(cash, archived, cash.copy(id = id, ownerUserId = other), cash.copy(id = id, deletedAt = now),
            cash.copy(id = id, kindWireValue = "creditCard"), cash.copy(id = id, kindWireValue = "futureKind"))
        assertEquals(listOf(cash), eligibleInstallmentWallets(owner, null, records, "JPY"))
        assertEquals(listOf(cash, archived), eligibleInstallmentWallets(owner, other, records, "JPY"))
        assertEquals(InstallmentValidationError.INVALID_WALLET, reason { fresh().toDraft(listOf(cash.copy(ownerUserId = other))) })
        assertEquals(InstallmentValidationError.INVALID_WALLET, reason { fresh().copy(paymentWalletId = null).toDraft(records) })
    }
    @Test fun `existing imported money and schedule survive untouched identity while frozen currency cannot switch`() {
        val source = plan().copy(dueDay = 99, frequencyMonths = 0)
        val state = InstallmentEditorState.from(owner, source)
        assertEquals(99, state.dueDay); assertEquals(1, state.frequencyMonths)
        assertEquals(99, state.toDraft(listOf(wallet())).dueDay)
        assertEquals(InstallmentValidationError.INVALID_CURRENCY, reason { state.copy(currencyCode = "VND").toDraft(listOf(wallet())) })
        assertEquals(InstallmentValidationError.INVALID_DAYS, reason { state.copy(dueDay = 100).toDraft(listOf(wallet())) })
        assertEquals(InstallmentValidationError.INVALID_FREQUENCY, reason { state.copy(frequencyMonths = 99).toDraft(listOf(wallet())) })
    }
    @Test fun `state restoration preserves unsaved fields and baseline only for the same owner and editor ID`() {
        val state = InstallmentEditorState.from(owner, plan()).copy(name = "Unsaved", amountText = "100", totalCyclesText = "")
        val saver = InstallmentEditorState.saver(owner, id)
        val saved = with(saver) { SaverScope { true }.save(state) }!!
        assertEquals(state, saver.restore(saved)); assertNull(InstallmentEditorState.saver(other, id).restore(saved))
        assertNull(InstallmentEditorState.saver(owner, other).restore(saved)); assertNull(saver.restore(listOf("bad")))
        val foreign = state.copy(baselinePayload = plan().copy(ownerUserId = other).toPayload().toString())
        assertNull(saver.restore(with(saver) { SaverScope { true }.save(foreign) }!!))
        val changedCurrency = state.copy(currencyCode = "VND")
        assertNull(saver.restore(with(saver) { SaverScope { true }.save(changedCurrency) }!!))
    }
    @Test fun `navigation restoration keeps stable create ID and owned edit baseline and rejects malformed foreign targets`() {
        val saver = InstallmentEditorNavigation.saver(owner)
        val created = InstallmentEditorNavigation.create(owner, "JPY", id)
        val saved = with(saver) { SaverScope { true }.save(created) }!!
        assertEquals(created, saver.restore(saved)); assertNull(InstallmentEditorNavigation.saver(other).restore(saved))
        val edit = InstallmentEditorNavigation.edit(owner, plan())
        assertEquals(plan(), edit.baseline()); assertTrue(edit.valid()); assertTrue(edit.closed().valid())
        assertFalse(edit.copy(owner = other).valid()); assertFalse(edit.copy(editorId = other).valid())
        assertNull(saver.restore(listOf(owner, "bad-id", "", "JPY")))
    }
    @Test fun `operation errors remain failures and callback success is propagated`() = runTest {
        val error = IllegalStateException("fixture")
        assertSame(error, guardedInstallmentMutation<Unit> { throw error }.exceptionOrNull())
        assertEquals("Saved", guardedInstallmentMutation { Result.success("Saved") }.getOrThrow())
    }
    @OptIn(ExperimentalCoroutinesApi::class)
    @Test fun `late non cooperative success after leaving the editor cannot dismiss a replacement form`() = runTest {
        val release = CompletableDeferred<Unit>(); var dismissed = false
        val job = launch(UnconfinedTestDispatcher(testScheduler)) {
            guardedInstallmentMutation { withContext(NonCancellable) { release.await(); Result.success(Unit) } }.onSuccess { dismissed = true }
        }
        job.cancel(); release.complete(Unit); job.join(); assertFalse(dismissed)
    }
}
