package vn.com.quyln.mistia.core.model

import java.time.Instant

/** One owned generation of all four cash planner entities and their exact queues. */
data class InvestmentCashEventPublicationSnapshot(val owner:UserId,val eventId:String,val rows:List<CloudRecord>,
    val pending:List<QueuedMutation>,val dirtyKeys:Set<Pair<String,String>>) {
    val requestedRecord:CloudRecord? get()=rows.singleOrNull{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==eventId}
    val requestedQueue:QueuedMutation? get()=pending.singleOrNull{it.mutation.entity==CloudEntity.LEDGER_TRANSACTION && it.mutation.recordId==eventId}
    fun requireCoherent() {
        require(financeRawUuid(owner.value)==owner.value && financeRawUuid(eventId)==eventId)
        val keys=rows.map{it.entity to it.id};require(keys.distinct().size==keys.size)
        for(row in rows) {
            val entity=requireNotNull(CloudEntity.fromTable(row.entity));require(entity in entities && financeRawUuid(row.id)==row.id &&
                row.financeRawIdentity(owner,entity,true) && row.payload.financeRawString("id")==row.id && row.payload.financeRawString("user_id")==owner.value &&
                row.syncVersion>=0 && row.payload.financeRawLong("sync_version")==row.syncVersion && row.updatedAt==row.payload.financeRawString("updated_at") &&
                row.financeRawDeleted(true)!=null && row.deletedAt==row.payload.financeRawString("deleted_at"))
            for(key in listOf("created_at","updated_at"))Instant.parse(requireNotNull(row.payload.financeRawString(key)))
        }
        val queuedKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}
        require(queuedKeys.distinct().size==queuedKeys.size && dirtyKeys==queuedKeys.toSet())
        val byKey=rows.associateBy{it.entity to it.id}
        for(queued in pending) {
            val q=queued.mutation;val row=requireNotNull(byKey[q.entity.table to q.recordId])
            require(q.entity in entities && q.subjectUserId==owner.value && financeRawUuid(q.deviceId)==q.deviceId &&
                q.payload==row.payload && q.baseVersion==row.syncVersion && q.modifiedAt==row.updatedAt &&
                row.payload.financeRawString("last_modified_by_device_id")==q.deviceId &&
                q.kind==if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE)
            Instant.parse(q.modifiedAt)
        }
    }
    fun requireUnchanged(current:InvestmentCashEventPublicationSnapshot) {
        requireCoherent();current.requireCoherent()
        val rowOrder=compareBy(CloudRecord::entity,CloudRecord::id)
        val queueOrder=compareBy<QueuedMutation>{it.mutation.entity.table}.thenBy{it.mutation.recordId}
        require(owner==current.owner && eventId==current.eventId && rows.sortedWith(rowOrder)==current.rows.sortedWith(rowOrder) &&
            pending.sortedWith(queueOrder)==current.pending.sortedWith(queueOrder) && dirtyKeys==current.dirtyKeys)
    }
    fun matches(queued:QueuedMutation):Boolean=runCatching {
        requireCoherent()
        queued==requestedQueue && queued.mutation.entity==CloudEntity.LEDGER_TRANSACTION && queued.mutation.recordId==eventId &&
            requestedRecord?.payload?.financeRawString("settlement_role_raw_value") in setOf("investmentCashDeposit","investmentCashWithdrawal")
    }.getOrDefault(false)
    companion object {val entities=InvestmentCashReadSnapshot.entities}
}
