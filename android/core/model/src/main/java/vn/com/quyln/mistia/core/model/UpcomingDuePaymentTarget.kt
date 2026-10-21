package vn.com.quyln.mistia.core.model

import java.time.YearMonth
import kotlinx.serialization.json.*

/** Saved navigation contains identity only; payment always reloads current source money. */
data class UpcomingDuePaymentTarget(val ownerUserId:String,val sourceKind:DueSourceKind,val sourceId:String,val month:YearMonth) {
    init {
        require(financeRawUuid(ownerUserId)==ownerUserId && financeRawUuid(sourceId)==sourceId)
        require(sourceKind==DueSourceKind.RECURRING_BILL || sourceKind==DueSourceKind.INSTALLMENT)
    }
    fun navigationToken():String=buildJsonObject {
        put("owner",ownerUserId);put("kind",sourceKind.wireValue);put("source",sourceId);put("month",month.toString())
    }.toString()
    companion object {
        fun restore(owner:UserId,token:String?):UpcomingDuePaymentTarget?=runCatching {
            val payload=Json.parseToJsonElement(requireNotNull(token)).jsonObject
            require(payload.financeRawString("owner")==owner.value)
            val kind=DueSourceKind.entries.single {it.wireValue==payload.financeRawString("kind")}
            UpcomingDuePaymentTarget(owner.value,kind,requireNotNull(payload.financeRawString("source")),YearMonth.parse(payload.financeRawString("month")))
        }.getOrNull()
    }
}
fun UpcomingRecurringDueAlert.paymentTarget()=UpcomingDuePaymentTarget(ownerUserId,sourceKind,sourceId,month)
