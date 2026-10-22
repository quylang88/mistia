package vn.com.quyln.mistia.feature.investment

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import vn.com.quyln.mistia.core.designsystem.R

@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun InvestmentCashDateTime(occurredAt:String,onChange:(String)->Unit,enabled:Boolean) {
    var dateOpen by rememberSaveable{mutableStateOf(false)}
    var timeOpen by rememberSaveable{mutableStateOf(false)}
    val current=runCatching{Instant.parse(occurredAt).atZone(ZoneId.systemDefault())}.getOrNull()
    val locale=LocalConfiguration.current.locales[0]
    Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
        OutlinedButton(onClick={dateOpen=true},enabled=enabled && current!=null,modifier=Modifier.weight(1f).testTag("investment.cash.transfer.date")) {
            Text(current?.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale)) ?: "—")
        }
        OutlinedButton(onClick={timeOpen=true},enabled=enabled && current!=null,modifier=Modifier.weight(1f).testTag("investment.cash.transfer.time")) {
            Text(current?.format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale)) ?: "—")
        }
    }
    if(dateOpen && current!=null) {
        val state=rememberDatePickerState(initialSelectedDateMillis=current.toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(onDismissRequest={dateOpen=false},modifier=Modifier.testTag("investment.cash.transfer.date.dialog"),
            confirmButton={TextButton(onClick={
                val day=state.selectedDateMillis?.let{Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()} ?: current.toLocalDate()
                onChange(day.atTime(current.toLocalTime()).atZone(ZoneId.systemDefault()).toInstant().toString());dateOpen=false
            },enabled=enabled,modifier=Modifier.testTag("investment.cash.transfer.date.confirm")){Text(stringResource(R.string.common_ok))}},
            dismissButton={TextButton(onClick={dateOpen=false},modifier=Modifier.testTag("investment.cash.transfer.date.cancel")){Text(stringResource(R.string.common_cancel))}}) {DatePicker(state)}
    }
    if(timeOpen && current!=null) {
        val state=rememberTimePickerState(current.hour,current.minute,is24Hour=true)
        AlertDialog(onDismissRequest={timeOpen=false},modifier=Modifier.testTag("investment.cash.transfer.time.dialog"),
            confirmButton={TextButton(onClick={
                onChange(current.toLocalDate().atTime(state.hour,state.minute,current.second).atZone(ZoneId.systemDefault()).toInstant().toString());timeOpen=false
            },enabled=enabled,modifier=Modifier.testTag("investment.cash.transfer.time.confirm")){Text(stringResource(R.string.common_ok))}},
            dismissButton={TextButton(onClick={timeOpen=false},modifier=Modifier.testTag("investment.cash.transfer.time.cancel")){Text(stringResource(R.string.common_cancel))}},text={TimePicker(state)})
    }
}
