package vn.com.quyln.mistia.feature.overview

import java.time.Instant
import java.util.Locale
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull
import vn.com.quyln.mistia.core.model.*

internal data class OverviewRecentRow(val transaction: LedgerTransactionRecord, val money: Money)

/** Only eligibility dependencies are inspected; an explicit source currency needs no wallet fallback. */
internal fun overviewRecentHasUncertainDeletion(owner:UserId,records:List<CloudRecord>,wallets:List<CloudRecord>):Boolean =
    records.any {raw ->
        if(!raw.financeRawIdentity(owner,CloudEntity.LEDGER_TRANSACTION,true) || raw.financeRawDeleted()==true ||
            raw.payload.financeRawArchived()==true || raw.payload.financeRawString("entry_status_raw_value")=="draft" ||
            raw.payload.financeRawString("settlement_role_raw_value")?.startsWith("investment")==true) false
        else raw.financeRawDeleted()==null || recentWalletDeletionUncertain(owner,raw,wallets)
    }

private fun recentWalletDeletionUncertain(owner:UserId,raw:CloudRecord,wallets:List<CloudRecord>):Boolean {
    if(!raw.payload.financeRawString("source_currency_code").isNullOrBlank()) return false
    val source=raw.payload.financeRawReference("source_wallet_id").id ?: return false
    return wallets.any {it.financeRawIdentity(owner,CloudEntity.LEDGER_WALLET,true) && financeRawUuid(it.id)==source && it.financeRawDeleted()==null}
}

/** Swift OverviewLogic.recentTransactions uses the original source leg, never the reporting pair. */
internal fun overviewRecentTransactions(
    owner: UserId,
    records: List<CloudRecord>,
    wallets: List<CloudRecord>,
    primaryCurrency: String,
): List<OverviewRecentRow> {
    val primary = primaryCurrency.code()?.takeIf { it in CurrencyPreferences.supportedCurrencyCodes } ?: "JPY"
    val walletCurrencies = wallets.mapNotNull { raw ->
        if (!raw.financeRawIdentity(owner,CloudEntity.LEDGER_WALLET,true) || raw.financeRawDeleted()!=false) null
        else runCatching { LedgerWalletRecord.fromCloudRecord(raw) }.getOrNull()
            ?.takeIf { it.ownerUserId == owner.value && it.id == raw.id && it.deletedAt == null }
            ?.let { wallet -> wallet.currencyCode.code()?.let { wallet.id to it } }
    }.toMap()
    data class DatedRow(val row: OverviewRecentRow, val occurredAt: Instant, val createdAt: Instant)
    return records.mapNotNull { raw ->
        if (!raw.financeRawIdentity(owner,CloudEntity.LEDGER_TRANSACTION,true) || raw.financeRawDeleted()!=false || recentWalletDeletionUncertain(owner,raw,wallets)) return@mapNotNull null
        val amount = (raw.payload["amount_minor"] as? JsonPrimitive)?.longOrNull ?: return@mapNotNull null
        val archived = raw.payload["is_archived"]
        if (archived != null && (archived as? JsonPrimitive)?.booleanOrNull != false) return@mapNotNull null
        if ((raw.payload["settlement_role_raw_value"] as? JsonPrimitive)?.contentOrNull?.startsWith("investment") == true) return@mapNotNull null
        val transaction = runCatching { LedgerTransactionRecord.fromCloudRecord(raw) }.getOrNull()
            ?.takeIf { it.ownerUserId == owner.value && it.id == raw.id && it.deletedAt == null && !it.isArchived &&
                it.entryStatus == TransactionEntryStatus.POSTED && it.primaryKind != null } ?: return@mapNotNull null
        val occurred = runCatching { Instant.parse(transaction.occurredAt) }.getOrNull() ?: return@mapNotNull null
        val created = runCatching { Instant.parse(transaction.createdAt) }.getOrNull() ?: return@mapNotNull null
        val currency = transaction.sourceCurrencyCode?.takeIf(String::isNotBlank)?.let { it.code() ?: return@mapNotNull null }
            ?: walletCurrencies[transaction.sourceWalletId] ?: primary
        DatedRow(OverviewRecentRow(transaction, Money(amount, currency)), occurred, created)
    }.sortedWith(compareByDescending<DatedRow> { it.occurredAt }.thenByDescending { it.createdAt })
        .take(5).map { it.row }
}

private fun String.code(): String? = trim().uppercase(Locale.ROOT).takeIf { it.matches(Regex("[A-Z]{3}")) }
