package vn.com.quyln.mistia.auth

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.*
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import vn.com.quyln.mistia.R
import vn.com.quyln.mistia.core.auth.*
import vn.com.quyln.mistia.core.designsystem.R as D

@Composable
fun AuthScreen(model: AuthViewModel = viewModel()) {
    val state by model.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var email by rememberSaveable { mutableStateOf("") }
    var name by rememberSaveable { mutableStateOf("") }
    // Passwords deliberately never enter Android saved instance state.
    var password by remember { mutableStateOf("") }
    var confirmation by remember { mutableStateOf("") }
    var visible by remember { mutableStateOf(false) }
    LaunchedEffect(state.clearPasswordsVersion) { password = ""; confirmation = ""; visible = false }
    BackHandler(state.mode != AuthMode.MENU) { model.show(AuthMode.MENU) }
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(
            Modifier.safeDrawingPadding().imePadding().verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 32.dp).widthIn(max = 440.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Spacer(Modifier.height(24.dp))
            Image(painterResource(R.drawable.mistia_brand), null, Modifier.size(80.dp).clip(RoundedCornerShape(20.dp)))
            Text(stringResource(when (state.mode) {
                AuthMode.SIGN_UP -> D.string.management_managementauth_create_account
                AuthMode.RESET_PASSWORD -> D.string.management_managementauth_forgot_password
                AuthMode.CONFIRM_EMAIL -> D.string.management_managementauth_confirm_your_email
                else -> D.string.management_managementauth_welcome_to_mistia
            }), style = MaterialTheme.typography.headlineSmall, textAlign = TextAlign.Center)
            Text(stringResource(D.string.management_managementauth_use_the_same_mistia_account_to_sync),
                textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (state.mode == AuthMode.MENU) {
                Button(onClick = { model.signInWithGoogle(context) }, enabled = !state.busy, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) {
                    Text("G", style = MaterialTheme.typography.titleLarge)
                    Spacer(Modifier.width(12.dp))
                    Text(stringResource(D.string.management_managementauth_continue_with_google))
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    HorizontalDivider(Modifier.weight(1f))
                    Text(stringResource(D.string.management_managementauth_or), Modifier.padding(horizontal = 16.dp))
                    HorizontalDivider(Modifier.weight(1f))
                }
                OutlinedButton(onClick = { model.show(AuthMode.SIGN_IN) }, enabled = !state.busy, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) {
                    Text(stringResource(D.string.management_managementauth_continue_with_email))
                }
                Text(stringResource(D.string.management_managementauth_by_continuing_you_agree_to_our_terms),
                    style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Center)
            } else if (state.mode == AuthMode.CONFIRM_EMAIL) {
                Text(stringResource(D.string.management_managementauth_your_account_is_waiting_for_email_confirmation))
                Button(onClick = model::resendConfirmation, enabled = !state.busy) {
                    Text(stringResource(D.string.management_managementauth_resend_confirmation_email))
                }
            } else {
                if (state.mode == AuthMode.SIGN_UP) AuthFieldInput(name, { name = it }, D.string.management_managementauth_display_name, state.errors[AuthField.NAME], state.busy)
                AuthFieldInput(email, { email = it }, D.string.management_managementauth_email2, state.errors[AuthField.EMAIL], state.busy, KeyboardType.Email)
                if (state.mode != AuthMode.RESET_PASSWORD) {
                    AuthFieldInput(password, { password = it }, D.string.management_managementauth_password, state.errors[AuthField.PASSWORD], state.busy, KeyboardType.Password, visible) { visible = !visible }
                    if (state.mode == AuthMode.SIGN_UP) {
                        Text(stringResource(D.string.management_managementauth_password_must_be_at_least_characters) + "\n" +
                            stringResource(D.string.management_managementauth_password_needs_at_least_uppercase_letter) + "\n" +
                            stringResource(D.string.management_managementauth_password_needs_at_least_lowercase_letter),
                            style = MaterialTheme.typography.bodySmall, modifier = Modifier.fillMaxWidth())
                        AuthFieldInput(confirmation, { confirmation = it }, D.string.management_managementauth_confirm_password, state.errors[AuthField.CONFIRM_PASSWORD], state.busy, KeyboardType.Password, visible) { visible = !visible }
                    }
                }
                Button(onClick = { model.submit(email, password, confirmation, name) }, enabled = !state.busy, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) {
                    Text(stringResource(when (state.mode) {
                        AuthMode.SIGN_UP -> D.string.management_managementauth_create_account
                        AuthMode.RESET_PASSWORD -> D.string.management_managementauth_send_reset_email
                        else -> D.string.management_managementauth_sign_in
                    }))
                }
                if (state.mode == AuthMode.SIGN_IN) {
                    TextButton(onClick = { model.show(AuthMode.RESET_PASSWORD) }, enabled = !state.busy) { Text(stringResource(D.string.management_managementauth_forgot_password)) }
                    TextButton(onClick = { model.show(AuthMode.SIGN_UP) }, enabled = !state.busy) { Text(stringResource(D.string.management_managementauth_sign_up_now)) }
                }
            }
            state.notice?.let { Text(stringResource(it.resource()), textAlign = TextAlign.Center) }
            if (state.busy) CircularProgressIndicator(Modifier.size(24.dp))
            if (state.mode != AuthMode.MENU) TextButton(onClick = { model.show(if (state.mode == AuthMode.SIGN_IN) AuthMode.MENU else AuthMode.SIGN_IN) }, enabled = !state.busy) {
                Text(stringResource(if (state.mode == AuthMode.SIGN_IN) D.string.common_close else D.string.management_managementauth_back_to_sign_in))
            }
        }
    }
}

@Composable
private fun AuthFieldInput(value: String, change: (String) -> Unit, label: Int, error: AuthInputError?, busy: Boolean,
    keyboard: KeyboardType = KeyboardType.Text, visible: Boolean = false, toggle: (() -> Unit)? = null) {
    OutlinedTextField(value, change, Modifier.fillMaxWidth(), enabled = !busy, label = { Text(stringResource(label)) },
        isError = error != null, supportingText = error?.let { { Text(stringResource(it.resource())) } },
        singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = keyboard),
        visualTransformation = if (keyboard == KeyboardType.Password && !visible) PasswordVisualTransformation() else VisualTransformation.None,
        trailingIcon = toggle?.let { action -> { IconButton(onClick = action) {
            Icon(if (visible) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                stringResource(if (visible) D.string.management_managementauth_hide_password else D.string.management_managementauth_show_password))
        } } })
}
private fun AuthInputError.resource() = when (this) {
    AuthInputError.NAME_REQUIRED -> D.string.management_managementauth_display_name_can_t_be_empty
    AuthInputError.EMAIL_INVALID -> D.string.management_managementauth_the_email_format_doesn_t_look_right
    AuthInputError.PASSWORD_REQUIRED -> D.string.management_managementauth_enter_your_password_to_continue
    AuthInputError.PASSWORD_LENGTH -> D.string.management_managementauth_password_must_be_at_least_characters
    AuthInputError.PASSWORD_UPPERCASE -> D.string.management_managementauth_password_needs_at_least_uppercase_letter
    AuthInputError.PASSWORD_LOWERCASE -> D.string.management_managementauth_password_needs_at_least_lowercase_letter
    AuthInputError.CONFIRM_REQUIRED -> D.string.management_managementauth_re_enter_your_password_to_confirm_it
    AuthInputError.PASSWORD_MISMATCH -> D.string.management_managementauth_the_confirmation_password_doesn_t_match_yet
}
private fun AuthNotice.resource() = when (this) {
    AuthNotice.INVALID_CREDENTIALS -> D.string.shared_session_session_the_email_or_password_is_incorrect_check
    AuthNotice.CONFIRM_EMAIL -> D.string.shared_session_session_check_your_email_to_confirm
    AuthNotice.RESET_SENT -> D.string.shared_session_session_if_the_email_is_valid_mistia_will
    AuthNotice.CONFIRMATION_SENT -> D.string.shared_session_session_confirmation_email_sent_again
    AuthNotice.RATE_LIMITED -> D.string.shared_session_session_please_wait_a_bit_before_trying_again
    AuthNotice.GOOGLE_SETUP -> D.string.shared_session_session_google_sign_in_isn_t_ready_yet
    AuthNotice.GOOGLE_FAILED -> D.string.shared_session_session_google_sign_in_couldn_t_finish
    AuthNotice.NETWORK -> D.string.shared_session_session_no_network_connection_reconnect_to_sync_edit
    AuthNotice.GENERAL -> D.string.common_unknown_error
}
