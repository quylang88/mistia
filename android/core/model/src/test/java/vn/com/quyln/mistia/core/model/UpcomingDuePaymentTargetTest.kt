package vn.com.quyln.mistia.core.model

import java.time.YearMonth
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class UpcomingDuePaymentTargetTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val id="22222222-2222-2222-2222-222222222222"
    @Test fun `restoration preserves source cycle and encodes no financial default`() {
        for(kind in listOf(DueSourceKind.RECURRING_BILL,DueSourceKind.INSTALLMENT)) {
            val target=UpcomingDuePaymentTarget(owner.value,kind,id,YearMonth.of(2026,9))
            assertEquals(target,UpcomingDuePaymentTarget.restore(owner,target.navigationToken()))
            assertEquals(setOf("owner","kind","source","month"),Json.parseToJsonElement(target.navigationToken()).jsonObject.keys)
            assertNull(UpcomingDuePaymentTarget.restore(other,target.navigationToken()))
        }
    }
    @Test fun `malformed unsupported and wrong owner targets cannot open a source`() {
        val base=Json.parseToJsonElement(UpcomingDuePaymentTarget(owner.value,DueSourceKind.RECURRING_BILL,id,YearMonth.of(2026,10)).navigationToken()).jsonObject
        for((key,value) in listOf("owner" to JsonPrimitive(other.value),"kind" to JsonPrimitive("creditCard"),"kind" to JsonPrimitive("futureKind"),"source" to JsonPrimitive("bad"),"month" to JsonPrimitive("2026-13"),"month" to JsonPrimitive(10)))
            assertNull(UpcomingDuePaymentTarget.restore(owner,JsonObject(base+(key to value)).toString()))
        assertNull(UpcomingDuePaymentTarget.restore(owner,null));assertNull(UpcomingDuePaymentTarget.restore(owner,"broken"))
    }
}
