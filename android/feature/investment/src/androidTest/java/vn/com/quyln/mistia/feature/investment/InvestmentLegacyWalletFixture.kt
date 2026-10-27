package vn.com.quyln.mistia.feature.investment

import androidx.room.withTransaction
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.model.*

/** Test-only rehydration of pre-guard/legacy pending state. Current user mutations must remain rejected. */
internal suspend fun restoreLegacyInvestmentFixture(database:MistiaDatabase,mutations:List<Pair<CloudRecord,PendingMutation>>) {
    require(mutations.isNotEmpty() && mutations.map{it.first.ownerUserId}.distinct().size==1)
    require(mutations.map{it.first.entity to it.first.id}.distinct().size==mutations.size)
    database.withTransaction {
        for((row,q) in mutations) {
            require(row.ownerUserId==q.subjectUserId && row.entity==q.entity.table && row.id==q.recordId && row.payload==q.payload)
            val old=checkNotNull(database.cloudRecordDao().record(row.ownerUserId,row.entity,row.id))
            val queued=database.syncOutboxDao().record(row.ownerUserId,row.entity,row.id)
            database.cloudRecordDao().upsert(old.copy(payloadJson=row.payload.toString(),updatedAt=row.updatedAt,deletedAt=row.deletedAt,syncVersion=row.syncVersion,hasPendingMutation=true))
            database.syncOutboxDao().upsert(queued?.copy(payloadJson=row.payload.toString(),kind=q.kind.name.lowercase(),modifiedAt=q.modifiedAt,baseVersion=q.baseVersion,deviceId=q.deviceId)
                ?: SyncOutboxEntity(q.subjectUserId,q.entity.table,q.recordId,q.kind.name.lowercase(),row.payload.toString(),q.modifiedAt,q.baseVersion,q.deviceId,
                    remoteIdentityObserved=q.baseVersion>0 || !old.hasPendingMutation))
        }
    }
}
