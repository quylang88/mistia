package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.util.Currency
import kotlinx.serialization.json.JsonNull

data class CreditCardAccountReadSnapshot(val owner: UserId, val rows: List<CloudRecord>) {
    fun requireCoherent() {
        require(financeRawUuid(owner.value) == owner.value)
        require(rows.map { it.entity to it.id }.distinct().size == rows.size)
        for (row in rows) {
            val entity = requireNotNull(CloudEntity.fromTable(row.entity))
            require(entity in entities && row.financeRawIdentity(owner, entity, requireBodyIdentity = true))
            val payload = row.payload
            require(row.syncVersion >= 0 && payload.financeRawLong("sync_version") == row.syncVersion)
            require(row.updatedAt == payload.financeRawString("updated_at"))
            Instant.parse(requireNotNull(row.updatedAt))
            Instant.parse(requireNotNull(payload.financeRawString("created_at")))
            require(payload.containsKey("deleted_at"))
            val deletion = if (payload["deleted_at"] == JsonNull) null else requireNotNull(payload.financeRawString("deleted_at"))
            deletion?.let(Instant::parse)
            require(deletion == row.deletedAt)
            val money = when (entity) {
                CloudEntity.LEDGER_WALLET -> "opening_balance_minor"
                CloudEntity.CREDIT_CARD_PROFILE -> "credit_limit_minor"
                CloudEntity.LEDGER_TRANSACTION -> "amount_minor"
                else -> error("Unsupported card read entity")
            }
            val amount = requireNotNull(payload.financeRawLong(money))
            if (entity == CloudEntity.LEDGER_TRANSACTION) require(amount >= 0)
            if (entity != CloudEntity.CREDIT_CARD_PROFILE) require(payload.financeRawArchived() != null)
            if (entity == CloudEntity.LEDGER_TRANSACTION && payload.financePresent("destination_amount_minor"))
                require(requireNotNull(payload.financeRawLong("destination_amount_minor")) >= 0)
        }
    }

    companion object {
        val entities = setOf(CloudEntity.LEDGER_WALLET, CloudEntity.CREDIT_CARD_PROFILE, CloudEntity.LEDGER_TRANSACTION)
    }
}

data class PlanningCreditCardAccount(
    val wallet: LedgerWalletRecord,
    val profile: CreditCardProfileRecord,
    val currentDebtMinor: Long,
    val availableCreditMinor: Long,
    val paymentSourceWalletName: String?,
    val network: CreditCardNetwork,
    val last4: String,
) {
    val currencyCode: String get() = requireNotNull(wallet.currencyCode.financeReportingCode())
}

fun planningCreditCardAccounts(snapshot: CreditCardAccountReadSnapshot): List<PlanningCreditCardAccount> {
    snapshot.requireCoherent()
    val wallets = snapshot.rows.filter { it.entity == CloudEntity.LEDGER_WALLET.table }.map(LedgerWalletRecord::fromCloudRecord)
    val profiles = snapshot.rows.filter { it.entity == CloudEntity.CREDIT_CARD_PROFILE.table }.map(CreditCardProfileRecord::fromCloudRecord)
    val transactions = snapshot.rows.filter { it.entity == CloudEntity.LEDGER_TRANSACTION.table }.map(LedgerTransactionRecord::fromCloudRecord)
    val cards = wallets.filter { it.kind == WalletKind.CREDIT_CARD && !it.isArchived && it.deletedAt == null && it.systemPurposeRawValue == null }
    val cardIds = cards.map { it.id }.toSet()
    for (transaction in transactions.filter { !it.isArchived && it.deletedAt == null &&
        (it.sourceWalletId in cardIds || it.destinationWalletId in cardIds) }) {
        require(transaction.entryStatus != null && transaction.primaryKind != null)
        if (transaction.primaryKind == TransactionPrimaryKind.TRANSFER) {
            require(transaction.transferSubtype != null)
            if (transaction.transferSubtype == TransactionTransferSubtype.DEBT) require(transaction.debtIntent != null)
        }
    }
    val balances = TransactionWalletBalanceIndex(wallets, transactions)
    val byWallet = profiles.filter { it.deletedAt == null }.groupBy { it.walletId }
    return cards.mapNotNull { wallet ->
        val matches = byWallet[wallet.id].orEmpty()
        require(matches.size <= 1) { "Ambiguous card profile" }
        val profile = matches.singleOrNull() ?: return@mapNotNull null
        require(profile.creditLimitMinor >= 0)
        val currency = requireNotNull(wallet.currencyCode.financeReportingCode())
        require(Currency.getInstance(currency).defaultFractionDigits >= 0)
        val debt = maxOf(balances.balance(wallet.id), 0L)
        val source = wallets.singleOrNull { it.id == profile.paymentSourceWalletId && it.deletedAt == null &&
            it.kind != null && it.kind !in setOf(WalletKind.CREDIT_CARD, WalletKind.INVESTMENT) && it.systemPurposeRawValue == null }
        PlanningCreditCardAccount(wallet, profile, debt, maxOf(profile.creditLimitMinor - debt, 0L),
            source?.name?.trim()?.takeIf { it.isNotEmpty() }, profile.network ?: CreditCardNetwork.OTHER,
            profile.last4.takeLast(4).takeIf { last -> last.all { it in '0'..'9' } }.orEmpty())
    }.sortedWith(compareBy<PlanningCreditCardAccount> { it.wallet.sortOrder }
        .thenBy { Instant.parse(it.wallet.createdAt) }.thenBy { it.wallet.id })
}
