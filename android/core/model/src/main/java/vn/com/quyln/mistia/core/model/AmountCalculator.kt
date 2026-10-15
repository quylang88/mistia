package vn.com.quyln.mistia.core.model

import java.math.BigDecimal
import java.math.BigInteger
import java.math.MathContext
import java.math.RoundingMode

enum class AmountCalculatorError(val wire: String) {
    EMPTY_EXPRESSION("emptyExpression"), INCOMPLETE_EXPRESSION("incompleteExpression"), INVALID_EXPRESSION("invalidExpression"),
    DIVISION_BY_ZERO("divisionByZero"), FRACTIONAL_RESULT("fractionalResult"), NON_POSITIVE_RESULT("nonPositiveResult"), OVERFLOW("overflow")
}
data class AmountCalculation(val decimalResult: BigDecimal? = null, val integerResult: Long? = null, val error: AmountCalculatorError? = null, val decimalIsNaN: Boolean = false) {
    val canCommit get() = integerResult != null && error == null
}
object AmountCalculator {
    private val operators = setOf("+", "-", "×", "÷")
    private val divisionContext = MathContext(38, RoundingMode.DOWN)
    private val maximumMantissa = BigInteger.ONE.shiftLeft(128).subtract(BigInteger.ONE)
    fun evaluate(tokens: List<String>): AmountCalculation {
        val normalized = tokens.filter { it.isNotEmpty() }
        if (normalized.isEmpty()) return failure(AmountCalculatorError.EMPTY_EXPRESSION)
        if (normalized.size % 2 == 0) return failure(AmountCalculatorError.INCOMPLETE_EXPRESSION)
        val values = mutableListOf<BigDecimal>(); val operations = mutableListOf<String>()
        normalized.forEachIndexed { index, token ->
            if (index % 2 == 0) {
                val digits = token.filter { it in '0'..'9' }
                val number = runCatching { decimal(digits.toBigDecimal()) }.getOrNull()
                    ?: return failure(AmountCalculatorError.INVALID_EXPRESSION)
                values += number
            } else {
                if (token !in operators) return failure(AmountCalculatorError.INVALID_EXPRESSION)
                operations += token
            }
        }
        return try {
            var term = values.first(); val additive = mutableListOf<BigDecimal>(); val signs = mutableListOf<String>()
            operations.forEachIndexed { index, operation ->
                val next = values[index + 1]
                when (operation) {
                    "×" -> term = decimal(term.multiply(next))
                    "÷" -> {
                        if (next.signum() == 0) return failure(AmountCalculatorError.DIVISION_BY_ZERO)
                        term = decimal(term.divide(next, divisionContext))
                    }
                    else -> { additive += term; signs += operation; term = next }
                }
            }
            additive += term
            var result = additive.first()
            signs.forEachIndexed { index, sign -> result = decimal(if (sign == "+") result.add(additive[index + 1]) else result.subtract(additive[index + 1])) }
            when {
                result.signum() <= 0 -> AmountCalculation(result, error = AmountCalculatorError.NON_POSITIVE_RESULT)
                result > BigDecimal.valueOf(Long.MAX_VALUE) -> AmountCalculation(result, error = AmountCalculatorError.OVERFLOW)
                result.stripTrailingZeros().scale() > 0 -> AmountCalculation(result, error = AmountCalculatorError.FRACTIONAL_RESULT)
                else -> AmountCalculation(result, result.longValueExact())
            }
        } catch (_: DecimalRangeException) { AmountCalculation(error = AmountCalculatorError.NON_POSITIVE_RESULT, decimalIsNaN = true) }
        catch (_: ArithmeticException) { failure(AmountCalculatorError.OVERFLOW) }
    }
    // Foundation Decimal's bounded mantissa; retain exact integers when their 128-bit coefficient fits.
    private fun decimal(number: BigDecimal): BigDecimal {
        var value = number.stripTrailingZeros()
        while (value.unscaledValue().abs() > maximumMantissa) value = value.round(MathContext(value.precision() - 1, RoundingMode.DOWN)).stripTrailingZeros()
        if (-value.scale() > 127) {
            if (-value.scale() - 127 > 38) throw DecimalRangeException()
            value = value.setScale(-127)
            if (value.unscaledValue().abs() > maximumMantissa) throw DecimalRangeException()
        }
        if (value.scale() > 128) throw DecimalRangeException()
        return value
    }
    private fun failure(error: AmountCalculatorError) = AmountCalculation(error = error)
}

private class DecimalRangeException : ArithmeticException()
