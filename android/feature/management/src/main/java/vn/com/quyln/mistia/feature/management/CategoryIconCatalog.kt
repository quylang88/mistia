package vn.com.quyln.mistia.feature.management

import vn.com.quyln.mistia.core.model.TransactionCategoryKind

internal typealias CategoryIconOption = vn.com.quyln.mistia.core.designsystem.CategoryIconOption
internal typealias CategoryIconCatalog = vn.com.quyln.mistia.core.designsystem.CategoryIconCatalog
internal typealias CategoryIconFamily = vn.com.quyln.mistia.core.designsystem.CategoryIconFamily
internal fun categoryIconFamily(fallbackIcon: String?, kind: TransactionCategoryKind?): CategoryIconFamily =
    vn.com.quyln.mistia.core.designsystem.categoryIconFamily(fallbackIcon, kind)
