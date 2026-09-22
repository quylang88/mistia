package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class WalletModelsTest {
    @Test
    fun `bank without institution is rejected`() {
        val error = assertThrows(WalletValidationException::class.java) {
            WalletDraft(name = "", kind = WalletKind.BANK, currencyCode = "jpy")
                .toMutation(UserId(OWNER), null, DEVICE, NOW)
        }

        assertEquals(WalletValidationError.BANK_INSTITUTION_REQUIRED, error.reason)
    }

    @Test
    fun `clearing bank details emits explicit nulls`() {
        val existing = walletRecord(
            kind = WalletKind.BANK,
            institutionDisplayName = "MUFG",
            institutionPresetKey = "mufg",
        )
        val mutation = WalletDraft(
            name = "Cash",
            kind = WalletKind.CASH,
            currencyCode = "jpy",
            openingBalanceMinor = 9_007_199_254_740_993L,
        ).toMutation(UserId(OWNER), existing, DEVICE, NOW)

        assertEquals(JsonNull, mutation.record.payload["institution_display_name"])
        assertEquals(JsonNull, mutation.record.payload["institution_preset_key"])
        assertEquals("JPY", mutation.record.payload["currency_code"]?.jsonPrimitive?.content)
        assertEquals(
            9_007_199_254_740_993L,
            mutation.record.payload["opening_balance_minor"]?.jsonPrimitive?.long,
        )
    }

    @Test
    fun `editing preserves identity creation and base version`() {
        val existing = walletRecord(
            id = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            syncVersion = 7,
        )
        val mutation = WalletDraft(
            name = "Travel",
            kind = WalletKind.CASH,
            currencyCode = "JPY",
        ).toMutation(UserId(OWNER), existing, DEVICE, NOW)

        assertEquals("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", mutation.record.id)
        assertEquals(
            CREATED_AT,
            mutation.record.payload["created_at"]?.jsonPrimitive?.content,
        )
        assertEquals(7, mutation.pending.baseVersion)
        assertEquals(NOW, mutation.pending.modifiedAt)
    }

    @Test
    fun `credit card and investment require dedicated flows`() {
        listOf(WalletKind.CREDIT_CARD, WalletKind.INVESTMENT).forEach { kind ->
            val error = assertThrows(WalletValidationException::class.java) {
                WalletDraft(name = "Blocked", kind = kind, currencyCode = "JPY")
                    .toMutation(UserId(OWNER), null, DEVICE, NOW)
            }

            assertEquals(WalletValidationError.DEDICATED_FLOW_REQUIRED, error.reason)
        }
    }

    @Test
    fun `new wallet uses exact iOS kind defaults and canonical identifiers`() {
        val mutation = WalletDraft(
            id = "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
            name = "Tokyo cash",
            kind = WalletKind.CASH,
            currencyCode = "jpy",
        ).toMutation(UserId(OWNER.uppercase()), null, DEVICE.uppercase(), NOW)

        assertEquals("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", mutation.record.id)
        assertEquals(OWNER, mutation.record.ownerUserId)
        assertEquals("mistia.wallet.cash", mutation.record.payload["icon_symbol_name"]?.jsonPrimitive?.content)
        assertEquals("#2DAA9E", mutation.record.payload["icon_color_hex"]?.jsonPrimitive?.content)
        assertEquals(DEVICE, mutation.record.payload["last_modified_by_device_id"]?.jsonPrimitive?.content)
    }

    private fun walletRecord(
        id: String = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
        kind: WalletKind = WalletKind.CASH,
        institutionDisplayName: String? = null,
        institutionPresetKey: String? = null,
        syncVersion: Long = 3,
    ): LedgerWalletRecord {
        val payload = buildJsonObject {
            put("user_id", JsonPrimitive(OWNER))
            put("id", JsonPrimitive(id.lowercase()))
            put("name", JsonPrimitive("Existing"))
            put("kind_raw_value", JsonPrimitive(kind.wireValue))
            put("icon_symbol_name", JsonPrimitive(kind.defaultIcon))
            put("icon_color_hex", JsonPrimitive(kind.defaultColorHex))
            put("currency_code", JsonPrimitive("JPY"))
            put("opening_balance_minor", JsonPrimitive(100L))
            put("institution_display_name", institutionDisplayName?.let(::JsonPrimitive) ?: JsonNull)
            put("institution_preset_key", institutionPresetKey?.let(::JsonPrimitive) ?: JsonNull)
            put("sort_order", JsonPrimitive(2))
            put("is_archived", JsonPrimitive(false))
            put("archived_at", JsonNull)
            put("created_at", JsonPrimitive(CREATED_AT))
            put("updated_at", JsonPrimitive(CREATED_AT))
            put("deleted_at", JsonNull)
            put("sync_version", JsonPrimitive(syncVersion))
            put("last_modified_by_device_id", JsonNull)
            put("system_purpose_raw_value", JsonNull)
            put("investment_linked_wallet_id", JsonNull)
        }
        return LedgerWalletRecord.fromCloudRecord(
            CloudRecord(
                entity = CloudEntity.LEDGER_WALLET.table,
                id = id,
                ownerUserId = OWNER,
                payload = payload,
                updatedAt = CREATED_AT,
                deletedAt = null,
                syncVersion = syncVersion,
            ),
        )
    }

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val DEVICE = "22222222-2222-2222-2222-222222222222"
        const val CREATED_AT = "2026-01-01T00:00:00.000Z"
        const val NOW = "2026-09-22T10:00:00.000Z"
    }
}
