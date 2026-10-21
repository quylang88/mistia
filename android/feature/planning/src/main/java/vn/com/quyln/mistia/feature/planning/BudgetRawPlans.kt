package vn.com.quyln.mistia.feature.planning

import java.time.*
import vn.com.quyln.mistia.core.model.*

internal fun projectRawBudgetPlans(owner:UserId,rawPlans:List<CloudRecord>?,categories:List<TransactionCategoryRecord>,
    transactions:List<LedgerTransactionRecord>,wallets:List<LedgerWalletRecord>,month:YearMonth,reference:Instant,zone:ZoneId,
    rates:List<ExchangeRateSnapshot>,language:CategoryNameLanguage,adjustmentTitles:Set<String>,currency:String,deletedCategoryName:String="",
    expenseEffects:List<BudgetExpenseEffect>?=null,
):BudgetProjection=vn.com.quyln.mistia.core.model.projectRawBudgetPlans(owner,rawPlans,categories,transactions,wallets,month,reference,zone,rates,language,adjustmentTitles,currency,deletedCategoryName,expenseEffects)

internal fun storedBudgetReadPlan(owner:UserId,id:String,rows:List<CloudRecord>?):BudgetPlanRecord?=
    vn.com.quyln.mistia.core.model.storedBudgetReadPlan(owner,id,rows)
