package vn.com.quyln.mistia.core.model

data class AmountCalculatorInput(val tokens: List<String>, val currentNumber: String) {
    fun digit(value: String): AmountCalculatorInput {
        require(value in (0..9).map(Int::toString) || value == "00")
        if (tokens.isEmpty() || tokens.last() in operations) {
            val next = if (value == "00") "0" else value
            return AmountCalculatorInput(tokens + next, next)
        }
        val next = if (currentNumber == "0") { if (value == "00") "0" else value } else currentNumber + value
        return AmountCalculatorInput(tokens.dropLast(1) + next, next)
    }
    fun operation(value: String): AmountCalculatorInput {
        require(value in operations)
        if (tokens.isEmpty()) return this
        return if (tokens.last() in operations) copy(tokens = tokens.dropLast(1) + value) else AmountCalculatorInput(tokens + value, "")
    }
    fun backspace(): AmountCalculatorInput {
        if (tokens.isEmpty()) return this
        if (tokens.last() in operations) return AmountCalculatorInput(tokens.dropLast(1), digits(tokens.dropLast(1).lastOrNull().orEmpty()))
        val next = currentNumber.dropLast(1)
        return if (next.isEmpty()) AmountCalculatorInput(tokens.dropLast(1), digits(tokens.dropLast(1).lastOrNull().orEmpty()))
            else AmountCalculatorInput(tokens.dropLast(1) + next, next)
    }
    fun clear() = AmountCalculatorInput(emptyList(), "")
    fun equalsResult(): AmountCalculatorInput = AmountCalculator.evaluate(tokens).integerResult?.let { AmountCalculatorInput(listOf(it.toString()), it.toString()) } ?: this
    fun requireValid() {
        require(tokens.withIndex().all { (index, token) -> if (index % 2 == 0) token.isNotEmpty() && token.all { it in '0'..'9' } else token in operations })
        require(currentNumber == if (tokens.isEmpty() || tokens.last() in operations) "" else tokens.last())
    }
    companion object {
        private val operations = setOf("+", "-", "×", "÷")
        fun initial(text: String): AmountCalculatorInput {
            val input = digits(text)
            return AmountCalculatorInput(if (input.isEmpty()) emptyList() else listOf(input), input)
        }
        private fun digits(text: String) = text.filter { it in '0'..'9' }
    }
}
