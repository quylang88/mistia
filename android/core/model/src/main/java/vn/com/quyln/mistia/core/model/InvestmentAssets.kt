package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import java.time.Instant
import java.util.Currency

data class InvestmentAssetRecord(
    val id: String,
    val ownerUserId: String,
    val channelId: String,
    val name: String,
    val currencyCode: String,
    val imagePath: String?,
    val defaultUnitLabel: String?,
    val sortOrder: Int,
    val isArchived: Boolean,
    val archivedAt: String?,
    val createdAt: String,
    val updatedAt: String,
    val deletedAt: String?,
    val syncVersion: Long,
    val lastModifiedByDeviceId: String?,
) {
    fun toCloudRecord(): CloudRecord = CloudRecord(CloudEntity.INVESTMENT_ASSET.table,id,ownerUserId,buildJsonObject {
        put("id",id);put("user_id",ownerUserId);put("channel_id",channelId);put("name",name);put("currency_code",currencyCode)
        put("image_path",imagePath?.let(::JsonPrimitive) ?: JsonNull);put("default_unit_label",defaultUnitLabel?.let(::JsonPrimitive) ?: JsonNull)
        put("sort_order",sortOrder);put("is_archived",isArchived);put("archived_at",archivedAt?.let(::JsonPrimitive) ?: JsonNull)
        put("created_at",createdAt);put("updated_at",updatedAt);put("deleted_at",deletedAt?.let(::JsonPrimitive) ?: JsonNull)
        put("sync_version",syncVersion);put("last_modified_by_device_id",lastModifiedByDeviceId?.let(::JsonPrimitive) ?: JsonNull)
    },updatedAt,deletedAt,syncVersion)
    companion object {
        fun fromCloudRecord(raw: CloudRecord): InvestmentAssetRecord {
            val owner=UserId(raw.ownerUserId)
            require(raw.financeRawIdentity(owner,CloudEntity.INVESTMENT_ASSET,true))
            val p=raw.payload
            fun text(key:String)=requireNotNull(p.financeRawString(key))
            fun optional(key:String):String? {
                if(p[key]==null || p[key]==JsonNull)return null
                return text(key)
            }
            fun date(key:String)=text(key).also{Instant.parse(it)}
            fun optionalDate(key:String)=optional(key)?.also{Instant.parse(it)}
            val version=investmentAssetVersion(raw)
            return InvestmentAssetRecord(requireNotNull(financeRawUuid(raw.id)),requireNotNull(financeRawUuid(raw.ownerUserId)),
                requireNotNull(financeRawUuid(text("channel_id"))),text("name"),requireNotNull(investmentAssetCurrency(text("currency_code"))),
                optional("image_path"),optional("default_unit_label"),requireNotNull((p["sort_order"] as? JsonPrimitive)?.takeIf{!it.isString}?.intOrNull),
                requireNotNull(p.financeRawArchived()),optionalDate("archived_at"),date("created_at"),date("updated_at"),
                raw.deletedAt?.also{Instant.parse(it)} ?: optionalDate("deleted_at"),version,optional("last_modified_by_device_id"))
        }
    }
}

data class InvestmentAssetDraft(
    val id: String,
    val channelId: String,
    val name: String,
    val currencyCode: String,
    val defaultUnitLabel: String,
    val expected: InvestmentAssetRecord? = null,
    val imageChange: InvestmentAssetImageChange = InvestmentAssetImageChange.Keep,
)

enum class InvestmentAssetError {
    INVALID_IDENTITY, NAME_REQUIRED, UNIT_REQUIRED, INVALID_CURRENCY, MISSING_CHANNEL,
    UNREADABLE_SOURCE, NOT_FOUND, STALE_RECORD, HISTORY_LOCKS_ACCOUNTING, OPEN_POSITION,
    UNREADABLE_POSITION, MISSING_WALLET, MISSING_EXCHANGE_RATE, INVALID_ACCOUNTING,
}
class InvestmentAssetException(val reason: InvestmentAssetError) : IllegalArgumentException(reason.name)

data class InvestmentAssetSnapshot(val owner: UserId, val rows: List<CloudRecord>) {
    fun records(entity: CloudEntity): List<CloudRecord> = rows.filter { it.entity == entity.table }
    fun requireUnchanged(current:InvestmentAssetSnapshot) {
        require(owner==current.owner)
        fun ordered(values:List<CloudRecord>)=values.sortedWith(compareBy(CloudRecord::entity,CloudRecord::id))
        require(ordered(rows)==ordered(current.rows))
    }
    companion object {
        val entities = InvestmentChannelSnapshot.entities + setOf(CloudEntity.LEDGER_TRANSACTION, CloudEntity.INVESTMENT_POSTING)
    }
}

sealed interface InvestmentAssetRequest {
    data class Save(val draft: InvestmentAssetDraft) : InvestmentAssetRequest
    data class Archive(val expected: InvestmentAssetRecord, val archived: Boolean) : InvestmentAssetRequest
}

data class InvestmentAssetMutationPlan(
    val asset: InvestmentAssetRecord,
    val mutations: List<Pair<CloudRecord, PendingMutation>>,
)

fun planInvestmentAssetMutation(
    snapshot: InvestmentAssetSnapshot,
    request: InvestmentAssetRequest,
    deviceId: String,
    now: String,
): InvestmentAssetMutationPlan {
    investmentAssetIdentity(snapshot.owner.value);investmentAssetIdentity(deviceId);investmentAssetDate(now)
    if(snapshot.rows.any{row ->
        row.ownerUserId!=snapshot.owner.value || CloudEntity.fromTable(row.entity) !in InvestmentAssetSnapshot.entities ||
            !row.financeRawIdentity(snapshot.owner,CloudEntity.fromTable(row.entity)!!,true) || financeRawUuid(row.id)!=row.id
    } || snapshot.rows.map{it.entity to it.id}.distinct().size!=snapshot.rows.size)investmentAssetFail(InvestmentAssetError.UNREADABLE_SOURCE)
    val id=when(request){is InvestmentAssetRequest.Save->request.draft.id;is InvestmentAssetRequest.Archive->request.expected.id}
    investmentAssetIdentity(id)
    val raw=snapshot.records(CloudEntity.INVESTMENT_ASSET).singleOrNull{it.id==id}
    val current=raw?.let{investmentAssetDecode(it)}
    fun expected(value:InvestmentAssetRecord) {
        if(value.id!=id || value.ownerUserId!=snapshot.owner.value)investmentAssetFail(InvestmentAssetError.INVALID_IDENTITY)
        if(current==null)investmentAssetFail(InvestmentAssetError.NOT_FOUND)
        if(current.deletedAt!=null || !value.matchesVisibleInvestmentAsset(current))investmentAssetFail(InvestmentAssetError.STALE_RECORD)
    }
    val changed:CloudRecord
    val extras:List<CloudRecord>
    when(request) {
        is InvestmentAssetRequest.Save -> {
            val draft=request.draft
            investmentAssetIdentity(draft.channelId)
            val name=normalizedInvestmentChannelName(draft.name)
            if(name.isEmpty())investmentAssetFail(InvestmentAssetError.NAME_REQUIRED)
            val unit=InvestmentUnitLabel.normalizedDisplay(draft.defaultUnitLabel) ?: investmentAssetFail(InvestmentAssetError.UNIT_REQUIRED)
            val currency=investmentAssetCurrency(draft.currencyCode) ?: investmentAssetFail(InvestmentAssetError.INVALID_CURRENCY)
            draft.expected?.let(::expected)
            val image=when(val change=draft.imageChange) {
                InvestmentAssetImageChange.Keep->current?.imagePath
                InvestmentAssetImageChange.Remove->null
                is InvestmentAssetImageChange.Replace->InvestmentProductImagePath.parse(snapshot.owner,id,change.path.value).value
            }
            if(current!=null && draft.expected==null) {
                if(current.deletedAt==null && !current.isArchived && current.name==name && current.channelId==draft.channelId &&
                    current.currencyCode==currency && current.defaultUnitLabel==unit && current.imagePath==image)return InvestmentAssetMutationPlan(current,emptyList())
                investmentAssetFail(InvestmentAssetError.STALE_RECORD)
            }
            val channelRaw=snapshot.records(CloudEntity.INVESTMENT_CHANNEL).singleOrNull{it.id==draft.channelId}
                ?: investmentAssetFail(InvestmentAssetError.MISSING_CHANNEL)
            val channel=try{InvestmentChannelRecord.fromCloudRecord(channelRaw)}catch(_:Exception){investmentAssetFail(InvestmentAssetError.UNREADABLE_SOURCE)}
            if(channel.deletedAt!=null || channel.isArchived)investmentAssetFail(InvestmentAssetError.MISSING_CHANNEL)
            val history=investmentAssetHistory(snapshot,id)
            if(history.isNotEmpty() && current!=null && (current.channelId!=draft.channelId || current.currencyCode!=currency))
                investmentAssetFail(InvestmentAssetError.HISTORY_LOCKS_ACCOUNTING)
            if(raw==null) {
                val live=snapshot.records(CloudEntity.INVESTMENT_ASSET).filter{
                    if(it.financeRawDeleted(true)==null)investmentAssetFail(InvestmentAssetError.UNREADABLE_SOURCE)
                    it.financeRawDeleted(true)==false
                }
                val count=live.count{
                    val ref=it.payload.financeRawReference("channel_id")
                    if(!ref.readable)investmentAssetFail(InvestmentAssetError.UNREADABLE_SOURCE)
                    ref.id==draft.channelId
                }
                changed=InvestmentAssetRecord(id,snapshot.owner.value,draft.channelId,name,currency,image,unit,count,false,null,now,now,null,0,deviceId).toCloudRecord()
                extras=emptyList()
            } else {
                changed=investmentAssetChanged(raw,buildJsonObject {
                    put("name",name);put("channel_id",draft.channelId);put("currency_code",currency);put("default_unit_label",unit)
                    if(draft.imageChange!=InvestmentAssetImageChange.Keep)put("image_path",image?.let(::JsonPrimitive) ?: JsonNull)
                },deviceId,now)
                if(current!!.defaultUnitLabel==null && history.any{
                    val value=it.payload["unit_label"]
                    value!=null && value!=JsonNull && it.payload.financeRawString("unit_label")==null
                })investmentAssetFail(InvestmentAssetError.UNREADABLE_SOURCE)
                extras=if(current.defaultUnitLabel==null && history.any{it.payload["unit_label"]==null || it.payload["unit_label"]==JsonNull})
                    rebuildInvestmentAssetUnitHistory(snapshot,investmentAssetDecode(changed),unit,deviceId,now) else emptyList()
            }
        }
        is InvestmentAssetRequest.Archive -> {
            expected(request.expected)
            if(current!!.isArchived==request.archived)return InvestmentAssetMutationPlan(current,emptyList())
            if(request.archived)requireInvestmentAssetClosed(snapshot,current)
            changed=investmentAssetChanged(requireNotNull(raw),buildJsonObject {
                put("is_archived",request.archived);put("archived_at",if(request.archived)JsonPrimitive(now) else JsonNull)
            },deviceId,now)
            extras=emptyList()
        }
    }
    val mutations=(listOf(changed)+extras).map{row ->
        row to PendingMutation(requireNotNull(CloudEntity.fromTable(row.entity)),row.id,snapshot.owner.value,MutationKind.UPSERT,row.payload,now,row.syncVersion,deviceId)
    }
    require(mutations.map{it.first.entity to it.first.id}.distinct().size==mutations.size)
    return InvestmentAssetMutationPlan(investmentAssetDecode(changed),mutations)
}

internal fun investmentAssetFail(reason:InvestmentAssetError):Nothing=throw InvestmentAssetException(reason)
internal fun investmentAssetIdentity(value:String):String=financeRawUuid(value)?.takeIf{it==value} ?: investmentAssetFail(InvestmentAssetError.INVALID_IDENTITY)
internal fun investmentAssetDate(value:String):String=try{Instant.parse(value);value}catch(_:Exception){investmentAssetFail(InvestmentAssetError.UNREADABLE_SOURCE)}
internal fun investmentAssetCurrency(value:String):String?=value.financeReportingCode()?.takeIf{runCatching{Currency.getInstance(it).defaultFractionDigits>=0}.getOrDefault(false)}
internal fun investmentAssetVersion(raw:CloudRecord):Long {
    val version=raw.syncVersion
    require(version>=0 && ("sync_version" !in raw.payload || raw.payload.financeRawLong("sync_version")==version))
    return version
}
internal fun investmentAssetDecode(raw:CloudRecord):InvestmentAssetRecord=try{InvestmentAssetRecord.fromCloudRecord(raw)}catch(_:Exception){investmentAssetFail(InvestmentAssetError.UNREADABLE_SOURCE)}
internal fun investmentAssetChanged(raw:CloudRecord,fields:JsonObject,device:String,now:String):CloudRecord {
    try{investmentAssetVersion(raw)}catch(_:Exception){investmentAssetFail(InvestmentAssetError.UNREADABLE_SOURCE)}
    return raw.copy(payload=JsonObject(raw.payload+(if(raw.deletedAt!=null && "deleted_at" !in fields) mapOf("deleted_at" to JsonPrimitive(raw.deletedAt)) else emptyMap())+fields+mapOf("updated_at" to JsonPrimitive(now),"last_modified_by_device_id" to JsonPrimitive(device))),updatedAt=now)
}
fun InvestmentAssetRecord.matchesVisibleInvestmentAsset(other:InvestmentAssetRecord):Boolean=
    copy(updatedAt="",syncVersion=0,lastModifiedByDeviceId=null,createdAt=Instant.parse(createdAt).toString(),archivedAt=archivedAt?.let{Instant.parse(it).toString()})==
        other.copy(updatedAt="",syncVersion=0,lastModifiedByDeviceId=null,createdAt=Instant.parse(other.createdAt).toString(),archivedAt=other.archivedAt?.let{Instant.parse(it).toString()})

internal fun investmentAssetHistory(snapshot:InvestmentAssetSnapshot,id:String):List<CloudRecord> =
    snapshot.records(CloudEntity.INVESTMENT_TRADE).filter{trade ->
        val reference=trade.payload.financeRawReference("asset_id")
        if(!reference.readable || reference.id==null)investmentAssetFail(InvestmentAssetError.UNREADABLE_SOURCE)
        reference.id==id
    }

internal fun requireInvestmentAssetClosed(snapshot:InvestmentAssetSnapshot,asset:InvestmentAssetRecord) {
    val trades=investmentAssetHistory(snapshot,asset.id).filter{
        it.financeRawDeleted(true) ?: investmentAssetFail(InvestmentAssetError.UNREADABLE_POSITION)
        it.financeRawDeleted(true)==false
    }
    if(trades.isEmpty())return
    fun date(raw:CloudRecord,key:String)=raw.payload.financeRawString(key)?.let{runCatching{Instant.parse(it)}.getOrNull()}
        ?: investmentAssetFail(InvestmentAssetError.UNREADABLE_POSITION)
    // The hub prefers the current FIFO projection. Persisted snapshots are
    // only its compatibility fallback for histories the engine cannot read.
    val inputs=try {
        trades.map { trade ->
            val p=trade.payload
            val kind=when(p.financeRawString("kind_raw_value")) {
                "buy"->InvestmentTradeKind.BUY;"sell"->InvestmentTradeKind.SELL
                else->investmentAssetFail(InvestmentAssetError.UNREADABLE_POSITION)
            }
            val label=p["unit_label"]
            require(label==null || label==JsonNull || p.financeRawString("unit_label")!=null)
            InvestmentTradeInput(java.util.UUID.fromString(trade.id),kind,
                requireNotNull(p.financeRawString("quantity_decimal_string")?.toBigDecimalOrNull()),
                p.financeRawString("unit_label") ?: asset.defaultUnitLabel,
                requireNotNull(p.financeRawLong("accounting_gross_amount_minor")),date(trade,"occurred_at"),date(trade,"created_at"))
        }
    }catch(_:Exception){investmentAssetFail(InvestmentAssetError.UNREADABLE_POSITION)}
    val projection=runCatching {InvestmentAccountingEngine.projection(inputs)}.getOrNull()
    if(projection!=null) {
        if(projection.calculations.last().positionQuantityAfter.signum()>0)investmentAssetFail(InvestmentAssetError.OPEN_POSITION)
        return
    }
    val latest=trades.maxWithOrNull(compareBy<CloudRecord>{date(it,"occurred_at")}.thenBy{date(it,"created_at")}.thenBy{it.id})!!
    val quantity=latest.payload.financeRawString("position_quantity_after_decimal_string")?.toBigDecimalOrNull()
        ?: investmentAssetFail(InvestmentAssetError.UNREADABLE_POSITION)
    if(quantity.signum()>0)investmentAssetFail(InvestmentAssetError.OPEN_POSITION)
}
