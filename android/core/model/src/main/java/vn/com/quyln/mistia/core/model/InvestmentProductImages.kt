package vn.com.quyln.mistia.core.model

/** Private object identity, scoped to the asset's owner and stable asset ID. */
@JvmInline value class InvestmentProductImagePath private constructor(val value:String) {
    companion object {
        fun create(owner:UserId,assetId:String,objectId:String):InvestmentProductImagePath {
            requireCanonical(owner.value);requireCanonical(assetId);requireCanonical(objectId)
            return InvestmentProductImagePath("${owner.value}/$assetId/$objectId.jpg")
        }
        fun parse(owner:UserId,assetId:String,raw:String):InvestmentProductImagePath {
            requireCanonical(owner.value);requireCanonical(assetId)
            require(raw.length==114){"Invalid private product image path"}
            val parts=raw.split('/')
            require(parts.size==3 && parts[0]==owner.value && parts[1]==assetId && parts[2].endsWith(".jpg")){"Private product image owner or asset mismatch"}
            requireCanonical(parts[2].removeSuffix(".jpg"))
            return InvestmentProductImagePath(raw)
        }
        private fun requireCanonical(value:String) {
            require(financeRawUuid(value)==value){"Product image identity must be a canonical UUID"}
        }
    }
}

sealed interface InvestmentAssetImageChange {
    data object Keep:InvestmentAssetImageChange
    data object Remove:InvestmentAssetImageChange
    data class Replace(val path:InvestmentProductImagePath):InvestmentAssetImageChange
}

data class InvestmentProductImageCandidate(
    val ownerUserId:String,val assetId:String,val path:String,val imageSha256:String,val thumbnailSha256:String,
)
data class InvestmentProductImagePublication(
    val ownerUserId:String,val assetId:String,val revision:String,val previousPath:String?,val candidate:InvestmentProductImageCandidate?,
) {
    constructor(candidate:InvestmentProductImageCandidate,revision:String,previousPath:String?):this(candidate.ownerUserId,candidate.assetId,revision,previousPath,candidate)
    val path:String? get()=candidate?.path
}
