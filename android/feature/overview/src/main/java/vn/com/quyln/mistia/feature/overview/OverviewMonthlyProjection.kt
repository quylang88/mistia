package vn.com.quyln.mistia.feature.overview

import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

/** Validate raw financial inputs before permissive legacy typed decoders can substitute values. */
internal fun overviewMonthlyProjection(owner:UserId,records:List<CloudRecord>,wallets:List<CloudRecord>,currency:String,
    rates:List<ExchangeRateSnapshot>,titles:Map<GeneratedTransactionTitle,Collection<String>>,reference:Instant,zone:ZoneId):List<OverviewMonthlyCashflow> {
    val ownedRecords=records.mapNotNull {raw ->
        if(raw.entity!=CloudEntity.LEDGER_TRANSACTION.table || raw.ownerUserId!=owner.value || raw.deletedAt!=null) return@mapNotNull null
        if((raw.payload["amount_minor"] as? JsonPrimitive)?.longOrNull==null) return@mapNotNull null
        for(key in listOf("reporting_expense_minor","reporting_income_minor")) {
            val value=raw.payload[key]
            if(value!=null && value!=JsonNull && (value as? JsonPrimitive)?.longOrNull==null) return@mapNotNull null
        }
        val archived=raw.payload["is_archived"]
        if(archived!=null && (archived as? JsonPrimitive)?.booleanOrNull!=false) return@mapNotNull null
        runCatching {LedgerTransactionRecord.fromCloudRecord(raw)}.getOrNull()?.takeIf {record ->
            record.id==raw.id && record.ownerUserId==owner.value &&
                runCatching {Instant.parse(record.occurredAt);Instant.parse(record.createdAt);true}.getOrDefault(false)
        }
    }
    val ownedWallets=wallets.mapNotNull {raw ->
        if(raw.entity!=CloudEntity.LEDGER_WALLET.table || raw.ownerUserId!=owner.value || raw.deletedAt!=null) null
        else runCatching {LedgerWalletRecord.fromCloudRecord(raw)}.getOrNull()?.takeIf {it.id==raw.id && it.ownerUserId==owner.value && it.deletedAt==null}
    }
    return overviewMonthlyCashflow(owner,ownedRecords,ownedWallets,currency,rates,titles,reference,zone)
}
