package vn.com.quyln.mistia.feature.overview

import java.time.Instant
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

/** Read-only financial effects, validated only for the fields consumed by each reporting direction. */
internal fun overviewRawReportingEffects(owner:UserId,records:List<CloudRecord>,wallets:List<CloudRecord>,
    knownTitles:Map<GeneratedTransactionTitle,Collection<String>>,includeDated:(Instant)->Boolean):List<OverviewReportingEffect> {
    val metadata=wallets.filter {it.overviewRawIdentity(owner,CloudEntity.LEDGER_WALLET) && it.overviewRawDeleted()!=true}
        .associateBy {overviewRawUuid(it.id)}
    val effects=records.mapNotNull {raw ->
        if(!raw.overviewRawIdentity(owner,CloudEntity.LEDGER_TRANSACTION)) return@mapNotNull null
        val payload=raw.payload
        val deleted=raw.overviewRawDeleted();val archived=payload.overviewRawArchived()
        val status=payload.overviewRawString("entry_status_raw_value")?.let(TransactionEntryStatus::fromWireValue)
        if(deleted==true || archived==true || status==TransactionEntryStatus.DRAFT) return@mapNotNull null
        val occurred=payload.overviewRawString("occurred_at")?.let {runCatching {Instant.parse(it)}.getOrNull()}
        if(occurred!=null && runCatching {includeDated(occurred)}.getOrNull()==false) return@mapNotNull null
        val source=payload.overviewRawReference("source_wallet_id")
        val wallet=metadata[source.id]
        val sourceCode=when {
            payload.present("source_currency_code") -> payload.overviewRawString("source_currency_code")?.overviewReportingCode()
            !source.readable -> null
            wallet==null -> "JPY"
            wallet.overviewRawDeleted()==null -> null
            else -> wallet.payload.overviewRawString("currency_code")?.overviewReportingCode()
        }
        val kind=wallet?.payload?.overviewRawString("kind_raw_value")?.let(WalletKind::fromWireValue)
        val kindKnown=source.readable && (wallet==null || (wallet.overviewRawDeleted()==false && kind!=null))
        val amounts=reportingAmounts(raw,kind,kindKnown,knownTitles)
        val eligibilityKnown=deleted==false && archived==false && status==TransactionEntryStatus.POSTED
        fun eligible(amount:Long?):Long?=if(eligibilityKnown || amount==0L) amount else null
        OverviewReportingEffect(occurred,sourceCode,eligible(amounts.first),eligible(amounts.second))
    }
    return effects
}

internal fun String.overviewReportingCode()=financeReportingCode()
internal fun JsonObject.present(key:String)=financePresent(key)

/** Compare the existing classifier's effects over unreadable classification dependencies, never wire defaults. */
private fun reportingAmounts(raw:CloudRecord,walletKind:WalletKind?,kindKnown:Boolean,titles:Map<GeneratedTransactionTitle,Collection<String>>):Pair<Long?,Long?> {
    val payload=raw.payload
    val original=payload.overviewRawLong("amount_minor")
    val expensePresent=payload.present("reporting_expense_minor");val incomePresent=payload.present("reporting_income_minor")
    val expense=payload.overviewRawLong("reporting_expense_minor");val income=payload.overviewRawLong("reporting_income_minor")
    val zeroExpense=if(expensePresent) expense==0L else original==0L
    val zeroIncome=if(incomePresent) income==0L else original==0L
    if(zeroExpense && zeroIncome) return 0L to 0L
    val primary=payload.overviewRawString("primary_kind_raw_value")?.let(TransactionPrimaryKind::fromWireValue)
        ?: return (if(zeroIncome) 0L else null) to (if(zeroExpense) 0L else null)
    fun value(source:OverviewReportingSource):Long?=when(source) {
        OverviewReportingSource.NONE -> 0L
        OverviewReportingSource.ORIGINAL -> original
        OverviewReportingSource.EXPENSE_OVERRIDE -> expense
        OverviewReportingSource.INCOME_OVERRIDE -> income
    }
    // Overrides and a non-income primary with no income override have no classifier ambiguity.
    val expenseResult=ReportingConsensus(if(expensePresent) expense else null,expensePresent)
    val incomeFixed=primary!=TransactionPrimaryKind.INCOME && !incomePresent
    val incomeResult=ReportingConsensus(0L,incomeFixed)
    val unknownSubtype=payload.present("transfer_subtype_raw_value") && payload.overviewRawString("transfer_subtype_raw_value")?.let(TransactionTransferSubtype::fromWireValue)==null
    if(primary==TransactionPrimaryKind.TRANSFER && unknownSubtype && !expensePresent && original!=0L) expenseResult.unknown()
    for((candidate,kindValue) in overviewClassificationCandidates(raw,primary,walletKind,kindKnown,titles,expensePresent,incomePresent)) {
        if(expenseResult.settled && incomeResult.settled) break
        expenseResult.add(value(overviewExpenseSource(candidate,kindValue,titles)))
        incomeResult.add(value(overviewIncomeSource(candidate,titles)))
    }
    return incomeResult.value to expenseResult.value
}

/** Existing Overview contract delegates to the shared classifier equivalence classes. */
internal fun overviewClassificationCandidates(raw:CloudRecord,primary:TransactionPrimaryKind,walletKind:WalletKind?,kindKnown:Boolean,
    titles:Map<GeneratedTransactionTitle,Collection<String>>,expensePresent:Boolean=false,incomePresent:Boolean=false):Sequence<Pair<LedgerTransactionRecord,WalletKind?>> =
    financeClassificationCandidates(raw,primary,walletKind,kindKnown,titles,expensePresent,incomePresent)

private class ReportingConsensus(initial:Long?,private val fixed:Boolean) {
    private var seen=fixed
    var value:Long?=initial;private set
    val settled:Boolean get()=fixed || (seen && value==null)
    fun unknown(){seen=true;value=null}
    fun add(next:Long?) {if(settled) return;if(!seen) {seen=true;value=next} else if(value!=next) value=null}
}
