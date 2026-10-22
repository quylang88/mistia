package vn.com.quyln.mistia.core.model

import java.math.BigInteger

enum class InvestmentCashTransferDirection { DEPOSIT, WITHDRAWAL }
data class InvestmentCashTransferPreview(
    val direction:InvestmentCashTransferDirection,val requestedMinor:Long,val maximumMinor:Long,
    val realizedProfitMinor:BigInteger,val availableInvestmentMinor:BigInteger,val linkedBookedMinor:BigInteger,val sourceOrdinaryMinor:BigInteger,
) {
    val isValid get()=requestedMinor>0 && requestedMinor<=maximumMinor
    val shortfallMinor get()=(realizedProfitMinor.max(BigInteger.ZERO)-availableInvestmentMinor.max(BigInteger.ZERO)).max(BigInteger.ZERO)
}
fun investmentCashTransferPreview(direction:InvestmentCashTransferDirection,requestedMinor:Long,realizedProfitMinor:BigInteger,
    availableInvestmentMinor:BigInteger,linkedBookedMinor:BigInteger,sourceActualMinor:BigInteger,sourceInvestmentMinor:BigInteger):InvestmentCashTransferPreview {
    val ordinary=(sourceActualMinor-sourceInvestmentMinor.max(BigInteger.ZERO)).max(BigInteger.ZERO)
    val maximum=when(direction) {
        InvestmentCashTransferDirection.DEPOSIT -> (realizedProfitMinor.max(BigInteger.ZERO)-availableInvestmentMinor.max(BigInteger.ZERO)).max(BigInteger.ZERO).min(ordinary)
        InvestmentCashTransferDirection.WITHDRAWAL -> linkedBookedMinor.max(BigInteger.ZERO)
    }.min(BigInteger.valueOf(Long.MAX_VALUE)).longValueExact()
    return InvestmentCashTransferPreview(direction,requestedMinor.coerceAtLeast(0),maximum,realizedProfitMinor,availableInvestmentMinor,linkedBookedMinor,ordinary)
}
