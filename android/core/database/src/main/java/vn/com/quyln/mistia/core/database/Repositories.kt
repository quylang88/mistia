package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.EntityCount
import vn.com.quyln.mistia.core.model.FamilyRepository
import vn.com.quyln.mistia.core.model.FinanceRepository
import vn.com.quyln.mistia.core.model.InvestmentRepository
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.ReadOnlyCloudCollection
import vn.com.quyln.mistia.core.model.RecordId
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.WalletDraft

class OfflineFirstFinanceRepository(private val localStore: LocalStore) : FinanceRepository {
    override fun observe(entity: CloudEntity, ownerUserId: UserId): Flow<List<CloudRecord>> =
        localStore.observe(entity.table, ownerUserId)

    override fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>> =
        localStore.observeEntityCounts(ownerUserId)

    override fun observeWallets(ownerUserId: UserId): Flow<List<LedgerWalletRecord>> =
        localStore.observe(CloudEntity.LEDGER_WALLET.table, ownerUserId).map { records ->
            records.mapNotNull { record ->
                runCatching { LedgerWalletRecord.fromCloudRecord(record) }.getOrNull()
            }.filterNot(LedgerWalletRecord::isArchived)
                .sortedWith(compareBy(LedgerWalletRecord::sortOrder, LedgerWalletRecord::createdAt, LedgerWalletRecord::id))
        }

    override suspend fun saveWallet(
        ownerUserId: UserId,
        draft: WalletDraft,
        deviceId: String,
        now: String,
    ): Result<LedgerWalletRecord> = runCatching {
        val existing = draft.id?.let { recordId ->
            localStore.record(ownerUserId, CloudEntity.LEDGER_WALLET.table, recordId.lowercase())
                ?.let(LedgerWalletRecord::fromCloudRecord)
        }
        val mutation = draft.toMutation(ownerUserId, existing, deviceId, now)
        localStore.commitMutation(mutation.record, mutation.pending)
        LedgerWalletRecord.fromCloudRecord(mutation.record)
    }

    override suspend fun archiveWallet(
        ownerUserId: UserId,
        walletId: RecordId,
        deviceId: String,
        now: String,
    ): Result<Unit> = runCatching {
        val record = localStore.record(
            ownerUserId,
            CloudEntity.LEDGER_WALLET.table,
            walletId.value.lowercase(),
        ) ?: error("Wallet not found")
        val mutation = LedgerWalletRecord.fromCloudRecord(record).toArchiveMutation(deviceId, now)
        localStore.commitMutation(mutation.record, mutation.pending)
    }
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
