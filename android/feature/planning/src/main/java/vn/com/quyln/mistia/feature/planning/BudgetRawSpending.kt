package vn.com.quyln.mistia.feature.planning

import java.time.*
import vn.com.quyln.mistia.core.model.*

internal fun projectRawBudgetReadSnapshot(owner:UserId,snapshot:BudgetReadSnapshot?,month:YearMonth,reference:Instant,zone:ZoneId,
    rates:List<ExchangeRateSnapshot>,language:CategoryNameLanguage,adjustmentTitles:Set<String>,currency:String,deletedCategoryName:String="",
):BudgetProjection=vn.com.quyln.mistia.core.model.projectRawBudgetReadSnapshot(owner,snapshot,month,reference,zone,rates,language,adjustmentTitles,currency,deletedCategoryName)
