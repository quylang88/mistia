package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*

/** Local-only causal evidence for the one canonical investment wallet, never cloud/storage authority. */
const val LOCAL_INVESTMENT_WALLET_PARENTS_KEY="_mistia_android_investment_wallet_parents"
data class InvestmentWalletPublicationParent(val baseVersion:Long,val confirmedVersion:Long?,val deviceId:String,val fingerprint:String)

fun localInvestmentWalletPublicationParents(row:CloudRecord):List<InvestmentWalletPublicationParent> {
    val value=row.payload[LOCAL_INVESTMENT_WALLET_PARENTS_KEY] ?: return emptyList()
    canonicalInvestmentWalletForPublication(UserId(row.ownerUserId),row,forWrite=true)
    val marker=value as? JsonObject ?: throw IllegalArgumentException("Invalid local investment wallet parents")
    require(marker.keys==setOf("version","owner_user_id","wallet_id","parents") && marker["version"]==JsonPrimitive(1))
    require(marker.financeRawString("owner_user_id")==row.ownerUserId && marker.financeRawString("wallet_id")==row.id)
    val entries=marker["parents"] as? JsonArray ?: throw IllegalArgumentException("Invalid local investment wallet parents")
    require(entries.size in 1..64)
    val parents=entries.map{entry->
        val p=entry as? JsonObject ?: throw IllegalArgumentException("Invalid local investment wallet parent")
        require(p.keys==setOf("base_version","confirmed_version","device_id","fingerprint"))
        val base=requireNotNull(p.financeRawLong("base_version")).also{require(it>=0 && it<Long.MAX_VALUE && it==row.syncVersion)}
        val confirmed=if(p["confirmed_version"]==JsonNull)null else requireNotNull(p.financeRawLong("confirmed_version")).also{require(it>base)}
        val device=requireNotNull(p.financeRawString("device_id")).also{require(financeRawUuid(it)==it)}
        val hash=requireNotNull(p.financeRawString("fingerprint")).also{require(Regex("[0-9a-f]{64}").matches(it))}
        InvestmentWalletPublicationParent(base,confirmed,device,hash)
    }
    require(parents.distinct().size==parents.size)
    return parents
}

fun investmentWalletPublicationFingerprint(payload:JsonObject):String =
    RecordConflictResolver.semanticFingerprint(investmentWalletMetadataForComparison(payload))

fun investmentWalletPayloadForCloud(payload:JsonObject):JsonObject =
    JsonObject(payload-LOCAL_INVESTMENT_WALLET_PARENTS_KEY-"current_balance_minor")

fun appendInvestmentWalletPublicationParent(row:CloudRecord,parent:InvestmentWalletPublicationParent):CloudRecord {
    canonicalInvestmentWalletForPublication(UserId(row.ownerUserId),row,forWrite=true)
    val parents=(localInvestmentWalletPublicationParents(row)+parent).distinct().takeLast(64)
    val marker=buildJsonObject {
        put("version",1);put("owner_user_id",row.ownerUserId);put("wallet_id",row.id)
        put("parents",JsonArray(parents.map{p->buildJsonObject {
            put("base_version",p.baseVersion);put("confirmed_version",p.confirmedVersion?.let(::JsonPrimitive) ?: JsonNull)
            put("device_id",p.deviceId);put("fingerprint",p.fingerprint)
        }}))
    }
    return row.copy(payload=JsonObject(row.payload+(LOCAL_INVESTMENT_WALLET_PARENTS_KEY to marker))).also{localInvestmentWalletPublicationParents(it)}
}

internal fun CloudRecord.withPriorInvestmentWalletPublication(prior:CloudRecord):CloudRecord {
    canonicalInvestmentWalletForPublication(UserId(prior.ownerUserId),prior,forWrite=true)
    localInvestmentWalletPublicationParents(prior)
    if(investmentWalletPublicationFingerprint(payload)==investmentWalletPublicationFingerprint(prior.payload))return this
    val device=prior.payload.financeRawString("last_modified_by_device_id") ?: return this
    if(prior.syncVersion==Long.MAX_VALUE)return this
    return appendInvestmentWalletPublicationParent(this,InvestmentWalletPublicationParent(prior.syncVersion,null,device,investmentWalletPublicationFingerprint(prior.payload)))
}

fun isKnownPriorInvestmentWalletPublication(local:CloudRecord,remote:CloudRecord,device:String):Boolean {
    canonicalInvestmentWalletForPublication(UserId(local.ownerUserId),local,forWrite=true)
    if(remote.entity!=local.entity || remote.id!=local.id || remote.ownerUserId!=local.ownerUserId || remote.deletedAt!=null ||
        remote.payload.financeRawString("last_modified_by_device_id")!=device)return false
    val server=canonicalInvestmentWalletForPublication(UserId(local.ownerUserId),remote)
    if(server.isArchived)return false
    val fingerprint=investmentWalletPublicationFingerprint(remote.payload)
    return localInvestmentWalletPublicationParents(local).any{p->p.deviceId==device &&
        remote.syncVersion==(p.confirmedVersion ?: (p.baseVersion+1)) && p.fingerprint==fingerprint}
}
