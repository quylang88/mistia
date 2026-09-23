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

enum class CreditCardNetwork(val wireValue: String) {
    VISA("visa"),
    MASTERCARD("mastercard"),
    JCB("jcb"),
    AMERICAN_EXPRESS("americanExpress"),
    UNION_PAY("unionPay"),
    OTHER("other"),
    ;

    companion object {
        fun fromWireValue(value: String): CreditCardNetwork? = entries.firstOrNull { it.wireValue == value }
    }
}

data class CreditCardProfileRecord(
    val id: String,
    val ownerUserId: String,
    val issuerName: String,
    val networkWireValue: String,
    val last4: String,
    val creditLimitMinor: Long,
    val statementClosingDay: Int,
    val paymentDueDay: Int,
    val notes: String?,
    val walletId: String?,
    val paymentSourceWalletId: String?,
    val autoPayEnabled: Boolean,
    val createdAt: String,
    val updatedAt: String,
    val deletedAt: String?,
    val syncVersion: Long,
    val lastModifiedByDeviceId: String?,
) {
    val network: CreditCardNetwork?
        get() = CreditCardNetwork.fromWireValue(networkWireValue)

    fun toPayload(): JsonObject = buildJsonObject {
        put("user_id", JsonPrimitive(ownerUserId))
        put("id", JsonPrimitive(id))
        put("issuer_name", JsonPrimitive(issuerName))
        put("network_raw_value", JsonPrimitive(networkWireValue))
        put("last4", JsonPrimitive(last4))
        put("credit_limit_minor", JsonPrimitive(creditLimitMinor))
        put("statement_closing_day", JsonPrimitive(statementClosingDay))
        put("payment_due_day", JsonPrimitive(paymentDueDay))
        putNullableCardString("notes", notes)
        putNullableCardString("wallet_id", walletId)
        putNullableCardString("payment_source_wallet_id", paymentSourceWalletId)
        put("auto_pay_enabled", JsonPrimitive(autoPayEnabled))
        put("created_at", JsonPrimitive(createdAt))
        put("updated_at", JsonPrimitive(updatedAt))
        putNullableCardString("deleted_at", deletedAt)
        put("sync_version", JsonPrimitive(syncVersion))
        putNullableCardString("last_modified_by_device_id", lastModifiedByDeviceId)
    }

    fun toCloudRecord(): CloudRecord = CloudRecord(
        entity = CloudEntity.CREDIT_CARD_PROFILE.table,
        id = id,
        ownerUserId = ownerUserId,
        payload = toPayload(),
        updatedAt = updatedAt,
        deletedAt = deletedAt,
        syncVersion = syncVersion,
    )

    companion object {
        fun fromCloudRecord(record: CloudRecord): CreditCardProfileRecord {
            require(record.entity == CloudEntity.CREDIT_CARD_PROFILE.table)
            val payload = record.payload
            return CreditCardProfileRecord(
                id = cardUuid(payload.cardString("id") ?: record.id),
                ownerUserId = cardUuid(payload.cardString("user_id") ?: record.ownerUserId),
                issuerName = payload.cardString("issuer_name").orEmpty(),
                networkWireValue = payload.cardString("network_raw_value").orEmpty(),
                last4 = payload.cardString("last4").orEmpty(),
                creditLimitMinor = payload.cardLong("credit_limit_minor"),
                statementClosingDay = payload.cardInt("statement_closing_day"),
                paymentDueDay = payload.cardInt("payment_due_day"),
                notes = payload.cardString("notes"),
                walletId = payload.cardString("wallet_id")?.let(::cardUuid),
                paymentSourceWalletId = payload.cardString("payment_source_wallet_id")?.let(::cardUuid),
                autoPayEnabled = payload.cardBoolean("auto_pay_enabled", default = true),
                createdAt = payload.cardString("created_at") ?: record.updatedAt.orEmpty(),
                updatedAt = payload.cardString("updated_at") ?: record.updatedAt.orEmpty(),
                deletedAt = payload.cardString("deleted_at") ?: record.deletedAt,
                syncVersion = payload.cardLongOrNull("sync_version") ?: record.syncVersion,
                lastModifiedByDeviceId = payload.cardString("last_modified_by_device_id"),
            )
        }
    }
}

data class CreditCardDraft(
    val walletId: String? = null,
    val profileId: String? = null,
    val name: String,
    val issuerName: String = "",
    val network: CreditCardNetwork = CreditCardNetwork.VISA,
    val last4: String = "",
    val creditLimitMinor: Long,
    val statementClosingDay: Int = 10,
    val paymentDueDay: Int = 26,
    val notes: String? = null,
    val paymentSourceWalletId: String? = null,
    val currencyCode: String = "JPY",
    val iconSymbolName: String? = null,
    val iconColorHex: String? = null,
    val sortOrder: Int? = null,
) {
    fun toMutation(
        ownerUserId: UserId,
        existingWallet: LedgerWalletRecord?,
        existingProfile: CreditCardProfileRecord?,
        paymentSourceWallet: LedgerWalletRecord?,
        deviceId: String,
        now: String,
    ): CreditCardAggregateMutation {
        val owner = cardUuid(ownerUserId.value)
        val device = cardUuid(deviceId)
        val timestamp = cardUtc(now)
        if (existingWallet != null && existingWallet.ownerUserId != owner) fail(CreditCardValidationError.OWNER_MISMATCH)
        if (existingProfile != null && existingProfile.ownerUserId != owner) fail(CreditCardValidationError.OWNER_MISMATCH)
        if (existingWallet != null && existingWallet.kind != WalletKind.CREDIT_CARD) {
            fail(CreditCardValidationError.WALLET_KIND_MISMATCH)
        }
        if (existingProfile?.walletId != null && existingProfile.walletId != existingWallet?.id) {
            fail(CreditCardValidationError.WALLET_PROFILE_MISMATCH)
        }

        val normalizedName = name.trim()
        if (normalizedName.isEmpty()) fail(CreditCardValidationError.NAME_REQUIRED)
        val normalizedLast4 = last4.trim()
        if (!normalizedLast4.matches(Regex("^[0-9]{0,4}$"))) fail(CreditCardValidationError.INVALID_LAST4)
        if (creditLimitMinor < 0) fail(CreditCardValidationError.INVALID_CREDIT_LIMIT)
        if (statementClosingDay !in 1..30 || paymentDueDay !in 2..31 || statementClosingDay >= paymentDueDay) {
            fail(CreditCardValidationError.INVALID_BILLING_DAYS)
        }
        val currency = currencyCode.trim().uppercase(Locale.ROOT)
        if (!currency.matches(Regex("^[A-Z]{3}$"))) fail(CreditCardValidationError.INVALID_CURRENCY)
        val color = (iconColorHex.cardOptional() ?: WalletKind.CREDIT_CARD.defaultColorHex).uppercase(Locale.ROOT)
        if (!color.matches(Regex("^#[0-9A-F]{6}$"))) fail(CreditCardValidationError.INVALID_COLOR)

        val canonicalWalletId = cardUuid(existingWallet?.id ?: walletId ?: UUID.randomUUID().toString())
        val canonicalProfileId = cardUuid(existingProfile?.id ?: profileId ?: UUID.randomUUID().toString())
        val paymentSourceId = paymentSourceWalletId?.let(::cardUuid)
        if (paymentSourceId != null) {
            val source = paymentSourceWallet ?: fail(CreditCardValidationError.INVALID_PAYMENT_SOURCE)
            if (source.id != paymentSourceId || source.ownerUserId != owner || source.id == canonicalWalletId ||
                source.kind == null || source.kind == WalletKind.CREDIT_CARD || source.isArchived || source.deletedAt != null
            ) {
                fail(CreditCardValidationError.INVALID_PAYMENT_SOURCE)
            }
        } else if (paymentSourceWallet != null) {
            fail(CreditCardValidationError.INVALID_PAYMENT_SOURCE)
        }

        val wallet = LedgerWalletRecord(
            id = canonicalWalletId,
            ownerUserId = owner,
            name = normalizedName,
            kindWireValue = WalletKind.CREDIT_CARD.wireValue,
            iconSymbolName = iconSymbolName.cardOptional() ?: existingWallet?.iconSymbolName
                ?: WalletKind.CREDIT_CARD.defaultIcon,
            iconColorHex = color,
            currencyCode = currency,
            openingBalanceMinor = existingWallet?.openingBalanceMinor ?: 0,
            institutionDisplayName = null,
            institutionPresetKey = null,
            sortOrder = sortOrder ?: existingWallet?.sortOrder ?: 0,
            isArchived = existingWallet?.isArchived ?: false,
            archivedAt = existingWallet?.archivedAt,
            createdAt = existingWallet?.createdAt ?: timestamp,
            updatedAt = timestamp,
            deletedAt = null,
            syncVersion = existingWallet?.syncVersion ?: 0,
            lastModifiedByDeviceId = device,
            systemPurposeRawValue = existingWallet?.systemPurposeRawValue,
            investmentLinkedWalletId = existingWallet?.investmentLinkedWalletId,
        )
        val profile = CreditCardProfileRecord(
            id = canonicalProfileId,
            ownerUserId = owner,
            issuerName = issuerName.trim(),
            networkWireValue = network.wireValue,
            last4 = normalizedLast4,
            creditLimitMinor = creditLimitMinor,
            statementClosingDay = statementClosingDay,
            paymentDueDay = paymentDueDay,
            notes = notes.cardOptional(),
            walletId = canonicalWalletId,
            paymentSourceWalletId = paymentSourceId,
            autoPayEnabled = existingProfile?.autoPayEnabled ?: true,
            createdAt = existingProfile?.createdAt ?: timestamp,
            updatedAt = timestamp,
            deletedAt = null,
            syncVersion = existingProfile?.syncVersion ?: 0,
            lastModifiedByDeviceId = device,
        )
        val walletCloud = wallet.toCloudRecord()
        val profileCloud = profile.toCloudRecord()
        return CreditCardAggregateMutation(
            wallet = CreditCardWalletMutation(
                wallet,
                PendingMutation(
                    CloudEntity.LEDGER_WALLET,
                    wallet.id,
                    owner,
                    MutationKind.UPSERT,
                    walletCloud.payload,
                    timestamp,
                    wallet.syncVersion,
                    device,
                ),
            ),
            profile = CreditCardProfileMutation(
                profile,
                PendingMutation(
                    CloudEntity.CREDIT_CARD_PROFILE,
                    profile.id,
                    owner,
                    MutationKind.UPSERT,
                    profileCloud.payload,
                    timestamp,
                    profile.syncVersion,
                    device,
                ),
            ),
        )
    }
}

data class CreditCardWalletMutation(val record: LedgerWalletRecord, val pending: PendingMutation)
data class CreditCardProfileMutation(val record: CreditCardProfileRecord, val pending: PendingMutation)
data class CreditCardAggregateMutation(
    val wallet: CreditCardWalletMutation,
    val profile: CreditCardProfileMutation,
)

data class CreditCardAccount(
    val wallet: LedgerWalletRecord,
    val profile: CreditCardProfileRecord,
)

enum class CreditCardValidationError {
    NAME_REQUIRED,
    INVALID_LAST4,
    INVALID_CREDIT_LIMIT,
    INVALID_BILLING_DAYS,
    INVALID_CURRENCY,
    INVALID_COLOR,
    INVALID_PAYMENT_SOURCE,
    OWNER_MISMATCH,
    WALLET_KIND_MISMATCH,
    WALLET_PROFILE_MISMATCH,
    PROFILE_NOT_FOUND,
}

class CreditCardValidationException(val reason: CreditCardValidationError) : IllegalArgumentException(reason.name)

private fun fail(reason: CreditCardValidationError): Nothing = throw CreditCardValidationException(reason)
private fun cardUuid(value: String): String = UUID.fromString(value.trim()).toString()
private fun cardUtc(value: String): String = value.also { require(Instant.parse(it).toString().endsWith("Z")) }
private fun String?.cardOptional(): String? = this?.trim()?.takeIf(String::isNotEmpty)
private fun JsonObject.cardString(key: String): String? =
    (get(key) as? JsonPrimitive)?.contentOrNull?.takeIf(String::isNotBlank)
private fun JsonObject.cardLong(key: String): Long = (get(key) as? JsonPrimitive)?.longOrNull ?: 0L
private fun JsonObject.cardLongOrNull(key: String): Long? = (get(key) as? JsonPrimitive)?.longOrNull
private fun JsonObject.cardInt(key: String): Int = (get(key) as? JsonPrimitive)?.intOrNull ?: 0
private fun JsonObject.cardBoolean(key: String, default: Boolean): Boolean =
    (get(key) as? JsonPrimitive)?.booleanOrNull ?: default
private fun kotlinx.serialization.json.JsonObjectBuilder.putNullableCardString(key: String, value: String?) {
    put(key, value?.let(::JsonPrimitive) ?: JsonNull)
}
