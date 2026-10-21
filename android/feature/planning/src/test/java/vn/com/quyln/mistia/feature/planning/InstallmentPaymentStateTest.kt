package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.saveable.SaverScope
import java.time.Instant
import java.time.YearMonth
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InstallmentPaymentStateTest {
    private val owner = "11111111-1111-1111-1111-111111111111"
    private val id = "22222222-2222-2222-2222-222222222222"
    private val walletId = "33333333-3333-3333-3333-333333333333"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val time = "2026-10-15T00:00:00Z"
    private val month = YearMonth.of(2026, 10)
    private fun plan(currency: String = "JPY") = InstallmentPlanRecord(id, owner, "Loan", "mistia.plan.loan", 9007199254740993, 15, 12, 1, walletId, currency, false, time, time, null, 9007199254740995, walletId)
    private fun row(currency: String = "JPY") = InstallmentDueRow(plan(currency), month, Instant.parse(time), 9007199254740993, DueStatus.PENDING, null)
    private fun wallet(currency: String = "JPY") = LedgerWalletRecord.fromCloudRecord(WalletDraft(id = walletId, name = "Cash", kind = WalletKind.CASH, currencyCode = currency).toMutation(UserId(owner), null, id, time).record)
    private fun state(currency: String = "JPY") = InstallmentPaymentState.initial(owner, row(currency), listOf(wallet(currency)))
    private fun rejects(block: () -> Unit) { assertTrue(runCatching(block).isFailure) }
    @Test fun `request carries visible effective cycle amount independently of plan default`() {
        val due=row().copy(amountMinor=6000)
        val request=InstallmentPaymentState.initial(owner,due,listOf(wallet())).request(due,listOf(wallet()))
        assertEquals(due.plan,request.expected);assertEquals(6000L,request.expectedDueAmountMinor)
        assertEquals(6000L,request.amountMinorOverride)
    }
    @Test fun `form keeps exact source amount and Long version without converting major units`() {
        for (currency in listOf("JPY", "VND", "USD")) {
            val state = state(currency); val request = state.request(row(currency), listOf(wallet(currency)))
            assertEquals("9,007,199,254,740,993", state.amountText); assertEquals(9007199254740993L, request.amountMinorOverride)
            assertEquals(plan(currency), request.expected); assertEquals(9007199254740995L, request.expected.syncVersion); assertFalse(state.changed)
            rejects { state.copy(amountText = "1,375").request(row(currency), listOf(wallet(currency))) }
        }
    }
    @Test fun `payment picker excludes foreign currency card investment unknown archived and deleted wallets`() {
        val cash = wallet(); val invalid = listOf(cash.copy(id = other, currencyCode = "VND"), cash.copy(id = other, ownerUserId = other),
            cash.copy(id = other, kindWireValue = "creditCard"), cash.copy(id = other, kindWireValue = "investment"), cash.copy(id = other, kindWireValue = "future"),
            cash.copy(id = other, isArchived = true), cash.copy(id = other, deletedAt = time))
        assertEquals(listOf(cash), eligibleInstallmentPaymentWallets(owner, " jpy ", invalid + cash))
        assertNull(InstallmentPaymentState.initial(owner, row("VND"), listOf(cash)).walletId)
    }
    @Test fun `restored selected wallet is revalidated for currency owner and availability`() {
        val state = state()
        for (changed in listOf(wallet("VND"), wallet().copy(ownerUserId = other), wallet().copy(isArchived = true), wallet().copy(deletedAt = time)))
            rejects { state.request(row(), listOf(changed)) }
        rejects { state.copy(walletId = null).request(row(), listOf(wallet())) }
    }
    @Test fun `invalid fractional exponent signed zero overflow and malformed amount are rejected`() {
        for (text in listOf("", "0", "-1", "13.75", "1e3", "+123", "9223372036854775808", "1x00"))
            rejects { state().copy(amountText = text).request(row(), listOf(wallet())) }
    }
    @Test fun `state cannot target another source owner currency month or settled cycle`() {
        val s = state(); val row = row()
        for (changed in listOf(row.copy(plan = plan().copy(id = other)), row.copy(plan = plan().copy(ownerUserId = other)), row.copy(plan = plan("VND")),
            row.copy(month = month.plusMonths(1)), row.copy(status = DueStatus.PAID), row.copy(status = DueStatus.SKIPPED), row.copy(linkedTransactionId = other)))
            rejects { s.request(changed, listOf(wallet())) }
    }
    @Test fun `only wallet changes create a dirty payment form`() {
        val s = state(); assertFalse(s.changed); assertFalse(s.copy(amountText = "100").changed); assertTrue(s.copy(walletId = other).changed)
        assertFalse(s.copy(amountText = "100").copy(amountText = s.initialAmountText).changed)
    }
    @Test fun `form saver retains wallet choice and original dirty baseline only in same owner source month`() {
        val state = state().copy(walletId = null); val saver = InstallmentPaymentState.saver(owner, id, month.toString())
        val saved = with(saver) { SaverScope { true }.save(state) }!!
        assertEquals(state, saver.restore(saved)); assertTrue(saver.restore(saved)!!.changed)
        assertNull(InstallmentPaymentState.saver(other, id, month.toString()).restore(saved)); assertNull(InstallmentPaymentState.saver(owner, other, month.toString()).restore(saved))
        assertNull(InstallmentPaymentState.saver(owner, id, month.plusMonths(1).toString()).restore(saved)); assertNull(saver.restore(listOf("bad")))
    }
    @Test fun `navigation saver restores original paid history or pending source baseline with exact amount`() {
        for (status in listOf(DueStatus.PENDING, DueStatus.PAID)) {
            val row = row().copy(status = status, linkedTransactionId = if (status == DueStatus.PAID) other else null)
            val navigation = InstallmentPaymentNavigation.open(owner, row)
            val saver = InstallmentPaymentNavigation.saver(owner, month); val saved = with(saver) { SaverScope { true }.save(navigation) }!!
            assertEquals(row, saver.restore(saved)!!.row()); assertNull(InstallmentPaymentNavigation.saver(other, month).restore(saved))
            assertNull(InstallmentPaymentNavigation.saver(owner, month.plusMonths(1)).restore(saved))
        }
    }
    @Test fun `navigation rejects foreign malformed and skipped targets instead of restoring a payment`() {
        rejects { InstallmentPaymentNavigation.open(owner, row().copy(plan = plan().copy(ownerUserId = other))) }
        rejects { InstallmentPaymentNavigation.open(owner, row().copy(status = DueStatus.SKIPPED)) }
        assertNull(InstallmentPaymentNavigation(owner, month.toString(), "not-json", 100, time, "pending").row())
        assertNull(InstallmentPaymentNavigation.closed(owner, month).row())
    }
    @Test fun `confirmation cannot retain a changed source currency or schedule under equal cycle amount`() {
        val frozen=row()
        for(source in listOf(frozen.plan.copy(currencyCode="USD"),frozen.plan.copy(frequencyMonths=3),frozen.plan.copy(paymentWalletId=other)))
            assertFalse(source.toString(),installmentPaymentTargetIsCurrent(frozen,frozen.copy(plan=source)))
    }
    @Test fun `confirmation target rejects missing or changed frozen cycle but accepts metadata only ACK`() {
        val frozen = row().copy(status = DueStatus.PAID, linkedTransactionId = other)
        assertTrue(installmentPaymentTargetIsCurrent(frozen, frozen.copy(plan = frozen.plan.copy(syncVersion = 1, updatedAt = "2026-10-15T01:00:00Z"))))
        for (changed in listOf(null, frozen.copy(amountMinor = 1), frozen.copy(status = DueStatus.PENDING, linkedTransactionId = null),
            frozen.copy(linkedTransactionId = walletId), frozen.copy(month = month.plusMonths(1)), frozen.copy(plan = plan().copy(id = other)),
            frozen.copy(plan = plan().copy(ownerUserId = other)), frozen.copy(dueDate = frozen.dueDate.plusSeconds(1))))
            assertFalse(installmentPaymentTargetIsCurrent(frozen, changed))
    }

}
