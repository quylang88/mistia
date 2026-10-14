package vn.com.quyln.mistia

import android.content.Context
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

internal fun formatBillNotification(context:Context,message:BillNotificationMessage):BillNotificationText {
    val due=message.event.due
    val bill=due.bill
    val amount=due.amountMinor?.let {formatMinorUnits(it,bill.currencyCode)}
    val date=DateTimeFormatter.ofLocalizedDate(FormatStyle.SHORT)
        .withLocale(context.resources.configuration.locales[0]).format(due.dueDate.atZone(ZoneId.systemDefault()))
    fun string(id:Int,vararg args:Any)=context.getString(id,*args)
    return when(message.kind) {
        "billAutoPaymentFailed" -> {
            val billError=(message.failure as? BillPaymentException)?.reason
            val transactionError=(message.failure as? TransactionValidationException)?.reason
            val body=when {
                billError==BillPaymentError.WALLET_CURRENCY_MISMATCH -> string(R.string.planning_bill_payment_currency_mismatch)
                billError in setOf(BillPaymentError.MISSING_AMOUNT,BillPaymentError.INVALID_WALLET) ->
                    string(R.string.shared_notifications_mistiarecurringbillmaintenance_value_is_missing_an_amount_or_payment,bill.name)
                billError==BillPaymentError.INVESTMENT_USAGE_UNAVAILABLE -> string(R.string.investment_wallet_automatic_paused_message,bill.name)
                transactionError in setOf(TransactionValidationError.INSUFFICIENT_WALLET_BALANCE,TransactionValidationError.CREDIT_LIMIT_EXCEEDED) ->
                    string(R.string.shared_notifications_mistiarecurringbillmaintenance_insufficient_balance_to_auto_pay_value_please,bill.name)
                else -> string(R.string.shared_notifications_mistiarecurringbillmaintenance_failed_to_auto_pay_value_value,bill.name,
                    string(R.string.planning_duepayment_payment_failed))
            }
            BillNotificationText(string(R.string.shared_notifications_mistiarecurringbillmaintenance_auto_payment_failed),body)
        }
        "billOverdue" -> BillNotificationText(string(R.string.shared_notifications_mistiarecurringbillmaintenance_bill_overdue),
            if(amount==null) string(R.string.shared_notifications_mistiarecurringbillmaintenance_value_is_past_its_due_date,bill.name)
            else string(R.string.shared_notifications_mistiarecurringbillmaintenance_value_value_is_past_its_due_date,bill.name,amount))
        else -> {
            val title=if(message.event.kind==BillMaintenanceEventKind.DEADLINE) R.string.shared_notifications_mistiarecurringbillmaintenance_bill_due_today
                else R.string.shared_notifications_mistiarecurringbillmaintenance_payment_date
            val body=if(due.hasExplicitDueDate) {
                if(amount==null) string(R.string.shared_notifications_mistiarecurringbillmaintenance_value_is_due_by_value,bill.name,date)
                else string(R.string.shared_notifications_mistiarecurringbillmaintenance_value_value_is_due_by_value,bill.name,amount,date)
            } else {
                if(amount==null) string(R.string.shared_notifications_mistiarecurringbillmaintenance_value_is_ready_to_pay_today,bill.name)
                else string(R.string.shared_notifications_mistiarecurringbillmaintenance_value_value_is_ready_to_pay_today,bill.name,amount)
            }
            BillNotificationText(string(title),body)
        }
    }
}
