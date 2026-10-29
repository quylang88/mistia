package vn.com.quyln.mistia.core.model

/** Whole owned generation; queue membership includes blocked/backoff mutations. */
data class CardPaymentPublicationSnapshot(val owner:UserId,val cardId:String,
    val recordsByEntity:Map<CloudEntity,List<CloudRecord>>,val queues:List<QueuedMutation>,val dirtyKeys:Set<Pair<String,String>>) {
    companion object { val entities=setOf(CloudEntity.LEDGER_WALLET,CloudEntity.CREDIT_CARD_PROFILE,CloudEntity.LEDGER_TRANSACTION,
        CloudEntity.TRANSACTION_CATEGORY,CloudEntity.DUE_OCCURRENCE_RECORD,CloudEntity.INVESTMENT_POSTING) }
    fun requireCoherent() {
        require(financeRawUuid(owner.value)==owner.value && financeRawUuid(cardId)==cardId && recordsByEntity.keys==entities)
        val rows=recordsByEntity.values.flatten()
        val byKey=rows.associateBy{it.entity to it.id}
        require(byKey.size==rows.size)
        for((entity,records) in recordsByEntity)for(row in records) {
            cardPublicationIdentity(row,owner,entity,row.id)
        }
        val keys=queues.map{it.mutation.entity.table to it.mutation.recordId}
        require(keys.distinct().size==keys.size && dirtyKeys==keys.toSet())
        for(q in queues) {
            val m=q.mutation;val row=byKey.getValue(m.entity.table to m.recordId)
            require(m.entity in entities && m.subjectUserId==owner.value && m.payload==row.payload &&
                m.modifiedAt==row.updatedAt && m.baseVersion==row.syncVersion &&
                financeRawUuid(m.deviceId)==m.deviceId && m.deviceId==row.payload.financeRawString("last_modified_by_device_id") &&
                q.attemptCount>=0 && q.nextAttemptAtEpochMillis>=0 && m.kind==if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE)
        }
    }
    fun requireUnchanged(current:CardPaymentPublicationSnapshot) {
        requireCoherent();current.requireCoherent()
        require(owner==current.owner && cardId==current.cardId && dirtyKeys==current.dirtyKeys)
        require(entities.all{recordsByEntity.getValue(it).sortedBy(CloudRecord::id)==current.recordsByEntity.getValue(it).sortedBy(CloudRecord::id)})
        fun ordered(q:List<QueuedMutation>)=q.sortedWith(compareBy({it.mutation.entity.table},{it.mutation.recordId}))
        require(ordered(queues)==ordered(current.queues))
    }
}
