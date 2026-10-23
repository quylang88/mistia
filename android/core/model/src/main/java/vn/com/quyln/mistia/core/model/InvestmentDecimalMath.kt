package vn.com.quyln.mistia.core.model

import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode

/**
 * Foundation Decimal intermediates use an unsigned 128-bit significand.
 * Multiplication and division discard low digits when fitting that significand.
 * Keeping the final ratio exact changes half-minor results on long quantities.
 */
internal object InvestmentDecimalMath {
    private val maximum = BigInteger.ONE.shiftLeft(128).subtract(BigInteger.ONE)
    private val ten38 = BigInteger.TEN.pow(38)
    private data class Parts(val coefficient: BigInteger, val exponent: Int)

    private fun parts(value: BigDecimal): Parts {
        var compact = value.stripTrailingZeros()
        // Foundation stops compacting at exponent127; larger finite values
        // retain zero digits in their 128-bit significand.
        if (compact.scale() < -165 || compact.scale() > 128)
            throw ArithmeticException("Quantity is outside Foundation decimal range")
        if (compact.scale() < -127) compact = compact.setScale(-127)
        return Parts(compact.unscaledValue(), Math.negateExact(compact.scale()))
    }

    private fun fit(coefficient: BigInteger, exponent: Int): BigDecimal {
        if (coefficient.signum() == 0) return BigDecimal.ZERO
        var mantissa = coefficient
        var power = exponent
        // Skip decimal digits that cannot fit in 128 bits in one operation.
        // Reject an impossible exponent before allocating a huge power of ten.
        val discard = (mantissa.abs().toString().length - 39).coerceAtLeast(0)
        if (discard > 0) {
            power = Math.addExact(power,discard)
            if (power > 165) throw ArithmeticException("Foundation decimal exponent overflow")
            mantissa = mantissa.divide(BigInteger.TEN.pow(discard))
        }
        while (mantissa.abs() > maximum) {
            mantissa = mantissa.divide(BigInteger.TEN)
            power = Math.incrementExact(power)
        }
        if (power > 165) throw ArithmeticException("Foundation decimal exponent overflow")
        if (power > 127) {
            mantissa = mantissa.multiply(BigInteger.TEN.pow(Math.subtractExact(power,127)))
            power = 127
            if (mantissa.abs() > maximum) throw ArithmeticException("Foundation decimal significand overflow")
        }
        if (power < -128) throw ArithmeticException("Foundation decimal exponent overflow")
        return BigDecimal(mantissa, -power).stripTrailingZeros()
    }

    fun quantity(value: BigDecimal): BigDecimal {
        val p = parts(value)
        return fit(p.coefficient,p.exponent)
    }

    private fun normalized(lhs: BigDecimal, rhs: BigDecimal): Pair<Parts,Parts> {
        val left = parts(lhs)
        val right = parts(rhs)
        if (left.exponent == right.exponent) return left to right
        val leftHigher = left.exponent > right.exponent
        var higher = if (leftHigher) left else right
        var lower = if (leftHigher) right else left
        var distance = Math.subtractExact(higher.exponent,lower.exponent)
        var coefficient = higher.coefficient
        while (distance > 0 && coefficient.abs() <= maximum.divide(BigInteger.TEN)) {
            coefficient = coefficient.multiply(BigInteger.TEN)
            higher = Parts(coefficient,higher.exponent-1)
            distance--
        }
        if (distance > 0) {
            // The low operand loses its least significant digits to match the
            // greatest common exponent the 128-bit high operand can represent.
            lower = Parts(lower.coefficient.divide(BigInteger.TEN.pow(distance)),higher.exponent)
        }
        return if (leftHigher) higher to lower else lower to higher
    }

    fun add(lhs: BigDecimal, rhs: BigDecimal): BigDecimal {
        if (lhs.signum() == 0) return rhs
        if (rhs.signum() == 0) return lhs
        val (left,right) = normalized(lhs,rhs)
        return fit(left.coefficient.add(right.coefficient),left.exponent)
    }

    fun subtract(lhs: BigDecimal, rhs: BigDecimal): BigDecimal = add(lhs,rhs.negate())

    fun divide(lhs:BigDecimal,rhs:BigDecimal):BigDecimal {
        var left=parts(lhs);var right=parts(rhs)
        if(left.exponent-right.exponent>=19) {
            val (a,b)=normalized(lhs,rhs)
            if(a.coefficient.signum()!=0 && b.coefficient.signum()!=0){left=a;right=b}
        }
        val quotient=left.coefficient.multiply(ten38).divide(right.coefficient)
        return fit(quotient,Math.subtractExact(Math.subtractExact(left.exponent,right.exponent),38))
    }

    fun proportionalMinor(total: Long, numerator: BigDecimal, denominator: BigDecimal): Long {
        val amount = parts(BigDecimal.valueOf(total))
        val part = parts(numerator)
        val product = fit(amount.coefficient.multiply(part.coefficient),Math.addExact(amount.exponent,part.exponent))
        var left = parts(product)
        var right = parts(denominator)
        if (left.exponent-right.exponent >= 19) {
            val (normalizedLeft,normalizedRight) = normalized(product,denominator)
            if (normalizedLeft.coefficient.signum()!=0 && normalizedRight.coefficient.signum()!=0) {
                left=normalizedLeft
                right=normalizedRight
            }
        }
        val quotient = left.coefficient.multiply(ten38).divide(right.coefficient)
        val ratio = fit(quotient,Math.subtractExact(Math.subtractExact(left.exponent,right.exponent),38))
        return ratio.setScale(0,RoundingMode.HALF_UP).longValueExact()
    }
}
