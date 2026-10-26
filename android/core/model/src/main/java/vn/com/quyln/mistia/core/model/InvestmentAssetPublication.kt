package vn.com.quyln.mistia.core.model

/** One atomic metadata/outbox generation plus its reconciled private photo authority. */
data class InvestmentAssetPublicationSnapshot(
    val owner:UserId,val record:CloudRecord?,val pending:QueuedMutation?,val hasPendingMutation:Boolean,
    val imagePublication:InvestmentProductImagePublication?=null,val imageAcknowledged:Boolean=false,
) {
    fun matches(queued:QueuedMutation,expected:CloudRecord?=record):Boolean {
        val q=queued.mutation;val row=record ?: return false
        return owner.value==q.subjectUserId && q.entity==CloudEntity.INVESTMENT_ASSET &&
            row.ownerUserId==owner.value && row.entity==q.entity.table && row.id==q.recordId && row==expected &&
            hasPendingMutation && pending==queued && row.payload==q.payload && row.syncVersion==q.baseVersion &&
            row.updatedAt==q.modifiedAt && row.payload.financeRawString("last_modified_by_device_id")==q.deviceId &&
            q.kind==(if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE)
    }
}
