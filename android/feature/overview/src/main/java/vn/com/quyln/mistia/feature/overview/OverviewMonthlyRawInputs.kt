package vn.com.quyln.mistia.feature.overview

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.util.Locale
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

/** Monthly-only admission: retain unknown required effects instead of omitting raw financial rows. */
internal fun overviewRawMonthlyCashflow(owner:UserId,records:List<CloudRecord>,wallets:List<CloudRecord>,currency:String,
    rates:List<ExchangeRateSnapshot> = emptyList(),knownTitles:Map<GeneratedTransactionTitle,Collection<String>> = emptyMap(),reference:Instant,zone:ZoneId):List<OverviewMonthlyCashflow> {
    val metadata=wallets.filter {it.overviewRawIdentity(owner,CloudEntity.LEDGER_WALLET) && it.overviewRawDeleted()!=true}
        .associateBy {overviewRawUuid(it.id)}
    val current=YearMonth.from(reference.atZone(zone))
    val effects=records.mapNotNull {raw ->
        if(!raw.overviewRawIdentity(owner,CloudEntity.LEDGER_TRANSACTION)) return@mapNotNull null
        val payload=raw.payload
        val deleted=raw.overviewRawDeleted();val archived=payload.overviewRawArchived()
        val status=payload.overviewRawString("entry_status_raw_value")?.let(TransactionEntryStatus::fromWireValue)
        if(deleted==true || archived==true || status==TransactionEntryStatus.DRAFT) return@mapNotNull null
        val occurred=payload.overviewRawString("occurred_at")?.let {runCatching {Instant.parse(it)}.getOrNull()}
        val month=occurred?.let {runCatching {YearMonth.from(it.atZone(zone))}.getOrNull()}
        if(month!=null && month>current) return@mapNotNull null
        val source=payload.overviewRawReference("source_wallet_id")
        val wallet=metadata[source.id]
        val sourceCode=when {
            payload.present("source_currency_code") -> payload.overviewRawString("source_currency_code")?.monthlyCode()
            !source.readable -> null
            wallet==null -> "JPY"
            wallet.overviewRawDeleted()==null -> null
            else -> wallet.payload.overviewRawString("currency_code")?.monthlyCode()
        }
        val kind=wallet?.payload?.overviewRawString("kind_raw_value")?.let(WalletKind::fromWireValue)
        val kindKnown=source.readable && (wallet==null || (wallet.overviewRawDeleted()==false && kind!=null))
        val amounts=monthlyAmounts(raw,kind,kindKnown,knownTitles)
        val eligibilityKnown=deleted==false && archived==false && status==TransactionEntryStatus.POSTED
        fun eligible(amount:Long?):Long?=if(eligibilityKnown || amount==0L) amount else null
        OverviewMonthlyEffect(occurred,sourceCode,eligible(amounts.first),eligible(amounts.second))
    }
    return overviewMonthlyCashflowEffects(effects,currency,rates,reference,zone)
}

private fun String.monthlyCode()=trim().uppercase(Locale.ROOT).takeIf {it.matches(Regex("[A-Z]{3}"))}
private fun JsonObject.present(key:String)=get(key).let {it!=null && it!=JsonNull}

/** Compare the existing classifier's effects over unreadable classification dependencies, never wire defaults. */
private fun monthlyAmounts(raw:CloudRecord,walletKind:WalletKind?,kindKnown:Boolean,titles:Map<GeneratedTransactionTitle,Collection<String>>):Pair<Long?,Long?> {
    val payload=raw.payload
    val original=payload.overviewRawLong("amount_minor")
    val expensePresent=payload.present("reporting_expense_minor");val incomePresent=payload.present("reporting_income_minor")
    val expense=payload.overviewRawLong("reporting_expense_minor");val income=payload.overviewRawLong("reporting_income_minor")
    if((if(expensePresent) expense==0L else original==0L) && (if(incomePresent) income==0L else original==0L)) return 0L to 0L
    val primary=payload.overviewRawString("primary_kind_raw_value")?.let(TransactionPrimaryKind::fromWireValue) ?: return null to null
    fun value(source:OverviewReportingSource):Long?=when(source) {
        OverviewReportingSource.NONE -> 0L
        OverviewReportingSource.ORIGINAL -> original
        OverviewReportingSource.EXPENSE_OVERRIDE -> expense
        OverviewReportingSource.INCOME_OVERRIDE -> income
    }
    // Overrides and a non-income primary with no income override have no classifier ambiguity.
    val expenseResult=MonthlyConsensus(if(expensePresent) expense else null,expensePresent)
    val incomeFixed=primary!=TransactionPrimaryKind.INCOME && !incomePresent
    val incomeResult=MonthlyConsensus(0L,incomeFixed)
    val subtypes=payload.enumChoices("transfer_subtype_raw_value",TransactionTransferSubtype::fromWireValue,listOf(TransactionTransferSubtype.INTERNAL_TRANSFER,TransactionTransferSubtype.FAMILY_TRANSFER,TransactionTransferSubtype.DEBT))
    val intents=payload.enumChoices("debt_intent_raw_value",TransactionDebtIntent::fromWireValue,TransactionDebtIntent.entries)
    val unknownSubtype=payload.present("transfer_subtype_raw_value") && payload.overviewRawString("transfer_subtype_raw_value")?.let(TransactionTransferSubtype::fromWireValue)==null
    if(primary==TransactionPrimaryKind.TRANSFER && unknownSubtype && !expensePresent && original!=0L) expenseResult.unknown()
    val source=payload.overviewRawReference("source_wallet_id")
    val category=payload.overviewRawReference("category_id")
    val sourceIds=if(source.readable) listOf(source.id) else listOf(null,MONTHLY_OTHER_ID)
    val categoryIds=if(category.readable) listOf(category.id) else listOf(null,MONTHLY_OTHER_ID,TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID,
        TransactionCategoryRecord.BALANCE_ADJUSTMENT_INCOME_ID,SystemCategoryIdentity.canonicalId("loan_repayment"),SystemCategoryIdentity.canonicalId("people_repayment"))
    val titleChoices=if(!payload.present("title")) listOf("") else payload.overviewRawString("title")?.let(::listOf)
        ?: (listOf("","Card payment")+listOf(GeneratedTransactionTitle.BALANCE_ADJUSTMENT,GeneratedTransactionTitle.COLLECT,GeneratedTransactionTitle.BORROW).flatMap {titles[it].orEmpty()}).distinct()
    val knownRoles=setOf("sharedExpenseReceivable","sharedExpensePayable","sharedExpensePaid","sharedExpenseReceipt","sharedExpensePayment","resaleReceivable","resaleReceipt")
    val role=payload.overviewRawString("settlement_role_raw_value")
    val roles=when {
        !payload.present("settlement_role_raw_value") -> listOf(null)
        role in knownRoles || role?.startsWith("investment")==true -> listOf(role)
        else -> listOf(null,"resaleReceipt")
    }
    val kinds=if(kindKnown) listOf(walletKind) else listOf(null,WalletKind.CREDIT_CARD)
    // These are ephemeral classifier inputs, not financial records. Only presence selects the override field.
    val base=LedgerTransactionRecord.fromCloudRecord(raw.copy(payload=buildJsonObject {
        put("id",overviewRawUuid(raw.id)!!);put("user_id",raw.ownerUserId);put("primary_kind_raw_value",primary.wireValue);put("entry_status_raw_value","posted");put("amount_minor",0)
        if(expensePresent) put("reporting_expense_minor",0)
        if(incomePresent) put("reporting_income_minor",0)
    },deletedAt=null))
    // All domains are finite classifier equivalence classes. Normal readable records take exactly one path.
    loop@ for(subtype in subtypes) for(intent in intents) for(roleValue in roles) for(title in titleChoices) for(categoryId in categoryIds) for(sourceId in sourceIds) for(kindValue in kinds) {
        if(expenseResult.settled && incomeResult.settled) break@loop
        val candidate=base.copy(transferSubtypeWireValue=subtype?.wireValue,debtIntentWireValue=intent?.wireValue,settlementRoleWireValue=roleValue,title=title,categoryId=categoryId,sourceWalletId=sourceId)
        expenseResult.add(value(overviewExpenseSource(candidate,kindValue,titles)))
        incomeResult.add(value(overviewIncomeSource(candidate,titles)))
    }
    return incomeResult.value to expenseResult.value
}

private const val MONTHLY_OTHER_ID="00000000-0000-0000-0000-000000000001"
private class MonthlyConsensus(initial:Long?,private val fixed:Boolean) {
    private var seen=fixed
    var value:Long?=initial;private set
    val settled:Boolean get()=fixed || (seen && value==null)
    fun unknown(){seen=true;value=null}
    fun add(next:Long?) {if(settled) return;if(!seen) {seen=true;value=next} else if(value!=next) value=null}
}
private fun <T> JsonObject.enumChoices(key:String,parse:(String?)->T?,all:List<T>):List<T?> {
    if(!present(key)) return listOf(null)
    return overviewRawString(key)?.let(parse)?.let {listOf(it)} ?: (listOf(null)+all)
}
