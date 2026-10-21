package vn.com.quyln.mistia.core.model

/** Consistent raw inputs for personal Overview reports, never mutation defaults. */
data class OverviewFinancialReadSnapshot(val owner:UserId,val rows:List<CloudRecord>) {
    fun records(entity:CloudEntity):List<CloudRecord> = rows.filter {it.entity==entity.table}
    companion object {
        val entities:Set<CloudEntity> = setOf(CloudEntity.LEDGER_WALLET,CloudEntity.LEDGER_TRANSACTION,
            CloudEntity.TRANSACTION_CATEGORY,CloudEntity.INVESTMENT_CHANNEL,CloudEntity.INVESTMENT_ASSET,CloudEntity.INVESTMENT_TRADE)
    }
}
