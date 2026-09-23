package vn.com.quyln.mistia.feature.management

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import vn.com.quyln.mistia.core.designsystem.MistiaGlassCard
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.CreditCardAccount
import vn.com.quyln.mistia.core.model.CreditCardDraft
import vn.com.quyln.mistia.core.model.CreditCardNetwork
import vn.com.quyln.mistia.core.model.CreditCardProfileRecord
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.WalletKind

data class CreditCardEditorState(
    val walletId: String?,
    val profileId: String?,
    val name: String,
    val issuerName: String,
    val network: CreditCardNetwork,
    val last4: String,
    val creditLimitText: String,
    val statementClosingDay: Int,
    val paymentDueDay: Int,
    val notes: String,
    val paymentSourceWalletId: String?,
    val currencyCode: String,
    val iconSymbolName: String,
    val iconColorHex: String,
    val sortOrder: Int,
) {
    fun withLast4(raw: String): CreditCardEditorState = copy(
        last4 = raw.filter(Char::isDigit).take(4),
    )

    fun toDraft(): CreditCardEditorDraftResult {
        if (name.isBlank()) {
            return CreditCardEditorDraftResult(validation = CreditCardEditorValidation.NAME_REQUIRED)
        }
        val creditLimit = parseMinorUnits(creditLimitText, currencyCode)
            ?.takeIf { it >= 0 }
            ?: return CreditCardEditorDraftResult(validation = CreditCardEditorValidation.INVALID_CREDIT_LIMIT)
        if (statementClosingDay !in 1..30 || paymentDueDay !in 2..31 ||
            statementClosingDay >= paymentDueDay
        ) {
            return CreditCardEditorDraftResult(validation = CreditCardEditorValidation.INVALID_BILLING_DAYS)
        }
        return CreditCardEditorDraftResult(
            draft = CreditCardDraft(
                walletId = walletId,
                profileId = profileId,
                name = name.trim(),
                issuerName = issuerName.trim(),
                network = network,
                last4 = last4,
                creditLimitMinor = creditLimit,
                statementClosingDay = statementClosingDay,
                paymentDueDay = paymentDueDay,
                notes = notes.trim().takeIf(String::isNotEmpty),
                paymentSourceWalletId = paymentSourceWalletId,
                currencyCode = currencyCode,
                iconSymbolName = iconSymbolName,
                iconColorHex = iconColorHex,
                sortOrder = sortOrder,
            ),
        )
    }

    companion object {
        fun new(nextSortOrder: Int = 0): CreditCardEditorState = CreditCardEditorState(
            walletId = null,
            profileId = null,
            name = "",
            issuerName = "",
            network = CreditCardNetwork.VISA,
            last4 = "",
            creditLimitText = "",
            statementClosingDay = 10,
            paymentDueDay = 26,
            notes = "",
            paymentSourceWalletId = null,
            currencyCode = "JPY",
            iconSymbolName = WalletKind.CREDIT_CARD.defaultIcon,
            iconColorHex = WalletKind.CREDIT_CARD.defaultColorHex,
            sortOrder = nextSortOrder,
        )

        fun edit(
            wallet: LedgerWalletRecord,
            profile: CreditCardProfileRecord,
        ): CreditCardEditorState {
            require(wallet.kind == WalletKind.CREDIT_CARD)
            require(profile.walletId == wallet.id)
            return CreditCardEditorState(
                walletId = wallet.id,
                profileId = profile.id,
                name = wallet.name,
                issuerName = profile.issuerName,
                network = profile.network ?: CreditCardNetwork.OTHER,
                last4 = profile.last4,
                creditLimitText = formatMinorInput(profile.creditLimitMinor, wallet.currencyCode),
                statementClosingDay = profile.statementClosingDay,
                paymentDueDay = profile.paymentDueDay,
                notes = profile.notes.orEmpty(),
                paymentSourceWalletId = profile.paymentSourceWalletId,
                currencyCode = wallet.currencyCode,
                iconSymbolName = wallet.iconSymbolName,
                iconColorHex = wallet.iconColorHex,
                sortOrder = wallet.sortOrder,
            )
        }

        val Saver: Saver<CreditCardEditorState, Any> = listSaver(
            save = {
                listOf(
                    it.walletId.orEmpty(),
                    it.profileId.orEmpty(),
                    it.name,
                    it.issuerName,
                    it.network.wireValue,
                    it.last4,
                    it.creditLimitText,
                    it.statementClosingDay,
                    it.paymentDueDay,
                    it.notes,
                    it.paymentSourceWalletId.orEmpty(),
                    it.currencyCode,
                    it.iconSymbolName,
                    it.iconColorHex,
                    it.sortOrder,
                )
            },
            restore = { values ->
                CreditCardEditorState(
                    walletId = (values[0] as String).takeIf(String::isNotEmpty),
                    profileId = (values[1] as String).takeIf(String::isNotEmpty),
                    name = values[2] as String,
                    issuerName = values[3] as String,
                    network = CreditCardNetwork.fromWireValue(values[4] as String) ?: CreditCardNetwork.OTHER,
                    last4 = values[5] as String,
                    creditLimitText = values[6] as String,
                    statementClosingDay = values[7] as Int,
                    paymentDueDay = values[8] as Int,
                    notes = values[9] as String,
                    paymentSourceWalletId = (values[10] as String).takeIf(String::isNotEmpty),
                    currencyCode = values[11] as String,
                    iconSymbolName = values[12] as String,
                    iconColorHex = values[13] as String,
                    sortOrder = values[14] as Int,
                )
            },
        )
    }
}

data class CreditCardEditorDraftResult(
    val draft: CreditCardDraft? = null,
    val validation: CreditCardEditorValidation? = null,
)

enum class CreditCardEditorValidation {
    NAME_REQUIRED,
    INVALID_CREDIT_LIMIT,
    INVALID_BILLING_DAYS,
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun CreditCardEditorSheet(
    wallet: LedgerWalletRecord?,
    profile: CreditCardProfileRecord?,
    paymentSourceWallets: List<LedgerWalletRecord>,
    nextSortOrder: Int,
    onDismiss: () -> Unit,
    onSave: suspend (CreditCardDraft) -> Result<CreditCardAccount>,
) {
    var state by rememberSaveable(wallet?.id, stateSaver = CreditCardEditorState.Saver) {
        mutableStateOf(
            if (wallet != null && profile != null) CreditCardEditorState.edit(wallet, profile)
            else CreditCardEditorState.new(nextSortOrder)
        )
    }
    var validation by remember { mutableStateOf<CreditCardEditorValidation?>(null) }
    var saveFailed by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    ModalBottomSheet(onDismissRequest = { if (!isSaving) onDismiss() }) {
        Column(
            modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp),
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
                    stringResource(
                        if (wallet == null) R.string.planning_planning_add_credit_card
                        else R.string.management_management_credit_card2
                    ),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                )
                Button(
                    enabled = !isSaving,
                    onClick = {
                        val result = state.toDraft()
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
                            WalletKind.CREDIT_CARD,
                            state.iconColorHex,
                            Modifier.size(48.dp),
                        )
                        Text(
                            stringResource(R.string.management_management_credit_card2),
                            modifier = Modifier.padding(start = 12.dp),
                            style = MaterialTheme.typography.titleMedium,
                        )
                    }
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        WALLET_COLORS.forEach { color ->
                            Box(
                                modifier = Modifier.padding(vertical = 4.dp)
                                    .size(if (state.iconColorHex.equals(color, true)) 32.dp else 28.dp)
                                    .clip(CircleShape)
                                    .background(colorFromHex(color))
                                    .clickable { state = state.copy(iconColorHex = color) }
                            )
                        }
                    }
                }
            }

            MistiaGlassCard { padding ->
                Column(Modifier.padding(padding), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        stringResource(R.string.planning_planning_card_details),
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
                    OutlinedTextField(
                        value = state.issuerName,
                        onValueChange = { state = state.copy(issuerName = it) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.management_management_issuer_name)) },
                        singleLine = true,
                    )
                    Text(stringResource(R.string.management_management_card_network))
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        CreditCardNetwork.entries.forEach { network ->
                            FilterChip(
                                selected = state.network == network,
                                onClick = { state = state.copy(network = network) },
                                label = { Text(creditCardNetworkTitle(network)) },
                            )
                        }
                    }
                    OutlinedTextField(
                        value = state.last4,
                        onValueChange = { state = state.withLast4(it) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.management_management_last_digits)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = state.creditLimitText,
                        onValueChange = { state = state.copy(creditLimitText = it) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.management_management_credit_limit)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true,
                    )
                    Text(stringResource(R.string.management_management_currency))
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

            MistiaGlassCard { padding ->
                Column(Modifier.padding(padding), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedTextField(
                        value = state.statementClosingDay.toString(),
                        onValueChange = { raw ->
                            raw.filter(Char::isDigit).toIntOrNull()?.let {
                                state = state.copy(statementClosingDay = it)
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.management_management_statement_closing_day)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = state.paymentDueDay.toString(),
                        onValueChange = { raw ->
                            raw.filter(Char::isDigit).toIntOrNull()?.let {
                                state = state.copy(paymentDueDay = it)
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.management_management_payment_day)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true,
                    )
                    Text(stringResource(R.string.management_management_payment_source))
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        FilterChip(
                            selected = state.paymentSourceWalletId == null,
                            onClick = { state = state.copy(paymentSourceWalletId = null) },
                            label = { Text(stringResource(R.string.management_management_choose_later)) },
                        )
                        paymentSourceWallets.forEach { source ->
                            FilterChip(
                                selected = state.paymentSourceWalletId == source.id,
                                onClick = { state = state.copy(paymentSourceWalletId = source.id) },
                                label = { Text(source.name) },
                            )
                        }
                    }
                    OutlinedTextField(
                        value = state.notes,
                        onValueChange = { state = state.copy(notes = it) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.management_management_notes)) },
                        minLines = 2,
                    )
                }
            }

            validation?.let {
                Text(
                    creditCardValidationMessage(it),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            if (saveFailed) {
                Text(
                    stringResource(R.string.planning_planning_couldn_t_save_this_card_right_now),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            Spacer(Modifier.height(28.dp))
        }
    }
}

@Composable
private fun creditCardValidationMessage(validation: CreditCardEditorValidation): String = when (validation) {
    CreditCardEditorValidation.INVALID_BILLING_DAYS ->
        stringResource(R.string.management_management_statement_closing_day_must_be_earlier_than)
    CreditCardEditorValidation.INVALID_CREDIT_LIMIT -> stringResource(R.string.investment_error_invalid_amount)
    CreditCardEditorValidation.NAME_REQUIRED ->
        stringResource(R.string.planning_planning_couldn_t_save_this_card_right_now)
}

@Composable
private fun creditCardNetworkTitle(network: CreditCardNetwork): String = when (network) {
    CreditCardNetwork.VISA -> "Visa"
    CreditCardNetwork.MASTERCARD -> "Mastercard"
    CreditCardNetwork.JCB -> "JCB"
    CreditCardNetwork.AMERICAN_EXPRESS -> "American Express"
    CreditCardNetwork.UNION_PAY -> "UnionPay"
    CreditCardNetwork.OTHER -> stringResource(R.string.shared_corelogic_financeenums_other_wallet)
}
