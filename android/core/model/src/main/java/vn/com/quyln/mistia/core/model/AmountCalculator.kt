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
        // Swift keeps evaluating a NaN term after Decimal range failure. A later
        // zero divisor still wins; validate divisors after parsing every operand.
        if (operations.withIndex().any { (index, operation) -> operation == "÷" && values[index + 1].signum() == 0 })
            return failure(AmountCalculatorError.DIVISION_BY_ZERO)
        return try {
            var term = values.first(); val additive = mutableListOf<BigDecimal>(); val signs = mutableListOf<String>()
            operations.forEachIndexed { index, operation ->
                val next = values[index + 1]
                when (operation) {
                    "×" -> term = multiply(term, next)
                    "÷" -> {
                        term = divide(term, next)
                    }
                    else -> { additive += term; signs += operation; term = next }
                }
            }
            additive += term
            var result = additive.first()
            signs.forEachIndexed { index, sign -> result = add(result, if (sign == "+") additive[index + 1] else additive[index + 1].negate()) }
            when {
                result.signum() <= 0 -> AmountCalculation(result, error = AmountCalculatorError.NON_POSITIVE_RESULT)
                result > BigDecimal.valueOf(Long.MAX_VALUE) -> AmountCalculation(result, error = AmountCalculatorError.OVERFLOW)
                result.stripTrailingZeros().scale() > 0 -> AmountCalculation(result, error = AmountCalculatorError.FRACTIONAL_RESULT)
                else -> AmountCalculation(result, result.longValueExact())
            }
        } catch (_: DecimalRangeException) { AmountCalculation(error = AmountCalculatorError.NON_POSITIVE_RESULT, decimalIsNaN = true) }
        catch (_: ArithmeticException) { failure(AmountCalculatorError.OVERFLOW) }
    }
    private fun multiply(lhs: BigDecimal, rhs: BigDecimal): BigDecimal {
        if (lhs.signum() == 0 || rhs.signum() == 0) return BigDecimal.ZERO
        var coefficient = lhs.unscaledValue().multiply(rhs.unscaledValue())
        var exponent = -lhs.scale() - rhs.scale()
        while (coefficient.abs() > maximumMantissa) { coefficient = coefficient.divide(BigInteger.TEN); exponent++ }
        // Foundation validates the operation's exponent before compacting zeros.
        if (exponent !in -128..127) throw DecimalRangeException()
        return decimal(BigDecimal(coefficient, -exponent))
    }
    // Foundation divides its integer coefficients after scaling the dividend by
    // 10^38, then fits the quotient to 128 bits. A fixed significant-digit
    // MathContext changes recurring fractions and subsequent calculations.
    private fun divide(dividend: BigDecimal, divisor: BigDecimal): BigDecimal {
        if (dividend.signum() == 0) return BigDecimal.ZERO
        val operands = if (divisor.scale() - dividend.scale() >= 19) normalizedOperands(dividend, divisor) else dividend to divisor
        // Swift restores both original operands when normalization loses either.
        val (a, b) = if (operands.first.signum() == 0 || operands.second.signum() == 0) dividend to divisor else operands
        var quotient = a.unscaledValue().multiply(BigInteger.TEN.pow(38)).divide(b.unscaledValue())
        var exponent = b.scale() - a.scale() - 38
        while (quotient > maximumMantissa) { quotient = quotient.divide(BigInteger.TEN); exponent++ }
        if (exponent !in -128..127) throw DecimalRangeException()
        return decimal(BigDecimal(quotient, -exponent))
    }
    private fun add(lhs: BigDecimal, rhs: BigDecimal): BigDecimal {
        if (lhs.signum() == 0) return rhs
        if (rhs.signum() == 0) return lhs
        val (a, b) = normalizedOperands(lhs, rhs)
        return decimal(a.add(b))
    }
    private fun normalizedOperands(lhs: BigDecimal, rhs: BigDecimal): Pair<BigDecimal, BigDecimal> {
        if (lhs.scale() == rhs.scale()) return lhs to rhs
        val firstIsHigher = lhs.scale() < rhs.scale()
        val high = if (firstIsHigher) lhs else rhs
        val low = if (firstIsHigher) rhs else lhs
        val difference = low.scale() - high.scale()
        val expanded = high.unscaledValue().multiply(BigInteger.TEN.pow(difference))
        val pair = if (expanded.abs() <= maximumMantissa) BigDecimal(expanded, low.scale()) to low else {
            // Foundation's conservative headroom estimate uses whole 16-bit
            // limbs, not all available coefficient bits. Keep its truncation.
            val limbs = (high.unscaledValue().abs().bitLength() + 15) / 16
            val shift = intArrayOf(0, 4, 9, 14, 19, 24, 28, 33)[8 - limbs]
            val lower = low.unscaledValue().divide(BigInteger.TEN.pow(difference - shift))
            if (lower.signum() == 0) high to BigDecimal.ZERO else {
                val scale = high.scale() + shift
                BigDecimal(high.unscaledValue().multiply(BigInteger.TEN.pow(shift)), scale) to BigDecimal(lower, scale)
            }
        }
        return if (firstIsHigher) pair else pair.second to pair.first
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
