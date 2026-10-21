package vn.com.quyln.mistia.core.model

/** Consistent personal due inputs; raw rows are never mutation defaults. */
data class UpcomingDueReadSnapshot(val owner:UserId,val rows:List<CloudRecord>) {
    fun records(entity:CloudEntity):List<CloudRecord> = rows.filter {it.entity==entity.table}
    companion object {
        val entities:Set<CloudEntity> = setOf(CloudEntity.RECURRING_BILL_PLAN,CloudEntity.INSTALLMENT_PLAN,
            CloudEntity.DUE_OCCURRENCE_RECORD,CloudEntity.LEDGER_WALLET,CloudEntity.TRANSACTION_CATEGORY)
    }
}
