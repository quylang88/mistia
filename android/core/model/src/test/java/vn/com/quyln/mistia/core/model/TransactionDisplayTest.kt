package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TransactionDisplayTest {
    private fun record(body: String) = CloudRecord("ledger_transactions", "t", "u", Json.parseToJsonElement(body).jsonObject, null, null, 1)
    @Test fun sourceAmountMustNeverBePairedWithReportingCurrency() {
        val record = record("""{"amount_minor":1000,"source_currency_code":"JPY","reporting_currency_code":"USD","reporting_amount_minor":675}""")
        assertEquals(Money(1000, "JPY"), record.transactionDisplayMoney())
    }
    @Test fun legacySourceCurrencyFallsBackToWalletThenDestinationThenYen() {
        val record = record("""{"amount_minor":1234,"reporting_currency_code":"USD"}""")
        assertEquals(Money(1234, "VND"), record.transactionDisplayMoney("VND", "USD"))
        assertEquals(Money(1234, "USD"), record.transactionDisplayMoney(null, "USD"))
        assertEquals(Money(1234, "JPY"), record.transactionDisplayMoney())
    }
    @Test fun internalTransferListUsesSourceAmountAsInSwiftZeroCashflowRule() {
        val record = record("""{"primary_kind_raw_value":"transfer","transfer_subtype_raw_value":"internalTransfer","amount_minor":15000,"source_currency_code":"JPY","destination_amount_minor":10000,"destination_currency_code":"USD"}""")
        assertEquals(Money(15000, "JPY"), record.transactionDisplayMoney())
    }
    @Test fun missingAmountIsNotInventedAsZero() { assertNull(record("{}").transactionDisplayMoney()) }
}
