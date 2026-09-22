package vn.com.quyln.mistia.core.auth

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

class GoogleNonce private constructor(val raw: String) {
    val hashed: String = sha256(raw)
    override fun toString() = "GoogleNonce(redacted)"
    companion object {
        fun create(): GoogleNonce = GoogleNonce(Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32).also { SecureRandom().nextBytes(it) }))
        fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }
}
