package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.EntityCount
import vn.com.quyln.mistia.core.model.FamilyRepository
import vn.com.quyln.mistia.core.model.FinanceRepository
import vn.com.quyln.mistia.core.model.InvestmentRepository
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.ReadOnlyCloudCollection
import vn.com.quyln.mistia.core.model.UserId

class OfflineFirstFinanceRepository(private val localStore: LocalStore) : FinanceRepository {
    override fun observe(entity: CloudEntity, ownerUserId: UserId): Flow<List<CloudRecord>> =
        localStore.observe(entity.table, ownerUserId)

    override fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>> =
        localStore.observeEntityCounts(ownerUserId)
}

class OfflineFirstFamilyRepository(private val localStore: LocalStore) : FamilyRepository {
    override fun observeFamilyRows(ownerUserId: UserId): Flow<List<CloudRecord>> = combine(
        ReadOnlyCloudCollection.entries
            .filter { it.name.startsWith("FAMILY") }
            .map { localStore.observe(it.table, ownerUserId) }
    ) { rows -> rows.flatMap { it } }
}

class OfflineFirstInvestmentRepository(private val localStore: LocalStore) : InvestmentRepository {
    override fun observeAssets(ownerUserId: UserId): Flow<List<CloudRecord>> =
        localStore.observe(CloudEntity.INVESTMENT_ASSET.table, ownerUserId)

    override fun observeTrades(ownerUserId: UserId): Flow<List<CloudRecord>> =
        localStore.observe(CloudEntity.INVESTMENT_TRADE.table, ownerUserId)
}
