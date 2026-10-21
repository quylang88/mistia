package vn.com.quyln.mistia.feature.overview

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import vn.com.quyln.mistia.core.model.*

/** Existing malformed-input fixtures inject controlled entity flows. Never a production read implementation. */
internal fun injectedOverviewReadFixture(owner:UserId,read:(CloudEntity,UserId)->Flow<List<CloudRecord>>):Flow<OverviewFinancialReadSnapshot> =
    combine(OverviewFinancialReadSnapshot.entities.map {read(it,owner)}) {rows ->OverviewFinancialReadSnapshot(owner,rows.flatMap {it})}
