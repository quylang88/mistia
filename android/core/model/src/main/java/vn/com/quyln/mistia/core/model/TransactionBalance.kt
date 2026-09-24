package vn.com.quyln.mistia.core.model

class TransactionWalletBalanceIndex(
    wallets: List<LedgerWalletRecord>,
    records: List<LedgerTransactionRecord>,
    excludingTransactionId: String? = null,
) {
    private val balancesByWalletId: Map<String, Long>

    init {
        val walletKinds = wallets.associate { it.id to it.kind }
        val balances = wallets.associate { wallet ->
            wallet.id to if (wallet.kind == WalletKind.CREDIT_CARD) 0L else wallet.openingBalanceMinor
        }.toMutableMap()

        fun apply(walletId: String?, amount: Long, outgoing: Boolean) {
            val id = walletId ?: return
            val kind = walletKinds[id] ?: return
            val direction = when {
                outgoing && kind == WalletKind.CREDIT_CARD -> amount
                outgoing -> -amount
                kind == WalletKind.CREDIT_CARD -> -amount
                else -> amount
            }
            balances[id] = saturatingAdd(balances[id] ?: 0L, direction)
        }

        records.asSequence()
            .filter { it.id != excludingTransactionId }
            .filter { it.entryStatus == TransactionEntryStatus.POSTED && !it.isArchived && it.deletedAt == null }
            .forEach { record ->
                when (record.primaryKind) {
                    TransactionPrimaryKind.EXPENSE -> apply(record.sourceWalletId, record.amountMinor, outgoing = true)
                    TransactionPrimaryKind.INCOME -> apply(record.sourceWalletId, record.amountMinor, outgoing = false)
                    TransactionPrimaryKind.TRANSFER -> when (record.transferSubtype) {
                        TransactionTransferSubtype.INTERNAL_TRANSFER -> {
                            apply(record.sourceWalletId, record.amountMinor, outgoing = true)
                            apply(
                                record.destinationWalletId,
                                record.destinationAmountMinor ?: record.amountMinor,
                                outgoing = false,
                            )
                        }
                        TransactionTransferSubtype.FAMILY_TRANSFER -> apply(
                            record.sourceWalletId,
                            record.amountMinor,
                            outgoing = record.destinationWalletId != null,
                        )
                        TransactionTransferSubtype.DEBT -> applyDebt(record, ::apply)
                        null -> Unit
                    }
                    null -> Unit
                }
            }
        balancesByWalletId = balances
    }

    fun balance(walletId: String): Long = balancesByWalletId[walletId] ?: 0L
}

fun LedgerTransactionRecord.requireAffordable(
    wallets: List<LedgerWalletRecord>,
    records: List<LedgerTransactionRecord>,
    creditCardProfiles: List<CreditCardProfileRecord>,
    excludingTransactionId: String?,
) {
    if (entryStatus != TransactionEntryStatus.POSTED) return
    val kind = primaryKind ?: return
    if (kind == TransactionPrimaryKind.INCOME) return
    val requiresOutflow = kind == TransactionPrimaryKind.EXPENSE ||
        transferSubtype == TransactionTransferSubtype.INTERNAL_TRANSFER ||
        (transferSubtype == TransactionTransferSubtype.DEBT &&
            (debtIntent == TransactionDebtIntent.LEND || debtIntent == TransactionDebtIntent.REPAY))
    if (!requiresOutflow) {
        return
    }
    val sourceId = sourceWalletId ?: return
    val sourceWallet = wallets.firstOrNull {
        it.id == sourceId && it.ownerUserId == ownerUserId && !it.isArchived && it.deletedAt == null
    } ?: transactionBalanceFail(TransactionValidationError.INVALID_SOURCE_WALLET)
    val index = TransactionWalletBalanceIndex(wallets, records, excludingTransactionId)

    if (sourceWallet.kind == WalletKind.CREDIT_CARD) {
        val profile = creditCardProfiles.firstOrNull {
            it.ownerUserId == ownerUserId && it.walletId == sourceWallet.id && it.deletedAt == null
        } ?: transactionBalanceFail(TransactionValidationError.CREDIT_CARD_PROFILE_REQUIRED)
        val debt = maxOf(index.balance(sourceWallet.id), 0L)
        val availableCredit = maxOf(saturatingSubtract(profile.creditLimitMinor, debt), 0L)
        if (amountMinor > availableCredit) {
            transactionBalanceFail(TransactionValidationError.CREDIT_LIMIT_EXCEEDED)
        }
    } else if (amountMinor > index.balance(sourceWallet.id)) {
        transactionBalanceFail(TransactionValidationError.INSUFFICIENT_WALLET_BALANCE)
    }
}

private fun applyDebt(
    record: LedgerTransactionRecord,
    apply: (String?, Long, Boolean) -> Unit,
) {
    if (record.settlementRoleWireValue == "sharedExpenseReceivable" ||
        record.settlementRoleWireValue == "sharedExpensePayable"
    ) {
        return
    }
    if (record.debtIntent == TransactionDebtIntent.LEND &&
        record.settlementRoleWireValue == "resaleReceivable"
    ) {
        apply(record.sourceWalletId, maxOf(record.reportingExpenseMinor ?: 0L, 0L), true)
        return
    }
    when (record.debtIntent) {
        TransactionDebtIntent.LEND, TransactionDebtIntent.REPAY ->
            apply(record.sourceWalletId, record.amountMinor, true)
        TransactionDebtIntent.COLLECT, TransactionDebtIntent.BORROW ->
            apply(record.sourceWalletId, record.amountMinor, false)
        null -> Unit
    }
}

private fun saturatingAdd(left: Long, right: Long): Long = runCatching {
    Math.addExact(left, right)
}.getOrElse {
    if (right >= 0) Long.MAX_VALUE else Long.MIN_VALUE
}

private fun saturatingSubtract(left: Long, right: Long): Long = runCatching {
    Math.subtractExact(left, right)
}.getOrElse {
    if (right >= 0) Long.MIN_VALUE else Long.MAX_VALUE
}

private fun transactionBalanceFail(reason: TransactionValidationError): Nothing =
    throw TransactionValidationException(reason)
