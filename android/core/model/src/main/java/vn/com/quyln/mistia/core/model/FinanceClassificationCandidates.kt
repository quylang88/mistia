package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*

/** Ephemeral classifier equivalence classes; callers must never use these placeholder amounts as money. */
fun financeClassificationCandidates(raw:CloudRecord,primary:TransactionPrimaryKind,walletKind:WalletKind?,kindKnown:Boolean,
    titles:Map<GeneratedTransactionTitle,Collection<String>>,expensePresent:Boolean=false,incomePresent:Boolean=false):Sequence<Pair<LedgerTransactionRecord,WalletKind?>> = sequence {
    val payload=raw.payload
    val subtypes=payload.financeEnumChoices("transfer_subtype_raw_value",TransactionTransferSubtype::fromWireValue,listOf(TransactionTransferSubtype.INTERNAL_TRANSFER,TransactionTransferSubtype.FAMILY_TRANSFER,TransactionTransferSubtype.DEBT))
    val intents=payload.financeEnumChoices("debt_intent_raw_value",TransactionDebtIntent::fromWireValue,TransactionDebtIntent.entries)
    val source=payload.financeRawReference("source_wallet_id")
    val category=payload.financeRawReference("category_id")
    val sourceIds=if(source.readable) listOf(source.id) else listOf(null,REPORTING_OTHER_ID)
    val categoryIds=if(category.readable) listOf(category.id) else listOf(null,REPORTING_OTHER_ID,TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID,
        TransactionCategoryRecord.BALANCE_ADJUSTMENT_INCOME_ID,SystemCategoryIdentity.canonicalId("loan_repayment"),SystemCategoryIdentity.canonicalId("people_repayment"))
    val titleChoices=if(!payload.financePresent("title")) listOf("") else payload.financeRawString("title")?.let(::listOf)
        ?: (listOf("","Card payment")+listOf(GeneratedTransactionTitle.BALANCE_ADJUSTMENT,GeneratedTransactionTitle.COLLECT,GeneratedTransactionTitle.BORROW).flatMap {titles[it].orEmpty()}).distinct()
    val knownRoles=setOf("sharedExpenseReceivable","sharedExpensePayable","sharedExpensePaid","sharedExpenseReceipt","sharedExpensePayment","resaleReceivable","resaleReceipt")
    val role=payload.financeRawString("settlement_role_raw_value")
    val roles=when {
        !payload.financePresent("settlement_role_raw_value") -> listOf(null)
        role in knownRoles || role?.startsWith("investment")==true -> listOf(role)
        else -> listOf(null,"resaleReceipt")
    }
    val kinds=if(kindKnown) listOf(walletKind) else listOf(null,WalletKind.CREDIT_CARD)
    // These are ephemeral classifier inputs, not financial records. Only presence selects the override field.
    val base=LedgerTransactionRecord.fromCloudRecord(raw.copy(payload=buildJsonObject {
        put("id",financeRawUuid(raw.id)!!);put("user_id",raw.ownerUserId);put("primary_kind_raw_value",primary.wireValue);put("entry_status_raw_value","posted");put("amount_minor",0)
        if(expensePresent) put("reporting_expense_minor",0)
        if(incomePresent) put("reporting_income_minor",0)
    },deletedAt=null))
    for(subtype in subtypes) for(intent in intents) for(roleValue in roles) for(title in titleChoices) for(categoryId in categoryIds) for(sourceId in sourceIds) for(kindValue in kinds) {
        yield(base.copy(transferSubtypeWireValue=subtype?.wireValue,debtIntentWireValue=intent?.wireValue,settlementRoleWireValue=roleValue,title=title,categoryId=categoryId,sourceWalletId=sourceId) to kindValue)
    }
}

private const val REPORTING_OTHER_ID="00000000-0000-0000-0000-000000000001"
private fun <T> JsonObject.financeEnumChoices(key:String,parse:(String?)->T?,all:List<T>):List<T?> {
    if(!financePresent(key)) return listOf(null)
    return financeRawString(key)?.let(parse)?.let {listOf(it)} ?: (listOf(null)+all)
}
