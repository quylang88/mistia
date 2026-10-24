package vn.com.quyln.mistia.core.model

/** The channel row, its dirty marker and exact queue must belong to one database generation. */
data class InvestmentChannelPublicationSnapshot(
    val owner:UserId,val record:CloudRecord?,val pending:QueuedMutation?,val hasPendingMutation:Boolean,
) {
    fun matches(queued:QueuedMutation,expected:CloudRecord?=record):Boolean {
        val q=queued.mutation;val row=record ?: return false
        return owner.value==q.subjectUserId && q.entity==CloudEntity.INVESTMENT_CHANNEL &&
            row.ownerUserId==owner.value && row.entity==q.entity.table && row.id==q.recordId && row==expected &&
            hasPendingMutation && pending==queued && row.payload==q.payload && row.syncVersion==q.baseVersion &&
            row.updatedAt==q.modifiedAt && row.payload.financeRawString("last_modified_by_device_id")==q.deviceId && q.kind==(if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE)
    }
}
