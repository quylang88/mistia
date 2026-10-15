package vn.com.quyln.mistia.core.designsystem

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import vn.com.quyln.mistia.core.model.*

/** Local draft tool. Committing a calculation never persists a financial record. */
@Composable
fun AmountCalculatorDialog(initialText: String, scopeKey: String, onCommit: (String) -> Unit, onDismiss: () -> Unit) {
    val saver = listSaver<AmountCalculatorInput, Any>(
        save = { listOf(scopeKey, it.tokens, it.currentNumber) },
        restore = { values -> runCatching {
            require(values.size == 3 && values[0] == scopeKey)
            @Suppress("UNCHECKED_CAST") val tokens = values[1] as List<String>
            AmountCalculatorInput(tokens, values[2] as String).also { it.requireValid() }
        }.getOrElse { AmountCalculatorInput.initial(initialText) } })
    var input by rememberSaveable(scopeKey, stateSaver = saver) { mutableStateOf(AmountCalculatorInput.initial(initialText)) }
    var error by remember { mutableStateOf<Int?>(null) }
    val evaluation = AmountCalculator.evaluate(input.tokens)
    val currentCommit by rememberUpdatedState(onCommit)
    val currentDismiss by rememberUpdatedState(onDismiss)
    fun commit() {
        val result = evaluation.integerResult
        if (result != null && evaluation.canCommit) { currentCommit(groupCalculatorDigits(result.toString())); currentDismiss() }
        else error = when (evaluation.error) {
            AmountCalculatorError.DIVISION_BY_ZERO -> R.string.shared_amount_calculator_division_by_zero
            AmountCalculatorError.OVERFLOW -> R.string.shared_amount_calculator_result_too_large
            else -> R.string.shared_amount_calculator_integer_positive_required
        }
    }
    val lastNumber = input.currentNumber.ifEmpty { input.tokens.lastOrNull { it !in setOf("+", "-", "×", "÷") }.orEmpty() }
    val resultText = when {
        evaluation.error in setOf(AmountCalculatorError.EMPTY_EXPRESSION, AmountCalculatorError.INCOMPLETE_EXPRESSION) -> groupCalculatorDigits(lastNumber.ifEmpty { "0" })
        evaluation.integerResult != null -> groupCalculatorDigits(evaluation.integerResult.toString())
        evaluation.decimalIsNaN -> "NaN"
        evaluation.decimalResult != null -> requireNotNull(evaluation.decimalResult).stripTrailingZeros().toPlainString()
        else -> groupCalculatorDigits(lastNumber.ifEmpty { "0" })
    }
    val expressionLabel = stringResource(R.string.shared_amount_calculator_expression)
    val resultLabel = stringResource(R.string.shared_amount_calculator_result)
    val clearLabel = stringResource(R.string.shared_amount_calculator_clear)
    val deleteLabel = stringResource(R.string.shared_amount_calculator_delete_digit)
    Dialog(onDismissRequest = currentDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxWidth(0.94f).testTag("amountCalculator.dialog"), shape = MaterialTheme.shapes.extraLarge, tonalElevation = 6.dp) {
            Column(Modifier.verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(stringResource(R.string.shared_amount_calculator_title), style = MaterialTheme.typography.titleLarge)
                    TextButton(onClick = currentDismiss, modifier = Modifier.testTag("amountCalculator.cancel")) { Text(stringResource(R.string.common_cancel)) }
                }
                Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerHighest) {
                    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(input.tokens.joinToString(" ").ifEmpty { "0" }, Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).testTag("amountCalculator.expression").semantics { contentDescription = expressionLabel },
                            fontFamily = FontFamily.Monospace, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                        Text(resultText, Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).testTag("amountCalculator.result").semantics { contentDescription = resultLabel },
                            fontSize = if (resultText.length > 15) 22.sp else 32.sp, fontFamily = FontFamily.Monospace, maxLines = 1)
                    }
                }
                val rows = listOf(listOf("C", "⌫", "÷", "×"), listOf("7", "8", "9", "-"), listOf("4", "5", "6", "+"), listOf("1", "2", "3", "="), listOf("0", "00", "OK"))
                rows.forEach { keys -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    keys.forEach { key ->
                        val utility = key in setOf("C", "⌫")
                        val operation = key in setOf("+", "-", "×", "÷", "=", "OK")
                        val colors = if (operation) ButtonDefaults.buttonColors() else ButtonDefaults.filledTonalButtonColors()
                        Button(onClick = {
                            error = null
                            input = when (key) {
                                "C" -> input.clear(); "⌫" -> input.backspace(); "=" -> input.equalsResult()
                                "OK" -> { commit(); input }
                                "+", "-", "×", "÷" -> input.operation(key)
                                else -> input.digit(key)
                            }
                        }, modifier = Modifier.weight(if (keys.size == 3 && key == "0") 2f else 1f).heightIn(min = 48.dp).testTag("amountCalculator.key.$key")
                            .then(if (utility) Modifier.semantics { contentDescription = if (key == "C") clearLabel else deleteLabel } else Modifier),
                            shape = MaterialTheme.shapes.medium, colors = colors, contentPadding = PaddingValues(8.dp)) {
                            Text(if (key == "OK") stringResource(R.string.common_ok) else key, fontSize = 20.sp)
                        }
                    }
                } }
            }
        }
    }
    error?.let { message -> AlertDialog(onDismissRequest = { error = null }, title = { Text(stringResource(R.string.shared_amount_calculator_title)) },
        text = { Text(stringResource(message), Modifier.testTag("amountCalculator.error")) },
        confirmButton = { TextButton(onClick = { error = null }, modifier = Modifier.testTag("amountCalculator.dismissError")) { Text(stringResource(R.string.common_ok)) } }) }
}
private fun groupCalculatorDigits(text: String): String {
    val sign = if (text.startsWith("-")) "-" else ""
    return sign + text.removePrefix("-").reversed().chunked(3).joinToString(",").reversed()
}
