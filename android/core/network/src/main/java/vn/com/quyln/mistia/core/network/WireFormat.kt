package vn.com.quyln.mistia.core.network

import kotlinx.serialization.json.Json

/** Shared wire settings. Explicit nulls are required so clearing an optional survives sync. */
object MistiaWireFormat {
    val json: Json = Json {
        ignoreUnknownKeys = true
        explicitNulls = true
        encodeDefaults = true
    }
}
