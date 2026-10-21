package vn.com.quyln.mistia.core.model

import java.time.Instant
import kotlinx.serialization.json.*

/** Wire identity and version are preserved independently of editor state. */
data class InvestmentChannelRecord(val id:String,val ownerUserId:String,val name:String,val iconSymbolName:String,val iconColorHex:String,
    val sortOrder:Int,val isArchived:Boolean,val archivedAt:String?,val createdAt:String,val updatedAt:String,val deletedAt:String?,val syncVersion:Long,val lastModifiedByDeviceId:String?) {
    fun toCloudRecord():CloudRecord=CloudRecord(CloudEntity.INVESTMENT_CHANNEL.table,id,ownerUserId,buildJsonObject {
        put("id",id);put("user_id",ownerUserId);put("name",name);put("icon_symbol_name",iconSymbolName);put("icon_color_hex",iconColorHex);put("sort_order",sortOrder)
        put("is_archived",isArchived);put("archived_at",archivedAt?.let(::JsonPrimitive) ?: JsonNull);put("created_at",createdAt);put("updated_at",updatedAt)
        put("deleted_at",deletedAt?.let(::JsonPrimitive) ?: JsonNull);put("sync_version",syncVersion);put("last_modified_by_device_id",lastModifiedByDeviceId?.let(::JsonPrimitive) ?: JsonNull)
    },updatedAt,deletedAt,syncVersion)
    companion object {
        fun fromCloudRecord(raw:CloudRecord):InvestmentChannelRecord {
            val owner=UserId(raw.ownerUserId)
            require(raw.financeRawIdentity(owner,CloudEntity.INVESTMENT_CHANNEL,true))
            val p=raw.payload
            fun text(key:String)=requireNotNull(p.financeRawString(key)) {"Unreadable channel $key"}
            fun date(key:String)=text(key).also {Instant.parse(it)}
            fun optional(key:String):String? {
                if(p[key]==null || p[key]==JsonNull) return null
                return date(key)
            }
            val version=if("sync_version" in p) requireNotNull(p.financeRawLong("sync_version")) else raw.syncVersion
            require(version==raw.syncVersion && version>=0)
            return InvestmentChannelRecord(requireNotNull(financeRawUuid(raw.id)),requireNotNull(financeRawUuid(raw.ownerUserId)),text("name"),text("icon_symbol_name"),text("icon_color_hex"),
                requireNotNull((p["sort_order"] as? JsonPrimitive)?.takeIf {!it.isString}?.intOrNull),requireNotNull(p.financeRawArchived()),optional("archived_at"),
                date("created_at"),date("updated_at"),raw.deletedAt?.also {Instant.parse(it)} ?: optional("deleted_at"),version,p.financeRawString("last_modified_by_device_id"))
        }
    }

}
data class InvestmentChannelDraft(val id:String,val name:String,val expected:InvestmentChannelRecord?=null)
enum class InvestmentChannelError {INVALID_IDENTITY,NAME_REQUIRED,INVALID_CURRENCY,UNREADABLE_SOURCE,NOT_FOUND,STALE_RECORD,OPEN_POSITION,UNREADABLE_POSITION}
class InvestmentChannelException(val reason:InvestmentChannelError):IllegalArgumentException(reason.name)

data class InvestmentChannelSnapshot(val owner:UserId,val rows:List<CloudRecord>) {
    fun records(entity:CloudEntity)=rows.filter {it.entity==entity.table}
    fun requireUnchanged(current:InvestmentChannelSnapshot) {
        require(current.owner==owner)
        fun ordered(rows:List<CloudRecord>)=rows.sortedWith(compareBy(CloudRecord::entity,CloudRecord::id))
        require(ordered(current.rows)==ordered(rows))
    }
    fun requireValidMutations(mutations:List<Pair<CloudRecord,PendingMutation>>) {
        require(financeRawUuid(owner.value)==owner.value)
        require(rows.all {it.ownerUserId==owner.value && CloudEntity.fromTable(it.entity) in entities})
        require(rows.map {it.entity to it.id}.distinct().size==rows.size)
        require(mutations.size in 1..2 && mutations.map {it.first.entity to it.first.id}.distinct().size==mutations.size)
        val channel=mutations.single {it.first.entity==CloudEntity.INVESTMENT_CHANNEL.table}.first
        require(channel.financeRawIdentity(owner,CloudEntity.INVESTMENT_CHANNEL,true) && financeRawUuid(channel.id)==channel.id)
        val typed=InvestmentChannelRecord.fromCloudRecord(channel)
        require(typed.name.isNotEmpty() && typed.name==normalizedInvestmentChannelName(typed.name) && typed.deletedAt==null)
        val original=records(CloudEntity.INVESTMENT_CHANNEL).singleOrNull {it.id==channel.id}
        if(original!=null) {
            val before=InvestmentChannelRecord.fromCloudRecord(original);require(before.deletedAt==null)
            val editable=setOf("name","is_archived","archived_at","updated_at","last_modified_by_device_id")
            require((original.payload.keys+channel.payload.keys).all {it in editable || original.payload[it]==channel.payload[it]})
            require(mutations.size==1)
        } else require(typed.createdAt==typed.updatedAt && !typed.isArchived && typed.archivedAt==null && typed.syncVersion==0L && mutations.size==2)
        mutations.forEach {(row,pending) ->
            val entity=requireNotNull(CloudEntity.fromTable(row.entity))
            require(entity in setOf(CloudEntity.LEDGER_WALLET,CloudEntity.INVESTMENT_CHANNEL))
            require(row.financeRawIdentity(owner,entity,true) && financeRawUuid(row.id)==row.id)
            val previous=records(entity).singleOrNull {it.id==row.id}
            require(row.deletedAt==null && row.financeRawDeleted()==false && row.syncVersion==(previous?.syncVersion ?: 0L))
            require(pending.entity==entity && pending.recordId==row.id && pending.subjectUserId==owner.value && pending.payload==row.payload && pending.kind==MutationKind.UPSERT)
            require(pending.baseVersion==row.syncVersion && pending.modifiedAt==row.updatedAt && row.updatedAt==typed.updatedAt)
            require(financeRawUuid(pending.deviceId)==pending.deviceId && row.payload.financeRawString("last_modified_by_device_id")==pending.deviceId)
            if(entity==CloudEntity.LEDGER_WALLET) {
                require(original==null && row.id==investmentSystemWalletId(owner))
                val wallet=LedgerWalletRecord.fromCloudRecord(row)
                require(wallet.kind==WalletKind.INVESTMENT && wallet.openingBalanceMinor==0L && wallet.sortOrder==Int.MAX_VALUE-100 && !wallet.isArchived && wallet.archivedAt==null)
                require(wallet.currencyCode.investmentAccountingCode()!=null && wallet.systemPurposeRawValue=="investmentProfit")
                if(previous!=null) {
                    val canonical=setOf("name","kind_raw_value","icon_symbol_name","icon_color_hex","opening_balance_minor","institution_display_name","institution_preset_key","sort_order","is_archived","archived_at","deleted_at","system_purpose_raw_value","updated_at","last_modified_by_device_id")
                    require((previous.payload.keys+row.payload.keys).all {it in canonical || previous.payload[it]==row.payload[it]})
                }
            }
        }
    }
    companion object {val entities=setOf(CloudEntity.LEDGER_WALLET,CloudEntity.INVESTMENT_CHANNEL,CloudEntity.INVESTMENT_ASSET,CloudEntity.INVESTMENT_TRADE)}
}

/** Visible consent ignores only synchronization acknowledgement metadata. */
fun InvestmentChannelRecord.matchesVisibleInvestmentChannel(other:InvestmentChannelRecord):Boolean =
    copy(updatedAt="",syncVersion=0,lastModifiedByDeviceId=null,createdAt=Instant.parse(createdAt).toString())==
        other.copy(updatedAt="",syncVersion=0,lastModifiedByDeviceId=null,createdAt=Instant.parse(other.createdAt).toString())

/** The ordinary wallet pipeline cannot publish investment-domain state independently. */
fun requiresInvestmentWalletDomain(owner:UserId,id:String,payload:JsonObject?):Boolean {
    val canonical=runCatching{investmentSystemWalletId(owner)}.getOrNull()
    return (canonical!=null && financeRawUuid(id)==canonical) || payload?.financeRawString("kind_raw_value")=="investment" ||
        payload?.financeRawString("system_purpose_raw_value")=="investmentProfit"
}

/** Exact Foundation whitespacesAndNewlines set; Java also includes unrelated controls. */
fun normalizedInvestmentChannelName(value:String):String=value.trim{
    it in '\u0009'..'\u000d' || it==' ' || it=='\u0085' || it=='\u00a0' || it=='\u1680' ||
        it in '\u2000'..'\u200b' || it=='\u2028' || it=='\u2029' || it=='\u202f' || it=='\u205f' || it=='\u3000'
}
