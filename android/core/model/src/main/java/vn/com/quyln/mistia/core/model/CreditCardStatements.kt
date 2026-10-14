package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.text.Collator
import java.util.Locale

enum class CreditCardStatementState(val wireValue:String) {UNCLOSED("unclosed"),PAYABLE("payable"),PAID("paid"),OVERDUE("overdue")}
data class CreditCardStatement(val account:CreditCardAccount,val month:YearMonth,val closingDate:Instant,val dueDate:Instant,
    val amountMinor:Long,val availableCreditMinor:Long,val status:DueStatus,val linkedTransactionId:String?,val state:CreditCardStatementState) {
    val id:String get()="${account.wallet.id.lowercase()}-$month"
    val isPayable:Boolean get()=state==CreditCardStatementState.PAYABLE || state==CreditCardStatementState.OVERDUE
}
enum class CreditCardAutoPaymentKind(val wireValue:String) {NOT_DUE("notDue"),ALREADY_PAID("alreadyPaid"),MISSING_LINKED_WALLET("missingLinkedWallet"),INSUFFICIENT_FUNDS("insufficientFunds"),PAYABLE("payable")}
data class CreditCardAutoPaymentDecision(val kind:CreditCardAutoPaymentKind,val availableMinor:Long?=null,val requiredMinor:Long?=null)
fun creditCardStatementClosingDate(month:YearMonth,closingDay:Int,zone:ZoneId):Instant {
    val next=month.plusMonths(1)
    return next.atDay(closingDay.coerceIn(1,next.lengthOfMonth())).atStartOfDay(zone).toInstant()
}
fun creditCardStatementDueDate(month:YearMonth,closingDay:Int,dueDay:Int,zone:ZoneId):Instant {
    val closing=creditCardStatementClosingDate(month,closingDay,zone)
    val closingMonth=YearMonth.from(closing.atZone(zone))
    fun scheduled(value:YearMonth)=value.atDay(dueDay.coerceIn(1,value.lengthOfMonth())).atStartOfDay(zone).toInstant()
    val candidate=scheduled(closingMonth)
    return if(candidate>=closing) candidate else scheduled(closingMonth.plusMonths(1))
}
fun creditCardStatementItems(owner:UserId,accounts:List<CreditCardAccount>,transactions:List<LedgerTransactionRecord>,occurrences:List<DueOccurrenceRecord>,
    months:List<YearMonth>,reference:Instant,zone:ZoneId,categories:List<TransactionCategoryRecord> = emptyList(),locale:Locale=Locale.getDefault()):List<CreditCardStatement> {
    val owned=accounts.filter {it.wallet.ownerUserId==owner.value && it.profile.ownerUserId==owner.value && it.wallet.deletedAt==null &&
        it.profile.deletedAt==null && it.wallet.kind==WalletKind.CREDIT_CARD && it.profile.walletId==it.wallet.id}.distinctBy {it.wallet.id}
    val ids=owned.map {it.wallet.id}.toSet()
    val records=transactions.filter {it.ownerUserId==owner.value && it.entryStatus==TransactionEntryStatus.POSTED && !it.isArchived && it.deletedAt==null}
    val excluded=categories.filter {it.ownerUserId==owner.value && (it.isBalanceAdjustmentSystemCategory || it.systemKey=="loan_repayment")}.map {it.id}.toSet()+
        setOf(TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID,TransactionCategoryRecord.BALANCE_ADJUSTMENT_INCOME_ID,"d872b8af-d28a-5b90-8822-839dfa097b23")
    val adjustmentTitles=setOf("điều chỉnh số dư","balance adjustment","残高調整")
    val amounts=mutableMapOf<Pair<String,YearMonth>,Long>()
    for(record in records) {
        val wallet=record.sourceWalletId?.takeIf {it in ids} ?: continue
        val charge=when(record.primaryKind) {
            TransactionPrimaryKind.EXPENSE -> record.categoryId !in excluded && record.title.trim().lowercase(Locale.ROOT) !in adjustmentTitles
            TransactionPrimaryKind.TRANSFER -> record.transferSubtype==TransactionTransferSubtype.DEBT && record.debtIntent==TransactionDebtIntent.LEND
            else -> false
        }
        if(charge) {
            val key=wallet to YearMonth.from(Instant.parse(record.occurredAt).atZone(zone))
            amounts[key]=Math.addExact(amounts[key] ?: 0L,record.amountMinor)
        }
    }
    val payments=records.filter {it.primaryKind==TransactionPrimaryKind.TRANSFER && it.transferSubtype==TransactionTransferSubtype.INTERNAL_TRANSFER && it.destinationWalletId in ids}
        .groupBy {it.destinationWalletId}.mapValues {(_,rows) -> rows.sortedWith(compareBy({Instant.parse(it.occurredAt)},{Instant.parse(it.createdAt)}))}
    val occurrenceIndex=linkedMapOf<Pair<String,String>,DueOccurrenceRecord>()
    occurrences.filter {it.ownerUserId==owner.value && it.deletedAt==null && it.sourceKind==DueSourceKind.CREDIT_CARD}.forEach {
        occurrenceIndex.putIfAbsent(it.sourceId to it.selectedMonthKey,it)
    }
    val balances=TransactionWalletBalanceIndex(owned.map {it.wallet},records)
    val today=reference.atZone(zone).toLocalDate()
    val result=owned.flatMap {account -> months.distinct().sorted().mapNotNull {month ->
        val closing=creditCardStatementClosingDate(month,account.profile.statementClosingDay,zone)
        val due=creditCardStatementDueDate(month,account.profile.statementClosingDay,account.profile.paymentDueDay,zone)
        val amount=amounts[account.wallet.id to month] ?: 0L
        val occurrence=(occurrenceIndex[account.wallet.id to month.toString()] ?: occurrenceIndex[account.wallet.id to YearMonth.from(due.atZone(zone)).toString()])
            ?.takeIf {amount>0 && it.amountMinorSnapshot==amount}
        val monthEnd=month.plusMonths(1).atDay(1).atStartOfDay(zone).toInstant().minusSeconds(1)
        if(Instant.parse(account.wallet.createdAt).epochSecond>monthEnd.epochSecond && occurrence==null && amount<=0) return@mapNotNull null
        val candidates=payments[account.wallet.id].orEmpty()
        fun covers(record:LedgerTransactionRecord)=amount>0 && Instant.parse(record.occurredAt)>=closing && (record.destinationAmountMinor ?: record.amountMinor)>=amount
        val linked=candidates.firstOrNull {it.id==occurrence?.linkedTransactionId && covers(it)} ?: candidates.firstOrNull(::covers)
        val status=if(linked==null) DueStatus.PENDING else DueStatus.PAID
        val state=when {
            status==DueStatus.PAID -> CreditCardStatementState.PAID
            today<closing.atZone(zone).toLocalDate() -> CreditCardStatementState.UNCLOSED
            amount<=0 -> CreditCardStatementState.PAID
            due.atZone(zone).toLocalDate()<today -> CreditCardStatementState.OVERDUE
            else -> CreditCardStatementState.PAYABLE
        }
        CreditCardStatement(account,month,closing,due,amount,maxOf(maxOf(account.profile.creditLimitMinor,0L)-maxOf(balances.balance(account.wallet.id),0L),0L),status,linked?.id,state)
    }}
    val collator=Collator.getInstance(locale).apply {strength=Collator.SECONDARY}
    return result.sortedWith {left,right -> val dates=left.dueDate.compareTo(right.dueDate);if(dates!=0) dates else collator.compare(left.account.wallet.name,right.account.wallet.name)}
}
fun creditCardAutoPaymentDecision(statement:CreditCardStatement,sourceBalanceMinor:Long?,reference:Instant,zone:ZoneId):CreditCardAutoPaymentDecision {
    if(statement.status!=DueStatus.PENDING || statement.state==CreditCardStatementState.PAID || statement.amountMinor<=0)
        return CreditCardAutoPaymentDecision(CreditCardAutoPaymentKind.ALREADY_PAID)
    val today=reference.atZone(zone).toLocalDate();val due=statement.dueDate.atZone(zone).toLocalDate()
    if(today<due || today>due.plusDays(5)) return CreditCardAutoPaymentDecision(CreditCardAutoPaymentKind.NOT_DUE)
    if(statement.account.profile.paymentSourceWalletId==null || sourceBalanceMinor==null)
        return CreditCardAutoPaymentDecision(CreditCardAutoPaymentKind.MISSING_LINKED_WALLET)
    if(sourceBalanceMinor<statement.amountMinor) return CreditCardAutoPaymentDecision(CreditCardAutoPaymentKind.INSUFFICIENT_FUNDS,sourceBalanceMinor,statement.amountMinor)
    return CreditCardAutoPaymentDecision(CreditCardAutoPaymentKind.PAYABLE)
}

fun creditCardStatementsDue(owner:UserId,selectedMonth:YearMonth,accounts:List<CreditCardAccount>,transactions:List<LedgerTransactionRecord>,
    occurrences:List<DueOccurrenceRecord>,reference:Instant,zone:ZoneId,categories:List<TransactionCategoryRecord> = emptyList()):List<CreditCardStatement> =
    creditCardStatementItems(owner,accounts,transactions,occurrences,(-2L..0L).map {selectedMonth.plusMonths(it)},reference,zone,categories)
        .filter {YearMonth.from(it.dueDate.atZone(zone))==selectedMonth}
