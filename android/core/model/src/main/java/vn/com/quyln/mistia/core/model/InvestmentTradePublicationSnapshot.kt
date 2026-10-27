package vn.com.quyln.mistia.core.model

import java.time.Instant

/** One local generation of all financial inputs used by the existing trade planner. */
data class InvestmentTradePublicationSnapshot(
    val owner:UserId,val tradeId:String,val rows:List<CloudRecord>,val pending:List<QueuedMutation>,val dirtyKeys:Set<Pair<String,String>>,
) {
    val requestedRecord:CloudRecord? get()=rows.singleOrNull{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==tradeId}
    val requestedQueue:QueuedMutation? get()=pending.singleOrNull{it.mutation.entity==CloudEntity.INVESTMENT_TRADE && it.mutation.recordId==tradeId}
    fun requireCoherent() {
        require(financeRawUuid(owner.value)==owner.value && financeRawUuid(tradeId)==tradeId)
        val keys=rows.map{it.entity to it.id}
        require(keys.distinct().size==keys.size)
        val byKey=rows.associateBy{it.entity to it.id}
        require(rows.all{row->CloudEntity.fromTable(row.entity) in entities && financeRawUuid(row.id)==row.id &&
            row.financeRawIdentity(owner,requireNotNull(CloudEntity.fromTable(row.entity)),true)})
        val queuedKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}
        require(queuedKeys.distinct().size==queuedKeys.size && dirtyKeys==queuedKeys.toSet())
        for(queued in pending) {
            val q=queued.mutation;val row=requireNotNull(byKey[q.entity.table to q.recordId])
            require(q.entity in entities && q.subjectUserId==owner.value && financeRawUuid(q.deviceId)==q.deviceId)
            require(row.payload==q.payload && row.syncVersion==q.baseVersion && row.syncVersion>=0 &&
                row.payload.financeRawLong("sync_version")==row.syncVersion && row.updatedAt==q.modifiedAt &&
                row.payload.financeRawString("updated_at")==q.modifiedAt && row.payload.financeRawString("last_modified_by_device_id")==q.deviceId)
            Instant.parse(q.modifiedAt)
            require(row.financeRawDeleted(true)!=null && row.deletedAt==row.payload.financeRawString("deleted_at"))
            require(q.kind==if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE)
        }
    }
    fun matches(queued:QueuedMutation):Boolean=runCatching {
        requireCoherent()
        queued==requestedQueue && queued.mutation.entity==CloudEntity.INVESTMENT_TRADE && queued.mutation.recordId==tradeId
    }.getOrDefault(false)
    fun requireUnchanged(current:InvestmentTradePublicationSnapshot) {
        requireCoherent();current.requireCoherent()
        val rowOrder=compareBy(CloudRecord::entity,CloudRecord::id)
        val queueOrder=compareBy<QueuedMutation>{it.mutation.entity.table}.thenBy{it.mutation.recordId}
        require(owner==current.owner && tradeId==current.tradeId && rows.sortedWith(rowOrder)==current.rows.sortedWith(rowOrder) &&
            pending.sortedWith(queueOrder)==current.pending.sortedWith(queueOrder) && dirtyKeys==current.dirtyKeys)
    }
    companion object {val entities=InvestmentPurchaseSnapshot.entities}
}
