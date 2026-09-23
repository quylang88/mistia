package vn.com.quyln.mistia.feature.management

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.CurrencyBitcoin
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.HealthAndSafety
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.Savings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Currency
import java.util.Locale
import kotlinx.coroutines.launch
import vn.com.quyln.mistia.core.designsystem.MistiaGlassCard
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.WalletDraft
import vn.com.quyln.mistia.core.model.WalletKind

data class WalletEditorState(
    val id: String?,
    val name: String,
    val kind: WalletKind,
    val iconSymbolName: String,
    val iconColorHex: String,
    val iconWasCustomized: Boolean,
    val currencyCode: String,
    val openingBalanceText: String,
    val originalOpeningBalanceMinor: Long?,
    val institutionDisplayName: String,
    val institutionPresetKey: String?,
    val sortOrder: Int,
) {
    fun selectKind(selected: WalletKind): WalletEditorState = copy(
        kind = selected,
        iconSymbolName = if (iconWasCustomized) iconSymbolName else selected.defaultIcon,
        iconColorHex = if (iconWasCustomized) iconColorHex else selected.defaultColorHex,
        institutionDisplayName = if (selected == WalletKind.BANK) institutionDisplayName else "",
        institutionPresetKey = if (selected == WalletKind.BANK) institutionPresetKey else null,
    )

    fun customizeIcon(symbolName: String, colorHex: String): WalletEditorState = copy(
        iconSymbolName = symbolName,
        iconColorHex = colorHex,
        iconWasCustomized = true,
    )

    fun toDraft(fallbackName: String): WalletEditorDraftResult {
        val institution = institutionDisplayName.trim()
        if (kind == WalletKind.BANK && institution.isEmpty()) {
            return WalletEditorDraftResult(validation = WalletEditorValidation.BANK_INSTITUTION_REQUIRED)
        }
        val normalizedName = name.trim().ifEmpty {
            if (kind == WalletKind.BANK) institution else fallbackName.trim()
        }
        if (normalizedName.isEmpty()) {
            return WalletEditorDraftResult(validation = WalletEditorValidation.NAME_REQUIRED)
        }
        val openingBalance = originalOpeningBalanceMinor
            ?: parseMinorUnits(openingBalanceText, currencyCode)
            ?: return WalletEditorDraftResult(validation = WalletEditorValidation.INVALID_OPENING_BALANCE)
        return WalletEditorDraftResult(
            draft = WalletDraft(
                id = id,
                name = normalizedName,
                kind = kind,
                iconSymbolName = iconSymbolName,
                iconColorHex = iconColorHex,
                currencyCode = currencyCode,
                openingBalanceMinor = openingBalance,
                institutionDisplayName = institution.takeIf(String::isNotEmpty),
                institutionPresetKey = institutionPresetKey,
                sortOrder = sortOrder,
            )
        )
    }

    companion object {
        val supportedKinds = listOf(
            WalletKind.CASH,
            WalletKind.PAY_PAY,
            WalletKind.BANK,
            WalletKind.E_WALLET,
            WalletKind.PREPAID,
            WalletKind.CRYPTO,
            WalletKind.OTHER,
        )

        fun new(sortOrder: Int = 0): WalletEditorState = WalletEditorState(
            id = null,
            name = "",
            kind = WalletKind.CASH,
            iconSymbolName = WalletKind.CASH.defaultIcon,
            iconColorHex = WalletKind.CASH.defaultColorHex,
            iconWasCustomized = false,
            currencyCode = "JPY",
            openingBalanceText = "",
            originalOpeningBalanceMinor = null,
            institutionDisplayName = "",
            institutionPresetKey = null,
            sortOrder = sortOrder,
        )

        fun edit(wallet: LedgerWalletRecord): WalletEditorState {
            val kind = requireNotNull(wallet.kind) { "Unknown wallet kind cannot be edited" }
            require(kind in supportedKinds) { "Wallet kind requires a dedicated editor" }
            return WalletEditorState(
                id = wallet.id,
                name = wallet.name,
                kind = kind,
                iconSymbolName = wallet.iconSymbolName,
                iconColorHex = wallet.iconColorHex,
                iconWasCustomized = wallet.iconSymbolName != kind.defaultIcon ||
                    !wallet.iconColorHex.equals(kind.defaultColorHex, ignoreCase = true),
                currencyCode = wallet.currencyCode,
                openingBalanceText = formatMinorInput(wallet.openingBalanceMinor, wallet.currencyCode),
                originalOpeningBalanceMinor = wallet.openingBalanceMinor,
                institutionDisplayName = wallet.institutionDisplayName.orEmpty(),
                institutionPresetKey = wallet.institutionPresetKey,
                sortOrder = wallet.sortOrder,
            )
        }

        val Saver: Saver<WalletEditorState, Any> = listSaver(
            save = {
                listOf(
                    it.id.orEmpty(),
                    it.name,
                    it.kind.wireValue,
                    it.iconSymbolName,
                    it.iconColorHex,
                    it.iconWasCustomized,
                    it.currencyCode,
                    it.openingBalanceText,
                    it.originalOpeningBalanceMinor?.toString().orEmpty(),
                    it.institutionDisplayName,
                    it.institutionPresetKey.orEmpty(),
                    it.sortOrder,
                )
            },
            restore = { values ->
                WalletEditorState(
                    id = (values[0] as String).takeIf(String::isNotEmpty),
                    name = values[1] as String,
                    kind = WalletKind.fromWireValue(values[2] as String) ?: WalletKind.CASH,
                    iconSymbolName = values[3] as String,
                    iconColorHex = values[4] as String,
                    iconWasCustomized = values[5] as Boolean,
                    currencyCode = values[6] as String,
                    openingBalanceText = values[7] as String,
                    originalOpeningBalanceMinor = (values[8] as String).toLongOrNull(),
                    institutionDisplayName = values[9] as String,
                    institutionPresetKey = (values[10] as String).takeIf(String::isNotEmpty),
                    sortOrder = values[11] as Int,
                )
            },
        )
    }
}

data class WalletEditorDraftResult(
    val draft: WalletDraft? = null,
    val validation: WalletEditorValidation? = null,
)

enum class WalletEditorValidation {
    NAME_REQUIRED,
    BANK_INSTITUTION_REQUIRED,
    INVALID_OPENING_BALANCE,
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun WalletEditorSheet(
    wallet: LedgerWalletRecord?,
    nextSortOrder: Int,
    onDismiss: () -> Unit,
    onSave: suspend (WalletDraft) -> Result<LedgerWalletRecord>,
    onArchive: suspend () -> Result<Unit>,
) {
    var state by rememberSaveable(wallet?.id, stateSaver = WalletEditorState.Saver) {
        mutableStateOf(wallet?.let(WalletEditorState::edit) ?: WalletEditorState.new(nextSortOrder))
    }
    var validation by remember { mutableStateOf<WalletEditorValidation?>(null) }
    var saveFailed by remember { mutableStateOf(false) }
    var archiveConfirmation by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val fallbackName = walletKindTitle(state.kind)

    ModalBottomSheet(onDismissRequest = { if (!isSaving) onDismiss() }) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onDismiss, enabled = !isSaving) {
                    Text(stringResource(R.string.common_cancel))
                }
                Text(
                    text = stringResource(
                        if (wallet == null) R.string.management_wallet_editor_new_title
                        else R.string.management_wallet_editor_edit_title
                    ),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                )
                Button(
                    enabled = !isSaving,
                    onClick = {
                        val result = state.toDraft(fallbackName)
                        validation = result.validation
                        saveFailed = false
                        val draft = result.draft ?: return@Button
                        isSaving = true
                        scope.launch {
                            onSave(draft).fold(
                                onSuccess = { onDismiss() },
                                onFailure = {
                                    isSaving = false
                                    saveFailed = true
                                },
                            )
                        }
                    },
                ) {
                    Text(stringResource(R.string.common_save))
                }
            }

            MistiaGlassCard { padding ->
                Column(Modifier.padding(padding), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        stringResource(R.string.management_management_identity),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        WalletIcon(
                            state.iconSymbolName,
                            state.kind,
                            state.iconColorHex,
                            Modifier.size(48.dp),
                        )
                        Column(Modifier.padding(start = 12.dp)) {
                            Text(stringResource(R.string.management_management_icon))
                            Text(
                                stringResource(R.string.management_management_tap_to_change_the_wallet_icon),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        WALLET_ICON_SYMBOLS.forEach { symbolName ->
                            val selected = state.iconSymbolName == symbolName
                            WalletIcon(
                                symbolName = symbolName,
                                kind = state.kind,
                                colorHex = state.iconColorHex,
                                modifier = Modifier
                                    .size(42.dp)
                                    .then(
                                        if (selected) {
                                            Modifier.border(
                                                width = 2.dp,
                                                color = MaterialTheme.colorScheme.primary,
                                                shape = CircleShape,
                                            )
                                        } else {
                                            Modifier
                                        }
                                    )
                                    .clickable {
                                        state = state.customizeIcon(symbolName, state.iconColorHex)
                                    },
                            )
                        }
                    }
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        WALLET_COLORS.forEach { color ->
                            Box(
                                modifier = Modifier
                                    .padding(vertical = 4.dp)
                                    .size(if (state.iconColorHex.equals(color, true)) 32.dp else 28.dp)
                                    .clip(CircleShape)
                                    .background(colorFromHex(color))
                                    .clickable {
                                        state = state.customizeIcon(state.iconSymbolName, color)
                                    }
                            )
                        }
                    }
                }
            }

            MistiaGlassCard { padding ->
                Column(Modifier.padding(padding), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        stringResource(R.string.management_management_basic_details),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    OutlinedTextField(
                        value = state.name,
                        onValueChange = { state = state.copy(name = it) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.management_management_wallet_name)) },
                        singleLine = true,
                    )
                    Text(
                        stringResource(R.string.management_management_wallet_type),
                        style = MaterialTheme.typography.labelLarge,
                    )
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        WalletEditorState.supportedKinds.forEach { kind ->
                            FilterChip(
                                selected = state.kind == kind,
                                onClick = { state = state.selectKind(kind) },
                                label = { Text(walletKindTitle(kind)) },
                            )
                        }
                    }
                    if (state.originalOpeningBalanceMinor == null) {
                        OutlinedTextField(
                            value = state.openingBalanceText,
                            onValueChange = { state = state.copy(openingBalanceText = it) },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text(stringResource(R.string.shared_corelogic_financeenums_opening_balance)) },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            singleLine = true,
                        )
                    } else {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(stringResource(R.string.shared_corelogic_financeenums_opening_balance))
                            Text(
                                formatMinorUnits(
                                    checkNotNull(state.originalOpeningBalanceMinor),
                                    state.currencyCode,
                                ),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    Text(
                        stringResource(R.string.management_management_currency),
                        style = MaterialTheme.typography.labelLarge,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf("JPY", "VND").forEach { code ->
                            FilterChip(
                                selected = state.currencyCode == code,
                                onClick = { state = state.copy(currencyCode = code) },
                                label = { Text(code) },
                            )
                        }
                    }
                }
            }

            if (state.kind == WalletKind.BANK) {
                MistiaGlassCard { padding ->
                    Column(Modifier.padding(padding), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(
                            stringResource(R.string.management_management_bank),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        OutlinedTextField(
                            value = state.institutionDisplayName,
                            onValueChange = {
                                state = state.copy(institutionDisplayName = it, institutionPresetKey = null)
                            },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text(stringResource(R.string.management_management_or_enter_the_bank_name)) },
                            singleLine = true,
                        )
                    }
                }
            }

            validation?.let {
                Text(
                    text = walletValidationMessage(it),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            if (saveFailed) {
                Text(
                    text = stringResource(R.string.management_management_couldn_t_save_this_wallet_right_now),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }

            if (wallet != null) {
                HorizontalDivider()
                OutlinedButton(
                    enabled = !isSaving,
                    onClick = { archiveConfirmation = true },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        stringResource(R.string.management_management_archive_wallet),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
                Text(
                    stringResource(R.string.management_management_archived_wallets_will_no_longer_appear_in),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.height(28.dp))
        }
    }

    if (archiveConfirmation) {
        AlertDialog(
            onDismissRequest = { archiveConfirmation = false },
            title = { Text(stringResource(R.string.management_management_archive_wallet)) },
            text = { Text(stringResource(R.string.management_management_this_wallet_will_be_archived_archived_wallets)) },
            dismissButton = {
                TextButton(onClick = { archiveConfirmation = false }) {
                    Text(stringResource(R.string.common_cancel))
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        archiveConfirmation = false
                        isSaving = true
                        scope.launch {
                            onArchive().fold(
                                onSuccess = { onDismiss() },
                                onFailure = {
                                    isSaving = false
                                    saveFailed = true
                                },
                            )
                        }
                    },
                ) {
                    Text(stringResource(R.string.common_archive), color = MaterialTheme.colorScheme.error)
                }
            },
        )
    }
}

@Composable
internal fun WalletIcon(
    symbolName: String,
    kind: WalletKind?,
    colorHex: String,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier.clip(CircleShape).background(colorFromHex(colorHex).copy(alpha = 0.18f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = walletIcon(symbolName, kind),
            contentDescription = null,
            tint = colorFromHex(colorHex),
            modifier = Modifier.size(24.dp),
        )
    }
}

@Composable
internal fun walletKindTitle(kind: WalletKind): String = when (kind) {
    WalletKind.CASH -> stringResource(R.string.shared_corelogic_financeenums_cash)
    WalletKind.PAY_PAY -> "PayPay"
    WalletKind.BANK -> stringResource(R.string.shared_corelogic_financeenums_bank)
    WalletKind.CREDIT_CARD -> stringResource(R.string.shared_corelogic_financeenums_credit_card)
    WalletKind.E_WALLET -> stringResource(R.string.shared_corelogic_financeenums_e_wallet_barcode)
    WalletKind.PREPAID -> stringResource(R.string.shared_corelogic_financeenums_prepaid_i_c_card)
    WalletKind.INVESTMENT -> stringResource(R.string.shared_corelogic_financeenums_investment_stocks)
    WalletKind.CRYPTO -> stringResource(R.string.shared_corelogic_financeenums_crypto_digital_assets)
    WalletKind.OTHER -> stringResource(R.string.shared_corelogic_financeenums_other_wallet)
}

@Composable
private fun walletValidationMessage(validation: WalletEditorValidation): String = when (validation) {
    WalletEditorValidation.BANK_INSTITUTION_REQUIRED ->
        stringResource(R.string.management_management_choose_or_enter_a_bank_name_for)
    WalletEditorValidation.INVALID_OPENING_BALANCE ->
        stringResource(R.string.investment_error_invalid_amount)
    WalletEditorValidation.NAME_REQUIRED ->
        stringResource(R.string.management_management_couldn_t_save_this_wallet_right_now)
}

private fun walletIcon(symbolName: String, kind: WalletKind?): ImageVector = when (symbolName) {
    "mistia.wallet.cash" -> Icons.Default.Payments
    "mistia.wallet.paypay", "mistia.wallet.e_wallet" -> Icons.Default.QrCode2
    "mistia.wallet.bank" -> Icons.Default.AccountBalance
    "mistia.wallet.credit_card", "mistia.wallet.prepaid" -> Icons.Default.CreditCard
    "mistia.wallet.investment" -> Icons.Default.AccountBalanceWallet
    "mistia.wallet.crypto" -> Icons.Default.CurrencyBitcoin
    "mistia.wallet.savings" -> Icons.Default.Savings
    "mistia.wallet.travel" -> Icons.Default.Flight
    "mistia.wallet.family" -> Icons.Default.Groups
    "mistia.wallet.emergency" -> Icons.Default.HealthAndSafety
    "mistia.wallet.other" -> Icons.Default.MoreHoriz
    else -> when (kind) {
        WalletKind.CASH -> Icons.Default.Payments
        WalletKind.PAY_PAY, WalletKind.E_WALLET -> Icons.Default.QrCode2
        WalletKind.BANK -> Icons.Default.AccountBalance
        WalletKind.CREDIT_CARD, WalletKind.PREPAID -> Icons.Default.CreditCard
        WalletKind.INVESTMENT -> Icons.Default.AccountBalanceWallet
        WalletKind.CRYPTO -> Icons.Default.CurrencyBitcoin
        WalletKind.OTHER, null -> Icons.Default.MoreHoriz
    }
}

internal fun parseMinorUnits(raw: String, currencyCode: String): Long? = runCatching {
    val normalized = raw.trim().replace(",", "").ifEmpty { "0" }
    val fractionDigits = Currency.getInstance(currencyCode.uppercase(Locale.ROOT))
        .defaultFractionDigits.coerceAtLeast(0)
    BigDecimal(normalized)
        .movePointRight(fractionDigits)
        .setScale(0, RoundingMode.UNNECESSARY)
        .longValueExact()
}.getOrNull()

internal fun formatMinorInput(minor: Long, currencyCode: String): String {
    val fractionDigits = runCatching {
        Currency.getInstance(currencyCode.uppercase(Locale.ROOT)).defaultFractionDigits.coerceAtLeast(0)
    }.getOrDefault(0)
    return BigDecimal.valueOf(minor).movePointLeft(fractionDigits).stripTrailingZeros().toPlainString()
}

internal fun colorFromHex(raw: String): Color {
    val value = raw.removePrefix("#").toLongOrNull(16) ?: 0x8A8A8E
    return Color(
        red = ((value shr 16) and 0xFF) / 255f,
        green = ((value shr 8) and 0xFF) / 255f,
        blue = (value and 0xFF) / 255f,
    )
}

internal val WALLET_COLORS = listOf(
    "#2DAA9E",
    "#6BCB77",
    "#F26A5A",
    "#FF9F1C",
    "#FFE45E",
    "#57B7FF",
    "#5B7BFF",
    "#FF6FB5",
    "#9A67FF",
    "#8A8A8E",
)

internal val WALLET_ICON_SYMBOLS = listOf(
    "mistia.wallet.cash",
    "mistia.wallet.paypay",
    "mistia.wallet.bank",
    "mistia.wallet.credit_card",
    "mistia.wallet.e_wallet",
    "mistia.wallet.prepaid",
    "mistia.wallet.investment",
    "mistia.wallet.crypto",
    "mistia.wallet.other",
    "mistia.wallet.savings",
    "mistia.wallet.travel",
    "mistia.wallet.family",
    "mistia.wallet.emergency",
)
