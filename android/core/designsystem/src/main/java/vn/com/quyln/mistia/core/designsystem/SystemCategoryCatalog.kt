package vn.com.quyln.mistia.core.designsystem

import android.content.Context
import vn.com.quyln.mistia.core.model.SystemCategoryCatalog

/** Cache immutable registry data only, never an Activity or account-specific records. */
fun systemCategoryCatalog(context:Context):SystemCategoryCatalog = SystemCategoryCatalogCache.load(context)

private object SystemCategoryCatalogCache {
    @Volatile private var cached:SystemCategoryCatalog?=null
    fun load(context:Context):SystemCategoryCatalog=cached ?: synchronized(this) {
        cached ?: context.applicationContext.assets.open("MistiaSystemCategories.json").bufferedReader().use {SystemCategoryCatalog.parse(it.readText())}.also {cached=it}
    }
}
