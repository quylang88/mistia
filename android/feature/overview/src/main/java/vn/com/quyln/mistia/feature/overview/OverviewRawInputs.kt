package vn.com.quyln.mistia.feature.overview

import kotlinx.serialization.json.JsonObject
import vn.com.quyln.mistia.core.model.*

internal fun overviewRawUuid(value:String)=financeRawUuid(value)
internal fun JsonObject.overviewRawString(key:String)=financeRawString(key)
internal fun JsonObject.overviewRawLong(key:String)=financeRawLong(key)
internal fun JsonObject.overviewRawArchived()=financeRawArchived()
internal fun CloudRecord.overviewRawDeleted()=financeRawDeleted()
internal fun CloudRecord.overviewRawIdentity(owner:UserId,expected:CloudEntity)=financeRawIdentity(owner,expected)
internal typealias OverviewRawReference = FinanceRawReference
internal fun JsonObject.overviewRawReference(key:String)=financeRawReference(key)
