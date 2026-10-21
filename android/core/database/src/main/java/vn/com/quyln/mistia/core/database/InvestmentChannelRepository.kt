package vn.com.quyln.mistia.core.database

import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

internal class OfflineInvestmentChannelRepository(private val store:LocalStore,private val systemWalletName:()->String):InvestmentRepository {
    override fun observeAssets(ownerUserId:UserId)=store.observeOwnedFinanceRows(CloudEntity.INVESTMENT_ASSET,ownerUserId)
    override fun observeTrades(ownerUserId:UserId)=store.observeOwnedFinanceRows(CloudEntity.INVESTMENT_TRADE,ownerUserId)
    override fun observeChannelSnapshot(owner:UserId)=store.observeInvestmentChannelSnapshot(owner).map {snapshot ->
        require(snapshot.owner==owner)
        snapshot.copy(rows=snapshot.rows.filter {row ->CloudEntity.fromTable(row.entity)?.let {it in InvestmentChannelSnapshot.entities && row.matchesFinanceReadScope(owner,it,true)}==true})
    }
    private fun fail(error:InvestmentChannelError):Nothing=throw InvestmentChannelException(error)
    private fun identity(value:String)=if(financeRawUuid(value)==value) value else fail(InvestmentChannelError.INVALID_IDENTITY)
    private fun validate(owner:UserId,id:String,device:String,now:String) {
        identity(owner.value);identity(id);identity(device)
        try{Instant.parse(now)}catch(_:Exception){fail(InvestmentChannelError.UNREADABLE_SOURCE)}
    }
    private suspend fun snapshot(owner:UserId):InvestmentChannelSnapshot=store.investmentChannelSnapshot(owner).also {
        if(it.owner!=owner || it.rows.any {row ->row.ownerUserId!=owner.value || CloudEntity.fromTable(row.entity) !in InvestmentChannelSnapshot.entities}) fail(InvestmentChannelError.UNREADABLE_SOURCE)
    }
    private fun channel(raw:CloudRecord):InvestmentChannelRecord=try{InvestmentChannelRecord.fromCloudRecord(raw)}catch(_:Exception){fail(InvestmentChannelError.UNREADABLE_SOURCE)}
    private fun current(snapshot:InvestmentChannelSnapshot,id:String):CloudRecord? {
        val rows=snapshot.records(CloudEntity.INVESTMENT_CHANNEL).filter {financeRawUuid(it.id)==id}
        if(rows.size>1 || rows.any {it.id!=id || !it.financeRawIdentity(snapshot.owner,CloudEntity.INVESTMENT_CHANNEL,true)}) fail(InvestmentChannelError.UNREADABLE_SOURCE)
        return rows.singleOrNull()
    }
    private fun mutation(row:CloudRecord,device:String)=row to PendingMutation(requireNotNull(CloudEntity.fromTable(row.entity)),row.id,row.ownerUserId,MutationKind.UPSERT,row.payload,requireNotNull(row.updatedAt),row.syncVersion,device)
    private suspend fun commit(snapshot:InvestmentChannelSnapshot,rows:List<CloudRecord>,device:String):Boolean {
        val mutations=rows.map {mutation(it,device)};snapshot.requireValidMutations(mutations)
        return store.commitInvestmentChannels(snapshot,mutations)
    }
    override suspend fun saveChannel(owner:UserId,draft:InvestmentChannelDraft,primaryCurrency:String,deviceId:String,now:String):Result<InvestmentChannelRecord> = result {
        validate(owner,draft.id,deviceId,now)
        val name=normalizedInvestmentChannelName(draft.name);if(name.isEmpty()) fail(InvestmentChannelError.NAME_REQUIRED)
        val expected=draft.expected
        expected?.let {if(it.id!=draft.id || it.ownerUserId!=owner.value) fail(InvestmentChannelError.INVALID_IDENTITY)}
        repeat(3) {
            val snapshot=snapshot(owner);val previous=current(snapshot,draft.id)
            if(expected!=null) {
                val current=previous?.let(::channel) ?: fail(InvestmentChannelError.NOT_FOUND)
                if(current.deletedAt!=null || !expected.matchesVisibleInvestmentChannel(current)) fail(InvestmentChannelError.STALE_RECORD)
                val record=previous.copy(payload=JsonObject(previous.payload+mapOf("name" to JsonPrimitive(name),"updated_at" to JsonPrimitive(now),"last_modified_by_device_id" to JsonPrimitive(deviceId))),updatedAt=now)
                if(commit(snapshot,listOf(record),deviceId)) return@result channel(record)
            } else {
                if(previous!=null) {
                    val current=channel(previous)
                    if(current.deletedAt==null && !current.isArchived && current.name==name) return@result current
                    fail(InvestmentChannelError.STALE_RECORD)
                }
                val ownedChannels=snapshot.records(CloudEntity.INVESTMENT_CHANNEL).filter {it.financeRawIdentity(owner,CloudEntity.INVESTMENT_CHANNEL,true)}
                if(ownedChannels.any {it.financeRawDeleted()==null}) fail(InvestmentChannelError.UNREADABLE_SOURCE)
                val count=ownedChannels.count {it.financeRawDeleted()==false}
                val created=InvestmentChannelRecord(draft.id,owner.value,name,"chart.line.uptrend.xyaxis","#9A67FF",count,false,null,now,now,null,0,deviceId)
                val wallet=canonicalWallet(snapshot,primaryCurrency,deviceId,now)
                if(commit(snapshot,listOf(wallet,created.toCloudRecord()),deviceId)) return@result created
            }
        }
        fail(InvestmentChannelError.STALE_RECORD)
    }
    private fun canonicalWallet(snapshot:InvestmentChannelSnapshot,primary:String,device:String,now:String):CloudRecord {
        val owner=snapshot.owner;val id=investmentSystemWalletId(owner)
        val candidates=snapshot.records(CloudEntity.LEDGER_WALLET).filter {financeRawUuid(it.id)==id}
        if(candidates.size>1 || candidates.any {it.id!=id || !it.financeRawIdentity(owner,CloudEntity.LEDGER_WALLET,true)}) fail(InvestmentChannelError.UNREADABLE_SOURCE)
        val previous=candidates.singleOrNull()
        val currency=if(previous==null) primary else previous.payload.financeRawString("currency_code") ?: fail(InvestmentChannelError.INVALID_CURRENCY)
        if(currency.investmentChannelCurrency()==null) fail(InvestmentChannelError.INVALID_CURRENCY)
        val created=previous?.payload?.financeRawString("created_at") ?: now
        try{Instant.parse(created)}catch(_:Exception){fail(InvestmentChannelError.UNREADABLE_SOURCE)}
        val version=previous?.syncVersion ?: 0L
        if(version<0 || previous?.payload?.let {p ->"sync_version" in p && p.financeRawLong("sync_version")!=version}==true) fail(InvestmentChannelError.UNREADABLE_SOURCE)
        val p=buildJsonObject {
            previous?.payload?.forEach {put(it.key,it.value)}
            put("id",id);put("user_id",owner.value);put("name",systemWalletName());put("kind_raw_value",WalletKind.INVESTMENT.wireValue)
            put("icon_symbol_name",WalletKind.INVESTMENT.defaultIcon);put("icon_color_hex",WalletKind.INVESTMENT.defaultColorHex);put("opening_balance_minor",0)
            put("institution_display_name",JsonNull);put("institution_preset_key",JsonNull);put("sort_order",Int.MAX_VALUE-100);put("is_archived",false)
            put("archived_at",JsonNull);put("deleted_at",JsonNull);put("created_at",created);put("updated_at",now)
            if(previous==null || "sync_version" in previous.payload)put("sync_version",version)
            put("last_modified_by_device_id",device);put("system_purpose_raw_value","investmentProfit")
            if(previous==null){put("currency_code",currency.investmentChannelCurrency());put("investment_linked_wallet_id",JsonNull)}
        }
        return CloudRecord(CloudEntity.LEDGER_WALLET.table,id,owner.value,p,now,null,version)
    }
    override suspend fun archiveChannel(owner:UserId,expected:InvestmentChannelRecord,deviceId:String,now:String):Result<Unit> = changeArchive(owner,expected,true,deviceId,now)
    override suspend fun restoreChannel(owner:UserId,expected:InvestmentChannelRecord,deviceId:String,now:String):Result<Unit> = changeArchive(owner,expected,false,deviceId,now)
    private suspend fun changeArchive(owner:UserId,expected:InvestmentChannelRecord,archive:Boolean,device:String,now:String):Result<Unit> = result {
        validate(owner,expected.id,device,now);if(expected.ownerUserId!=owner.value) fail(InvestmentChannelError.INVALID_IDENTITY)
        repeat(3) {
            val snapshot=snapshot(owner);val raw=current(snapshot,expected.id) ?: fail(InvestmentChannelError.NOT_FOUND);val current=channel(raw)
            if(current.deletedAt!=null || !expected.matchesVisibleInvestmentChannel(current)) fail(InvestmentChannelError.STALE_RECORD)
            if(current.isArchived==archive) return@result
            if(archive) requireClosedPositions(snapshot,current.id)
            val record=raw.copy(payload=JsonObject(raw.payload+mapOf("is_archived" to JsonPrimitive(archive),"archived_at" to (if(archive) JsonPrimitive(now) else JsonNull),"updated_at" to JsonPrimitive(now),"last_modified_by_device_id" to JsonPrimitive(device))),updatedAt=now)
            if(commit(snapshot,listOf(record),device)) return@result
        }
        fail(InvestmentChannelError.STALE_RECORD)
    }
    private fun requireClosedPositions(snapshot:InvestmentChannelSnapshot,channelId:String) {
        val assets=snapshot.records(CloudEntity.INVESTMENT_ASSET).filter {it.financeRawIdentity(snapshot.owner,CloudEntity.INVESTMENT_ASSET,true) && it.financeRawDeleted()!=true && it.payload.financeRawArchived()!=true}
        val relevant=assets.filter {val ref=it.payload.financeRawReference("channel_id");!ref.readable || ref.id==channelId}
        if(relevant.isEmpty()) return
        val trades=snapshot.records(CloudEntity.INVESTMENT_TRADE).filter {it.financeRawIdentity(snapshot.owner,CloudEntity.INVESTMENT_TRADE,true) && it.financeRawDeleted()!=true}
        if(trades.any {!it.payload.financeRawReference("asset_id").readable}) fail(InvestmentChannelError.UNREADABLE_POSITION)
        for(asset in relevant) {
            val candidates=trades.filter {it.payload.financeRawReference("asset_id").id==financeRawUuid(asset.id)}
            if(candidates.isEmpty()) continue
            if(candidates.any {it.financeRawDeleted()==null || it.payload.financeRawString("occurred_at")?.let {value ->runCatching {Instant.parse(value)}.isFailure}!=false || it.payload.financeRawString("created_at")?.let {value ->runCatching {Instant.parse(value)}.isFailure}!=false}) fail(InvestmentChannelError.UNREADABLE_POSITION)
            val latest=candidates.maxWithOrNull(compareBy<CloudRecord>{Instant.parse(it.payload.financeRawString("occurred_at"))}.thenBy{Instant.parse(it.payload.financeRawString("created_at"))}.thenBy{it.id})!!
            val quantity=latest.payload.financeRawString("position_quantity_after_decimal_string")?.toBigDecimalOrNull() ?: fail(InvestmentChannelError.UNREADABLE_POSITION)
            if(quantity.signum()>0) {
                if(asset.financeRawDeleted()==null || asset.payload.financeRawArchived()==null || !asset.payload.financeRawReference("channel_id").readable) fail(InvestmentChannelError.UNREADABLE_POSITION)
                fail(InvestmentChannelError.OPEN_POSITION)
            }
        }
    }
    private inline fun <T> result(block:()->T):Result<T> = try{Result.success(block())}catch(cancelled:CancellationException){throw cancelled}catch(error:Exception){Result.failure(error)}
}
private fun String.investmentChannelCurrency():String?=financeReportingCode()?.takeIf {runCatching {java.util.Currency.getInstance(it).defaultFractionDigits>=0}.getOrDefault(false)}
