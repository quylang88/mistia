package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.saveable.SaverScope
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class RecurringBillEditorStateTest {
    private val zone=ZoneId.of("Asia/Tokyo")
    private val today=LocalDate.of(2026,10,13)
    private val owner="11111111-1111-1111-1111-111111111111"
    private val id="22222222-2222-2222-2222-222222222222"
    private val category="33333333-3333-3333-3333-333333333333"
    private val wallet="44444444-4444-4444-4444-444444444444"
    private fun ready()=RecurringBillEditorState.fresh(today,"JPY").copy(name=" Rent ",categoryId=category,paymentWalletId=wallet)

    @Test fun `blank optional amount remains null while exact Long amount survives draft`() {
        assertNull(ready().toDraft(zone).amountMinor)
        assertEquals("Rent",ready().toDraft(zone).name)
        assertEquals(9007199254740993L,ready().copy(amountText="9,007,199,254,740,993").toDraft(zone).amountMinor)
        assertEquals(-25L,ready().copy(amountText="-25").toDraft(zone).amountMinor)
        assertEquals(0L,ready().copy(amountText="0").toDraft(zone).amountMinor)
        listOf("invalid","9223372036854775808","1.5").forEach { text ->
            assertThrows(IllegalArgumentException::class.java) {ready().copy(amountText=text).toDraft(zone)}
        }
    }
    @Test fun `draft rejects missing name category wallet and invalid schedule`() {
        listOf(ready().copy(name=" "),ready().copy(categoryId=null),ready().copy(paymentWalletId=null),
            ready().copy(paymentStartDay=0),ready().copy(frequencyMonths=0)).forEach { state ->
            assertThrows(IllegalArgumentException::class.java) {state.toDraft(zone)}
        }
    }
    @Test fun `cross month auto pay options preserve window and invalid selection resets`() {
        val state=ready().copy(paymentStartDay=28,dueDay=3,hasDeadline=true,autoPayEnabled=true,autoPayDay=15)
        assertEquals(listOf(28,29,30,31,1,2,3),state.autoPayDayOptions)
        assertEquals(28,state.normalizedAutoPay().autoPayDay)
        assertEquals(2,state.copy(autoPayDay=2).normalizedAutoPay().autoPayDay)
        assertEquals(listOf(28),state.copy(hasDeadline=false).autoPayDayOptions)
    }
    @Test fun `one time start movement follows implicit due date and clamps auto pay`() {
        val state=ready().copy(scheduleKind=BillScheduleKind.ONE_TIME,autoPayEnabled=true)
        val moved=state.withPaymentStartDate(LocalDate.of(2026,10,20))
        assertEquals("2026-10-20",moved.dueDate)
        assertEquals("2026-10-20",moved.autoPayDate)
        val explicit=state.copy(hasDeadline=true,dueDate="2026-10-30",autoPayDate="2026-10-25")
            .withPaymentStartDate(LocalDate.of(2026,10,20))
        assertEquals("2026-10-30",explicit.dueDate)
        assertEquals("2026-10-25",explicit.autoPayDate)
        assertEquals("2026-10-30",explicit.copy(autoPayDate="2026-11-05").normalizedAutoPay().autoPayDate)
        assertEquals("2026-10-19T15:00:00Z",explicit.toDraft(zone).paymentStartDate)
        assertThrows(RecurringBillValidationException::class.java) {explicit.copy(dueDate="2026-10-19").toDraft(zone)}
    }
    @Test fun `existing draft preserves currency and edit identity with exact amount`() {
        val bill=bill()
        val state=RecurringBillEditorState.from(bill,today,zone)
        val draft=state.toDraft(zone)
        assertEquals(id,draft.id);assertTrue(draft.editingExisting)
        assertEquals("VND",draft.currencyCode)
        assertEquals(9007199254740993L,draft.amountMinor)
        assertEquals(28,draft.paymentStartDay)
        assertEquals(3,draft.dueDay)
        assertEquals(2,draft.autoPayDay)
        assertFalse(draft.startsNextMonth)
        assertEquals(state,state.withCurrency("JPY"))
        assertEquals("",ready().copy(amountText="500").withCurrency("VND").amountText)
    }
    @Test fun `saveable state keeps unsaved schedule and refuses foreign account`() {
        val state=ready().copy(name="Unsaved",scheduleKind=BillScheduleKind.ONE_TIME,hasDeadline=true,
            dueDate="2026-10-30",autoPayEnabled=true,autoPayDate="2026-10-25",startsNextMonth=true)
        val saver=RecurringBillEditorState.saver(owner)
        val saved=with(saver) {SaverScope {true}.save(state)}!!
        assertEquals(state,saver.restore(saved))
        assertNull(RecurringBillEditorState.saver(wallet).restore(saved))
    }
    @Test fun `one time imported local dates and optional amount round trip`() {
        val existing=bill().copy(scheduleKindWireValue="oneTime",paymentStartDate="2026-10-13T16:00:00Z",
            dueDate="2026-10-20T16:00:00Z",autoPayDate="2026-10-18T16:00:00Z",amountMinor=null)
        val state=RecurringBillEditorState.from(existing,today,zone)
        assertEquals("2026-10-14",state.paymentStartDate)
        assertEquals("2026-10-21",state.dueDate)
        assertEquals("2026-10-19",state.autoPayDate)
        val draft=state.toDraft(zone)
        assertEquals("2026-10-13T15:00:00Z",draft.paymentStartDate)
        assertEquals("2026-10-18T15:00:00Z",draft.autoPayDate)
        assertEquals(1,draft.frequencyMonths)
        assertNull(draft.autoPayDay)
        assertNull(draft.amountMinor)
    }
    @Test fun `legacy recurring defaults preserve valid frequency outside UI stepper range`() {
        val state=RecurringBillEditorState.from(bill().copy(paymentStartDay=null,autoPayDay=null,autoPayEnabled=null,
            hasExplicitDueDate=null,frequencyMonths=24),today,zone)
        val draft=state.toDraft(zone)
        assertEquals(3,draft.paymentStartDay)
        assertEquals(24,draft.frequencyMonths)
        assertFalse(draft.hasDeadline)
        assertFalse(draft.autoPayEnabled)
    }

    @Test fun `bill navigation preserves captured edit and cannot restore for another owner`() {
        val navigation=RecurringBillNavigationState(owner,true,bill().toPayload().toString())
        val saver=RecurringBillNavigationState.saver(owner)
        val saved=with(saver) {SaverScope {true}.save(navigation)}!!
        assertEquals(bill(),saver.restore(saved)!!.bill())
        assertNull(RecurringBillNavigationState.saver(wallet).restore(saved))
        assertNull(navigation.copy(owner=wallet).bill())
        assertNull(navigation.copy(payload="invalid").bill())
    }

    @Test fun `archived or deleted captured bill cannot open a mutable editor`() {
        assertNull(RecurringBillNavigationState(owner,true,bill().copy(isArchived=true).toPayload().toString()).bill())
        assertNull(RecurringBillNavigationState(owner,true,bill().copy(deletedAt="2026-10-13T00:00:00Z").toPayload().toString()).bill())
    }
    @Test fun `fractional imported currency amount round trips without changing minor units`() {
        val state=RecurringBillEditorState.from(bill().copy(currencyCode="USD",amountMinor=1250),today,zone)
        assertEquals("12.5",state.amountText)
        assertEquals(1250L,state.toDraft(zone).amountMinor)
        assertEquals(1375L,state.copy(amountText="13.75").toDraft(zone).amountMinor)
    }

    private fun bill()=RecurringBillPlanRecord(id,owner,"Rent","house.fill",category,9007199254740993L,3,"recurring",28,
        null,"2026-09-30T15:00:00Z",true,null,true,2,null,2,wallet,"VND",false,true,"2026-10-10T00:00:00Z",null,
        "2026-10-01T00:00:00Z","2026-10-13T00:00:00Z",null,99,wallet)
}
