package vn.com.quyln.mistia.core.model

import java.time.*
import java.util.Locale
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class UpcomingRecurringDuesTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val zone=ZoneId.of("Asia/Tokyo")
    private val reference=Instant.parse("2026-10-21T03:00:00Z")
    private val month=YearMonth.of(2026,10)
    private val created="2026-01-01T00:00:00Z"
    private fun id(number:Int)="22222222-2222-2222-2222-"+number.toString().padStart(12,'0')
    private fun bill(number:Int=1,day:Int=22,amount:Long?=5000,code:String="JPY",name:String="Internet")=RecurringBillPlanRecord(
        id(number),owner.value,name,"wifi",null,amount,day,"recurring",day,null,created,false,null,false,null,null,1,null,code,false,false,null,null,created,created,null,0,null)
    private fun installment(number:Int=20,day:Int=22,amount:Long=6000,code:String="JPY")=InstallmentPlanRecord(
        id(number),owner.value,"Loan","banknote",amount,day,null,1,null,code,false,created,created,null,0,null)
    private fun occurrence(source:String=id(1),kind:String="recurringBill",status:String="pending",amount:Long?=5000,cycle:YearMonth=month)=DueOccurrenceRecord(
        id(80),owner.value,kind,source,cycle.toString(),cycle.atDay(22).atStartOfDay(zone).toInstant().toString(),amount,status,null,null,created,created,null,0,null)
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    private fun project(vararg rows:CloudRecord,at:Instant=reference,tz:ZoneId=zone)=projectUpcomingRecurringDues(owner,UpcomingDueReadSnapshot(owner,rows.toList()),at,tz,Locale.ENGLISH)
    @Test fun `pending bill and installment retain their own exact source amounts and currency`() {
        val bill=bill(amount=9007199254740993L,code="VND");val loan=installment(amount=Long.MAX_VALUE)
        val rows=project(bill.toCloudRecord(),loan.toCloudRecord())!!
        assertEquals(2,rows.size);assertEquals(setOf(DueSourceKind.RECURRING_BILL,DueSourceKind.INSTALLMENT),rows.map {it.sourceKind}.toSet())
        assertEquals(9007199254740993L,rows.single {it.sourceId==bill.id}.amountMinor)
        assertEquals("VND",rows.single {it.sourceId==bill.id}.currencyCode)
        assertEquals(Long.MAX_VALUE,rows.single {it.sourceId==loan.id}.amountMinor)
        assertEquals(1,rows.first().dayDelta);assertEquals(month,rows.first().month)
    }
    @Test fun `local window includes today through seven days and preserves urgency boundary`() {
        for((day,delta) in listOf(21 to 0,24 to 3,25 to 4,28 to 7)) {
            val row=project(bill(day=day).toCloudRecord())!!.single()
            assertEquals(delta,row.dayDelta);assertEquals(delta<=3,row.urgent)
        }
        assertTrue(project(bill(day=20).toCloudRecord(),bill(number=2,day=29).toCloudRecord())!!.isEmpty())
    }
    @Test fun `payment opening is shown before start and deadline replaces it after opening`() {
        val source=bill(day=28).copy(paymentStartDay=23,hasExplicitDueDate=true)
        val before=project(source.toCloudRecord())!!.single()
        assertEquals(LocalDate.of(2026,10,23),before.alertDate.atZone(zone).toLocalDate());assertEquals(2,before.dayDelta)
        val opened=project(source.toCloudRecord(),at=Instant.parse("2026-10-23T03:00:00Z"))!!.single()
        assertEquals(LocalDate.of(2026,10,28),opened.alertDate.atZone(zone).toLocalDate());assertEquals(5,opened.dayDelta)
    }
    @Test fun `previous and current unpaid cycles of one source keep distinct identity and payment month`() {
        val source=bill(day=24).copy(paymentStartDay=25,hasExplicitDueDate=true)
        val rows=project(source.toCloudRecord())!!
        assertEquals(listOf(3,4),rows.map {it.dayDelta});assertEquals(listOf(month.minusMonths(1),month),rows.map {it.month})
        assertEquals(2,rows.map {it.id}.toSet().size);assertEquals(setOf(source.id),rows.map {it.sourceId}.toSet())
    }
    @Test fun `local date arithmetic spans DST without treating seven calendar days as six`() {
        val la=ZoneId.of("America/Los_Angeles")
        val rows=project(bill(day=14).toCloudRecord(),at=Instant.parse("2026-03-07T20:00:00Z"),tz=la)!!
        assertEquals(7,rows.single().dayDelta);assertFalse(rows.single().urgent)
    }
    @Test fun `sources sort by actual alert date then locale name and stop at three`() {
        val rows=project(bill(number=4,day=28,name="Last").toCloudRecord(),bill(number=3,day=23,name="Next").toCloudRecord(),
            bill(number=2,day=22,name="Zulu").toCloudRecord(),bill(number=1,day=22,name="Alpha").toCloudRecord())!!
        assertEquals(listOf("Alpha","Zulu","Next"),rows.map {it.name})
    }
    @Test fun `intentional variable bill is no amount yet while unreadable required money is unavailable`() {
        val row=project(bill(amount=null).toCloudRecord())!!.single()
        assertNull(row.amountMinor);assertTrue(row.requiresAmountInput)
        for(value in listOf(JsonPrimitive("5000"),buildJsonObject {},Json.parseToJsonElement("9223372036854775808")))
            assertNull(project(bill().toCloudRecord().with("amount_minor",value)))
        assertNull(project(installment().toCloudRecord().with("amount_per_cycle_minor",JsonPrimitive("6000"))))
        assertNull(project(bill().toCloudRecord().with("currency_code",JsonPrimitive("???"))))
        assertEquals(1375L,project(bill(amount=1375,code="USD").toCloudRecord())!!.single().amountMinor)
    }
    @Test fun `paid skipped archived paused deleted and foreign inputs cannot become current alerts`() {
        for(status in listOf("paid","skipped")) assertTrue(project(bill().toCloudRecord(),occurrence(status=status).toCloudRecord())!!.isEmpty())
        assertTrue(project(bill().copy(isArchived=true).toCloudRecord(),installment().copy(isArchived=true).toCloudRecord())!!.isEmpty())
        assertTrue(project(bill().copy(isPaused=true).toCloudRecord(),installment().copy(deletedAt=created).toCloudRecord(),bill(number=2).copy(ownerUserId=other).toCloudRecord())!!.isEmpty())
        assertTrue(project(bill().copy(isArchived=true).toCloudRecord().with("amount_minor",JsonPrimitive("broken")))!!.isEmpty())
    }
    @Test fun `unknown source schedule and cycle classification cannot masquerade as ordinary pending`() {
        assertNull(project(bill().copy(scheduleKindWireValue="futureSchedule").toCloudRecord()))
        assertNull(project(bill().toCloudRecord(),occurrence(status="futureStatus").toCloudRecord()))
        assertNull(project(bill().toCloudRecord(),occurrence(kind="futureKind").toCloudRecord()))
        assertNull(project(bill().toCloudRecord(),occurrence().toCloudRecord().with("amount_minor_snapshot",JsonPrimitive("5000"))))
        assertEquals(1,project(bill().copy(scheduleKindWireValue=null).toCloudRecord())!!.size)
        val credit=occurrence(kind="creditCard").toCloudRecord().with("amount_minor_snapshot",JsonPrimitive("broken"))
        assertEquals(1,project(bill().toCloudRecord(),credit)!!.size)
    }
    @Test fun `pending occurrence supplies exact cycle amount instead of current default`() {
        val row=project(bill().toCloudRecord(),occurrence(amount=9007199254740993L).toCloudRecord())!!.single()
        assertEquals(9007199254740993L,row.amountMinor);assertFalse(row.requiresAmountInput)
        assertEquals(6000L,project(installment().toCloudRecord(),occurrence(source=id(20),kind="installment",amount=6000).toCloudRecord())!!.single().amountMinor)
    }
    @Test fun `wrong snapshot owner and withheld read are unavailable while loaded empty is known`() {
        assertNull(projectUpcomingRecurringDues(owner,null,reference,zone))
        assertNull(projectUpcomingRecurringDues(owner,UpcomingDueReadSnapshot(UserId(other),listOf(bill().toCloudRecord())),reference,zone))
        assertTrue(project()!!.isEmpty())
        val foreign=bill().toCloudRecord().copy(ownerUserId=other)
        assertEquals(1,project(foreign,bill().toCloudRecord())!!.size)
    }
    @Test fun `crossing month keeps source cycle and does not invent next month installment`() {
        val source=bill(day=3).copy(paymentStartDay=31,hasExplicitDueDate=true)
        val rows=project(source.toCloudRecord(),installment(day=2).toCloudRecord(),at=Instant.parse("2026-10-29T03:00:00Z"))!!
        assertEquals(1,rows.size);assertEquals(month,rows.single().month)
        assertEquals(LocalDate.of(2026,10,31),rows.single().alertDate.atZone(zone).toLocalDate())
    }
}
