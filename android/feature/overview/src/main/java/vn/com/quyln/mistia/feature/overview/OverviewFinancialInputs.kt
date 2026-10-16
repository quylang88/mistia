package vn.com.quyln.mistia.feature.overview

import java.time.Instant
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

/** Validate raw financial inputs before permissive legacy typed decoders can substitute values. */
internal data class OverviewFinancialInputs(val records:List<LedgerTransactionRecord>,val wallets:List<LedgerWalletRecord>)

internal fun overviewFinancialInputs(owner:UserId,records:List<CloudRecord>,wallets:List<CloudRecord>):OverviewFinancialInputs {
    val ownedRecords=records.mapNotNull {raw ->
        if(raw.entity!=CloudEntity.LEDGER_TRANSACTION.table || raw.ownerUserId!=owner.value || raw.deletedAt!=null) return@mapNotNull null
        if((raw.payload["amount_minor"] as? JsonPrimitive)?.longOrNull==null) return@mapNotNull null
        for(key in listOf("reporting_expense_minor","reporting_income_minor","destination_amount_minor")) {
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
        else {
            if((raw.payload["opening_balance_minor"] as? JsonPrimitive)?.longOrNull==null) return@mapNotNull null
            val archived=raw.payload["is_archived"]
            if(archived!=null && (archived as? JsonPrimitive)?.booleanOrNull==null) return@mapNotNull null
            runCatching {LedgerWalletRecord.fromCloudRecord(raw)}.getOrNull()?.takeIf {it.id==raw.id && it.ownerUserId==owner.value && it.deletedAt==null && it.kind!=null}
        }
    }
    return OverviewFinancialInputs(ownedRecords,ownedWallets)
}
