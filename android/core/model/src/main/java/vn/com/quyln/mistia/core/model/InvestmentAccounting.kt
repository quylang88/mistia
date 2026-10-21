package vn.com.quyln.mistia.core.model

import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

enum class InvestmentTradeKind { BUY, SELL }

data class InvestmentTradeInput(
    val id: UUID,
    val kind: InvestmentTradeKind,
    val quantity: BigDecimal,
    val unitLabel: String?,
    val accountingGrossAmountMinor: Long,
    val occurredAt: Instant,
    val createdAt: Instant,
)
data class InvestmentTradeCalculation(
    val id: UUID,
    val releasedCostBasisMinor: Long,
    val realizedProfitLossMinor: Long,
    val positionQuantityAfter: BigDecimal,
    val positionCostBasisAfterMinor: Long,
    val openLotCountAfter: Int,
)
data class InvestmentUnitPosition(val unitKey: String, val unitLabel: String?, val quantity: BigDecimal)
data class InvestmentAccountingProjection(
    val calculations: List<InvestmentTradeCalculation>,
    val unitPositions: List<InvestmentUnitPosition>,
)
enum class InvestmentAccountingError { INVALID_QUANTITY, INVALID_AMOUNT, INSUFFICIENT_POSITION, ARITHMETIC_OVERFLOW }
class InvestmentAccountingException(val reason: InvestmentAccountingError) : IllegalArgumentException(reason.name)

object InvestmentUnitLabel {
    const val LEGACY_KEY = "__mistia_legacy_unit__"

    fun normalizedDisplay(value: String?): String? {
        if (value == null) return null
        val result = buildString {
            var gap = false
            for (character in value) {
                if (character.isInvestmentWhitespace()) {
                    if (isNotEmpty()) gap = true
                } else {
                    if (gap) append(' ')
                    append(character)
                    gap = false
                }
            }
        }
        return result.takeUnless { it.isEmpty() }
    }

    fun comparisonKey(value: String?): String =
        normalizedDisplay(value)?.let(SwiftInvestmentUnitFold::apply) ?: LEGACY_KEY

    fun matches(lhs: String?, rhs: String?): Boolean = comparisonKey(lhs) == comparisonKey(rhs)
}

object InvestmentAccountingEngine {
    private data class Lot(var quantity: BigDecimal, var costBasisMinor: Long)
    private data class UnitBalance(var label: String?, var quantity: BigDecimal)
    private fun fail(reason: InvestmentAccountingError): Nothing = throw InvestmentAccountingException(reason)
    private fun BigDecimal.canonical(): BigDecimal = if (signum() == 0) BigDecimal.ZERO else stripTrailingZeros()

    fun projection(trades: List<InvestmentTradeInput>): InvestmentAccountingProjection {
        val lots = mutableMapOf<String, java.util.ArrayDeque<Lot>>()
        val balances = mutableMapOf<String, UnitBalance>()
        var positionQuantity = BigDecimal.ZERO
        var positionCost = 0L
        var openLotCount = 0
        val calculations = ArrayList<InvestmentTradeCalculation>(trades.size)
        try {
            val ordered = trades.sortedWith(compareBy(InvestmentTradeInput::occurredAt)
                .thenBy(InvestmentTradeInput::createdAt).thenBy { it.id.toString() })
            for (trade in ordered) {
                val quantity = InvestmentDecimalMath.quantity(trade.quantity)
                if (quantity.signum() <= 0) fail(InvestmentAccountingError.INVALID_QUANTITY)
                if (trade.accountingGrossAmountMinor < 0) fail(InvestmentAccountingError.INVALID_AMOUNT)
                val key = InvestmentUnitLabel.comparisonKey(trade.unitLabel)
                var releasedCost = 0L
                var profitLoss = 0L
                when (trade.kind) {
                    InvestmentTradeKind.BUY -> {
                        positionCost = Math.addExact(positionCost, trade.accountingGrossAmountMinor)
                        positionQuantity = InvestmentDecimalMath.add(positionQuantity, quantity)
                        val balance = balances.getOrPut(key) {
                            UnitBalance(InvestmentUnitLabel.normalizedDisplay(trade.unitLabel), BigDecimal.ZERO)
                        }
                        balance.quantity = InvestmentDecimalMath.add(balance.quantity, quantity)
                        if (balance.label == null) balance.label = InvestmentUnitLabel.normalizedDisplay(trade.unitLabel)
                        lots.getOrPut(key) { java.util.ArrayDeque() }.addLast(Lot(quantity, trade.accountingGrossAmountMinor))
                        openLotCount++
                    }
                    InvestmentTradeKind.SELL -> {
                        val balance = balances[key]
                        if (balance == null || balance.quantity < quantity)
                            fail(InvestmentAccountingError.INSUFFICIENT_POSITION)
                        val unitLots = lots[key] ?: fail(InvestmentAccountingError.INSUFFICIENT_POSITION)
                        var remaining = quantity
                        while (remaining.signum() > 0) {
                            val lot = unitLots.peekFirst() ?: fail(InvestmentAccountingError.INSUFFICIENT_POSITION)
                            val quantity = remaining.min(lot.quantity)
                            val entireLot = quantity.compareTo(lot.quantity) == 0
                            val basis = if (entireLot) lot.costBasisMinor else
                                InvestmentDecimalMath.proportionalMinor(lot.costBasisMinor, quantity, lot.quantity)
                            releasedCost = Math.addExact(releasedCost, basis)
                            remaining = InvestmentDecimalMath.subtract(remaining,quantity)
                            lot.quantity = InvestmentDecimalMath.subtract(lot.quantity,quantity)
                            lot.costBasisMinor = Math.subtractExact(lot.costBasisMinor, basis)
                            if (lot.quantity.signum() == 0) {
                                unitLots.removeFirst()
                                openLotCount--
                            }
                        }
                        profitLoss = Math.subtractExact(trade.accountingGrossAmountMinor, releasedCost)
                        positionQuantity = InvestmentDecimalMath.subtract(positionQuantity,quantity)
                        balance.quantity = InvestmentDecimalMath.subtract(balance.quantity,quantity)
                        positionCost = Math.subtractExact(positionCost, releasedCost)
                        if (positionCost < 0) fail(InvestmentAccountingError.ARITHMETIC_OVERFLOW)
                        if (positionQuantity.signum() == 0) positionCost = 0
                    }
                }
                calculations.add(InvestmentTradeCalculation(trade.id, releasedCost, profitLoss,
                    positionQuantity.canonical(), positionCost, openLotCount))
            }
        } catch (_: ArithmeticException) {
            fail(InvestmentAccountingError.ARITHMETIC_OVERFLOW)
        }
        val positions = balances.entries.filter { it.value.quantity.signum() > 0 }.sortedBy { it.key }
            .map { InvestmentUnitPosition(it.key, it.value.label, it.value.quantity.canonical()) }
        return InvestmentAccountingProjection(calculations.toList(), positions)
    }
}
