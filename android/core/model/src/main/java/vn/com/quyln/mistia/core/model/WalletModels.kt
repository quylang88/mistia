package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull

enum class WalletKind(
    val wireValue: String,
    val defaultIcon: String,
    val defaultColorHex: String,
) {
    CASH("cash", "mistia.wallet.cash", "#2DAA9E"),
    PAY_PAY("payPay", "mistia.wallet.paypay", "#F26A5A"),
    BANK("bank", "mistia.wallet.bank", "#5B7BFF"),
    CREDIT_CARD("creditCard", "mistia.wallet.credit_card", "#7C85A3"),
    E_WALLET("eWallet", "mistia.wallet.e_wallet", "#F26A5A"),
    PREPAID("prepaid", "mistia.wallet.prepaid", "#FFB347"),
    INVESTMENT("investment", "mistia.wallet.investment", "#9A67FF"),
    CRYPTO("crypto", "mistia.wallet.crypto", "#F59B3F"),
    OTHER("other", "mistia.wallet.other", "#8A8A8E"),
    ;

    companion object {
        fun fromWireValue(value: String): WalletKind? = entries.firstOrNull { it.wireValue == value }
    }
}

data class LedgerWalletRecord(
    val id: String,
    val ownerUserId: String,
    val name: String,
    val kindWireValue: String,
    val iconSymbolName: String,
    val iconColorHex: String,
    val currencyCode: String,
    val openingBalanceMinor: Long,
    val institutionDisplayName: String?,
    val institutionPresetKey: String?,
    val sortOrder: Int,
    val isArchived: Boolean,
    val archivedAt: String?,
    val createdAt: String,
    val updatedAt: String,
    val deletedAt: String?,
    val syncVersion: Long,
    val lastModifiedByDeviceId: String?,
    val systemPurposeRawValue: String?,
    val investmentLinkedWalletId: String?,
) {
    val kind: WalletKind?
        get() = WalletKind.fromWireValue(kindWireValue)

    fun toCloudRecord(): CloudRecord = CloudRecord(
        entity = CloudEntity.LEDGER_WALLET.table,
        id = id,
        ownerUserId = ownerUserId,
        payload = toPayload(),
        updatedAt = updatedAt,
        deletedAt = deletedAt,
        syncVersion = syncVersion,
    )

    fun toArchiveMutation(deviceId: String, now: String): WalletMutation {
        if (kind == null) throw WalletValidationException(WalletValidationError.UNKNOWN_KIND)
        if (kind == WalletKind.CREDIT_CARD || kind == WalletKind.INVESTMENT) {
            throw WalletValidationException(WalletValidationError.DEDICATED_FLOW_REQUIRED)
        }
        requireUtcInstant(now)
        val archived = copy(
            isArchived = true,
            archivedAt = now,
            updatedAt = now,
            deletedAt = null,
            lastModifiedByDeviceId = canonicalUuid(deviceId),
        )
        val record = archived.toCloudRecord()
        return WalletMutation(
            record = record,
            pending = PendingMutation(
                entity = CloudEntity.LEDGER_WALLET,
                recordId = id,
                subjectUserId = ownerUserId,
                kind = MutationKind.UPSERT,
                payload = record.payload,
                modifiedAt = now,
                baseVersion = syncVersion,
                deviceId = archived.lastModifiedByDeviceId.orEmpty(),
            ),
        )
    }

    fun toPayload(): JsonObject = buildJsonObject {
        put("user_id", JsonPrimitive(ownerUserId))
        put("id", JsonPrimitive(id))
        put("name", JsonPrimitive(name))
        put("kind_raw_value", JsonPrimitive(kindWireValue))
        put("icon_symbol_name", JsonPrimitive(iconSymbolName))
        put("icon_color_hex", JsonPrimitive(iconColorHex))
        put("currency_code", JsonPrimitive(currencyCode))
        put("opening_balance_minor", JsonPrimitive(openingBalanceMinor))
        putNullableString("institution_display_name", institutionDisplayName)
        putNullableString("institution_preset_key", institutionPresetKey)
        put("sort_order", JsonPrimitive(sortOrder))
        put("is_archived", JsonPrimitive(isArchived))
        putNullableString("archived_at", archivedAt)
        put("created_at", JsonPrimitive(createdAt))
        put("updated_at", JsonPrimitive(updatedAt))
        putNullableString("deleted_at", deletedAt)
        put("sync_version", JsonPrimitive(syncVersion))
        putNullableString("last_modified_by_device_id", lastModifiedByDeviceId)
        putNullableString("system_purpose_raw_value", systemPurposeRawValue)
        putNullableString("investment_linked_wallet_id", investmentLinkedWalletId)
    }

    companion object {
        fun fromCloudRecord(record: CloudRecord): LedgerWalletRecord {
            require(record.entity == CloudEntity.LEDGER_WALLET.table) {
                "Expected ${CloudEntity.LEDGER_WALLET.table}, got ${record.entity}"
            }
            val payload = record.payload
            val id = canonicalUuid(payload.string("id") ?: record.id)
            val owner = canonicalUuid(payload.string("user_id") ?: record.ownerUserId)
            return LedgerWalletRecord(
                id = id,
                ownerUserId = owner,
                name = payload.string("name").orEmpty(),
                kindWireValue = payload.string("kind_raw_value").orEmpty(),
                iconSymbolName = payload.string("icon_symbol_name").orEmpty(),
                iconColorHex = payload.string("icon_color_hex").orEmpty(),
                currencyCode = payload.string("currency_code").orEmpty().uppercase(Locale.ROOT),
                openingBalanceMinor = payload.long("opening_balance_minor"),
                institutionDisplayName = payload.string("institution_display_name"),
                institutionPresetKey = payload.string("institution_preset_key"),
                sortOrder = payload.int("sort_order"),
                isArchived = payload.boolean("is_archived"),
                archivedAt = payload.string("archived_at"),
                createdAt = payload.string("created_at") ?: record.updatedAt.orEmpty(),
                updatedAt = payload.string("updated_at") ?: record.updatedAt.orEmpty(),
                deletedAt = payload.string("deleted_at") ?: record.deletedAt,
                syncVersion = payload.longOrNull("sync_version") ?: record.syncVersion,
                lastModifiedByDeviceId = payload.string("last_modified_by_device_id"),
                systemPurposeRawValue = payload.string("system_purpose_raw_value"),
                investmentLinkedWalletId = payload.string("investment_linked_wallet_id"),
            )
        }
    }
}

data class WalletDraft(
    val id: String? = null,
    val name: String,
    val kind: WalletKind,
    val iconSymbolName: String? = null,
    val iconColorHex: String? = null,
    val currencyCode: String,
    val openingBalanceMinor: Long = 0,
    val institutionDisplayName: String? = null,
    val institutionPresetKey: String? = null,
    val sortOrder: Int? = null,
) {
    fun toMutation(
        ownerUserId: UserId,
        existing: LedgerWalletRecord?,
        deviceId: String,
        now: String,
    ): WalletMutation {
        val canonicalOwnerId = canonicalUuid(ownerUserId.value)
        val canonicalDeviceId = canonicalUuid(deviceId)
        requireUtcInstant(now)
        if (existing?.kind == null && existing != null) {
            throw WalletValidationException(WalletValidationError.UNKNOWN_KIND)
        }
        if (kind == WalletKind.CREDIT_CARD || kind == WalletKind.INVESTMENT) {
            throw WalletValidationException(WalletValidationError.DEDICATED_FLOW_REQUIRED)
        }

        val normalizedCurrency = currencyCode.trim().uppercase(Locale.ROOT)
        if (!normalizedCurrency.matches(Regex("^[A-Z]{3}$"))) {
            throw WalletValidationException(WalletValidationError.INVALID_CURRENCY)
        }
        val normalizedInstitution = institutionDisplayName.normalizedOptional()
        if (kind == WalletKind.BANK && normalizedInstitution == null) {
            throw WalletValidationException(WalletValidationError.BANK_INSTITUTION_REQUIRED)
        }
        val normalizedName = name.trim().ifEmpty {
            if (kind == WalletKind.BANK) normalizedInstitution.orEmpty() else ""
        }
        if (normalizedName.isEmpty()) {
            throw WalletValidationException(WalletValidationError.NAME_REQUIRED)
        }

        val canonicalId = canonicalUuid(existing?.id ?: id ?: UUID.randomUUID().toString())
        if (existing != null && existing.ownerUserId != canonicalOwnerId) {
            throw WalletValidationException(WalletValidationError.OWNER_MISMATCH)
        }
        val createdAt = existing?.createdAt ?: now
        requireUtcInstant(createdAt)
        val baseVersion = existing?.syncVersion ?: 0L
        val normalizedColor = (iconColorHex.normalizedOptional() ?: kind.defaultColorHex).uppercase(Locale.ROOT)
        if (!normalizedColor.matches(Regex("^#[0-9A-F]{6}$"))) {
            throw WalletValidationException(WalletValidationError.INVALID_COLOR)
        }

        val wallet = LedgerWalletRecord(
            id = canonicalId,
            ownerUserId = canonicalOwnerId,
            name = normalizedName,
            kindWireValue = kind.wireValue,
            iconSymbolName = iconSymbolName.normalizedOptional() ?: kind.defaultIcon,
            iconColorHex = normalizedColor,
            currencyCode = normalizedCurrency,
            openingBalanceMinor = openingBalanceMinor,
            institutionDisplayName = if (kind == WalletKind.BANK) normalizedInstitution else null,
            institutionPresetKey = if (kind == WalletKind.BANK) institutionPresetKey.normalizedOptional() else null,
            sortOrder = sortOrder ?: existing?.sortOrder ?: 0,
            isArchived = existing?.isArchived ?: false,
            archivedAt = existing?.archivedAt,
            createdAt = createdAt,
            updatedAt = now,
            deletedAt = null,
            syncVersion = baseVersion,
            lastModifiedByDeviceId = canonicalDeviceId,
            systemPurposeRawValue = existing?.systemPurposeRawValue,
            investmentLinkedWalletId = existing?.investmentLinkedWalletId,
        )
        val record = wallet.toCloudRecord()
        return WalletMutation(
            record = record,
            pending = PendingMutation(
                entity = CloudEntity.LEDGER_WALLET,
                recordId = canonicalId,
                subjectUserId = canonicalOwnerId,
                kind = MutationKind.UPSERT,
                payload = record.payload,
                modifiedAt = now,
                baseVersion = baseVersion,
                deviceId = canonicalDeviceId,
            ),
        )
    }
}

data class WalletMutation(
    val record: CloudRecord,
    val pending: PendingMutation,
)

enum class WalletValidationError {
    NAME_REQUIRED,
    BANK_INSTITUTION_REQUIRED,
    INVALID_CURRENCY,
    INVALID_COLOR,
    DEDICATED_FLOW_REQUIRED,
    UNKNOWN_KIND,
    OWNER_MISMATCH,
}

class WalletValidationException(val reason: WalletValidationError) : IllegalArgumentException(reason.name)

private fun canonicalUuid(value: String): String = UUID.fromString(value.trim()).toString()

private fun requireUtcInstant(value: String) {
    require(Instant.parse(value).toString().endsWith("Z")) { "Timestamp must be UTC ISO-8601" }
}

private fun String?.normalizedOptional(): String? = this?.trim()?.takeIf(String::isNotEmpty)

private fun JsonObject.string(key: String): String? =
    (get(key) as? JsonPrimitive)?.contentOrNull?.takeIf(String::isNotBlank)

private fun JsonObject.long(key: String): Long = (get(key) as? JsonPrimitive)?.longOrNull ?: 0L

private fun JsonObject.longOrNull(key: String): Long? = (get(key) as? JsonPrimitive)?.longOrNull

private fun JsonObject.int(key: String): Int = (get(key) as? JsonPrimitive)?.intOrNull ?: 0

private fun JsonObject.boolean(key: String): Boolean = (get(key) as? JsonPrimitive)?.booleanOrNull ?: false

private fun kotlinx.serialization.json.JsonObjectBuilder.putNullableString(key: String, value: String?) {
    put(key, value?.let(::JsonPrimitive) ?: JsonNull)
}
