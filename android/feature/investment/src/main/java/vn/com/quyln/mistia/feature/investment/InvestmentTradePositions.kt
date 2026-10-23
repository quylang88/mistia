package vn.com.quyln.mistia.feature.investment

import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.json.JsonNull
import vn.com.quyln.mistia.core.model.*

/** Read-only display projection; the repository revalidates the full source at commit. */
internal fun investmentTradePositions(rows:List<CloudRecord>,asset:InvestmentAssetRecord):List<InvestmentUnitPosition> {
    val inputs=rows.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table}.filter{row->
        val reference=row.payload.financeRawReference("asset_id")
        require(reference.readable && reference.id!=null)
        if(reference.id!=asset.id)false else !requireNotNull(row.financeRawDeleted(true))}.map{row->
        val p=row.payload
        require(p["unit_label"]==null || p["unit_label"]==JsonNull || p.financeRawString("unit_label")!=null)
        InvestmentTradeInput(UUID.fromString(row.id),when(p.financeRawString("kind_raw_value")){"buy"->InvestmentTradeKind.BUY;"sell"->InvestmentTradeKind.SELL;else->error("Unreadable trade")},
            BigDecimal(requireNotNull(p.financeRawString("quantity_decimal_string"))),p.financeRawString("unit_label") ?: asset.defaultUnitLabel,
            requireNotNull(p.financeRawLong("accounting_gross_amount_minor")),Instant.parse(p.financeRawString("occurred_at")),Instant.parse(p.financeRawString("created_at")))
    }
    return InvestmentAccountingEngine.projection(inputs).unitPositions
}
