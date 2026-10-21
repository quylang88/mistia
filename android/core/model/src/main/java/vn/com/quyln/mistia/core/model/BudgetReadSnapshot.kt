package vn.com.quyln.mistia.core.model

/** Owner-partitioned read inputs, including historical tombstones; never a mutation payload. */
data class BudgetReadSnapshot(val owner:UserId,val rows:List<CloudRecord>) {
    fun records(entity:CloudEntity):List<CloudRecord> = rows.filter {it.entity==entity.table}
    companion object {
        val entities:Set<CloudEntity> = setOf(CloudEntity.BUDGET_PLAN,CloudEntity.LEDGER_TRANSACTION,CloudEntity.LEDGER_WALLET,CloudEntity.TRANSACTION_CATEGORY)
    }
}
