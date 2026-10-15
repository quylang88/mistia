package vn.com.quyln.mistia.feature.planning

/** Presentation only: preserve malformed input for validation; never change the unit or precision. */
internal fun groupedMinorAmountInput(text: String): String = vn.com.quyln.mistia.core.model.groupedMinorAmountInput(text)

internal fun planningAmountInput(text: String, currency: String): String =
    vn.com.quyln.mistia.core.model.currencyAmountInput(text, currency)
