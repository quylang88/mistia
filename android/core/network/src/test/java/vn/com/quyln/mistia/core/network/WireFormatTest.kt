package vn.com.quyln.mistia.core.network

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import org.junit.Assert.assertTrue
import org.junit.Test

class WireFormatTest {
    @Serializable
    private data class PatchPayload(val note: String?)

    @Test
    fun clearedOptionalIsEncodedAsExplicitJsonNull() {
        val encoded = MistiaWireFormat.json.encodeToString(PatchPayload(note = null))
        assertTrue(encoded.contains("\"note\":null"))
    }
}
