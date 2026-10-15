package vn.com.quyln.mistia.core.model

import org.junit.Assert.*
import org.junit.Test

class AmountCalculatorInputTest {
    @Test fun `opening uses same sanitized raw input as Swift without changing parent draft`() {
        assertEquals(AmountCalculatorInput(listOf("1234"), "1234"), AmountCalculatorInput.initial("1,234"))
        assertEquals(AmountCalculatorInput(listOf("1234"), "1234"), AmountCalculatorInput.initial("-1,234"))
        assertEquals(AmountCalculatorInput(emptyList(), ""), AmountCalculatorInput.initial(""))
    }
    @Test fun `digits double zero and leading zero keep a single current operand`() {
        val input = AmountCalculatorInput.initial("").digit("00").digit("00").digit("7").digit("00")
        assertEquals(listOf("700"), input.tokens); assertEquals("700", input.currentNumber)
    }
    @Test fun `operator replaces pending operator without prematurely evaluating precedence`() {
        val input = AmountCalculatorInput.initial("1").operation("+").operation("-").digit("2").operation("×").digit("3")
        assertEquals(listOf("1", "-", "2", "×", "3"), input.tokens)
        assertEquals(AmountCalculatorError.NON_POSITIVE_RESULT, AmountCalculator.evaluate(input.tokens).error)
        assertEquals(AmountCalculatorInput.initial(""), AmountCalculatorInput.initial("").operation("+"))
    }
    @Test fun `backspace removes digit then operator and restores preceding number`() {
        val input = AmountCalculatorInput.initial("123").operation("+").digit("4").backspace()
        assertEquals(listOf("123", "+"), input.tokens); assertEquals("", input.currentNumber)
        val back = input.backspace(); assertEquals(listOf("123"), back.tokens); assertEquals("123", back.currentNumber)
        assertEquals(listOf("12"), back.backspace().tokens)
    }
    @Test fun `equals collapses only valid positive integral result and can continue typing`() {
        val input = AmountCalculatorInput.initial("2").operation("+").digit("3").operation("×").digit("4").equalsResult()
        assertEquals(listOf("14"), input.tokens); assertEquals(listOf("140"), input.digit("0").tokens)
        val invalid = AmountCalculatorInput.initial("1").operation("÷").digit("3")
        assertEquals(invalid, invalid.equalsResult()); assertEquals(emptyList<String>(), invalid.clear().tokens)
    }
    @Test fun `unsupported key values cannot inject tokens`() {
        val input = AmountCalculatorInput.initial("123")
        for (digit in listOf("-1", "1e3", "1.5", "x", "")) assertThrows(IllegalArgumentException::class.java) { input.digit(digit) }
        for (op in listOf("*", "/", "x", "")) assertThrows(IllegalArgumentException::class.java) { input.operation(op) }
    }
}
