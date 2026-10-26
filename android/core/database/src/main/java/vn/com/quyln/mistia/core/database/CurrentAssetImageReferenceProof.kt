package vn.com.quyln.mistia.core.database

import vn.com.quyln.mistia.core.model.*

/** Constructed by Room only after checking the current row and its exact outbox under its transaction. */
internal data class CurrentAssetImageReferenceProof(
    val owner:UserId,val assetId:String,val path:String?,val dirty:Boolean,
    val declared:InvestmentProductImagePublication?,val knownLegacyResult:InvestmentProductImagePublication?=null,
)
