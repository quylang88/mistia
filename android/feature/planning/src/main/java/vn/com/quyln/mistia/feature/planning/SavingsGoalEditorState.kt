package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.saveable.listSaver
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Currency
import vn.com.quyln.mistia.core.model.*

data class SavingsGoalEditorState(
    val id:String?, val name:String, val targetText:String, val currentText:String,
    val targetDate:String, val originalTargetDate:String?, val currencyCode:String,
    val iconSymbolName:String, val linkedWalletId:String?,
) {
    fun toDraft(zone:ZoneId):SavingsGoalDraft {
        val trimmed=name.trim().takeIf { it.isNotEmpty() } ?: throw SavingsGoalValidationException(SavingsGoalValidationError.NAME_REQUIRED)
        fun parse(text:String,emptyZero:Boolean):Long {
            if(emptyZero && text.isBlank()) return 0
            return runCatching {
                BigDecimal(text.trim().replace(",","")).movePointRight(Currency.getInstance(currencyCode).defaultFractionDigits.coerceAtLeast(0))
                    .setScale(0,RoundingMode.UNNECESSARY).longValueExact()
            }.getOrElse { throw IllegalArgumentException("Invalid savings amount",it) }
        }
        val target=parse(targetText,false)
        if(target<=0) throw SavingsGoalValidationException(SavingsGoalValidationError.INVALID_TARGET)
        val date=LocalDate.parse(targetDate)
        val timestamp=originalTargetDate?.takeIf { Instant.parse(it).atZone(zone).toLocalDate()==date }
            ?: date.atStartOfDay(zone).toInstant().toString()
        return SavingsGoalDraft(trimmed,target,parse(currentText,true),timestamp,currencyCode,id,id!=null,linkedWalletId,iconSymbolName)
    }
    companion object {
        fun fresh(date:LocalDate,currency:String)=SavingsGoalEditorState(null,"","","",date.toString(),null,currency,"mistia.goal.savings",null)
        fun from(goal:SavingsGoalRecord,zone:ZoneId):SavingsGoalEditorState {
            val digits=runCatching { Currency.getInstance(goal.currencyCode).defaultFractionDigits.coerceAtLeast(0) }.getOrDefault(0)
            fun text(value:Long)=BigDecimal.valueOf(value,digits).stripTrailingZeros().toPlainString()
            return SavingsGoalEditorState(goal.id,goal.name,text(goal.targetMinor),text(goal.currentSavedMinor),
                Instant.parse(goal.targetDate).atZone(zone).toLocalDate().toString(),goal.targetDate,goal.currencyCode,goal.iconSymbolName,goal.linkedWalletId)
        }
        fun saver(owner:String)=listSaver<SavingsGoalEditorState,Any>(
            save={ listOf(owner,it.id.orEmpty(),it.name,it.targetText,it.currentText,it.targetDate,it.originalTargetDate.orEmpty(),it.currencyCode,it.iconSymbolName,it.linkedWalletId.orEmpty()) },
            restore={ if(it.size!=10 || it[0]!=owner) null else SavingsGoalEditorState((it[1] as String).ifEmpty { null },it[2] as String,it[3] as String,it[4] as String,
                it[5] as String,(it[6] as String).ifEmpty { null },it[7] as String,it[8] as String,(it[9] as String).ifEmpty { null }) },
        )
    }
}

data class SavingsGoalNavigationState(val owner:String,val open:Boolean,val payload:String?) {
    fun goal():SavingsGoalRecord?=runCatching {
        val json=kotlinx.serialization.json.Json.parseToJsonElement(requireNotNull(payload)) as kotlinx.serialization.json.JsonObject
        val id=(json["id"] as kotlinx.serialization.json.JsonPrimitive).content
        SavingsGoalRecord.fromCloudRecord(CloudRecord(CloudEntity.SAVINGS_GOAL.table,id,owner,json,null,null,0)).takeIf { it.ownerUserId==owner }
    }.getOrNull()
    companion object {
        fun saver(owner:String)=listSaver<SavingsGoalNavigationState,Any>(
            save={ listOf(it.owner,it.open,it.payload.orEmpty()) },
            restore={ if(it.size!=3 || it[0]!=owner) null else SavingsGoalNavigationState(owner,it[1] as Boolean,(it[2] as String).ifEmpty { null }) },
        )
    }
}
