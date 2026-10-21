package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.JsonObject

/** Investment ledger legs and cash events belong to their dedicated atomic pipeline. */
fun requiresInvestmentLedgerDomain(payload:JsonObject?):Boolean =
    payload?.financeRawString("settlement_role_raw_value")?.startsWith("investment")==true
