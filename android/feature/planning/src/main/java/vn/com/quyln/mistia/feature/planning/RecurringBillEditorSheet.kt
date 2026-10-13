package vn.com.quyln.mistia.feature.planning

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import kotlinx.coroutines.launch
import vn.com.quyln.mistia.core.designsystem.CategoryIcon
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun RecurringBillEditorSheet(
    owner:String,bill:RecurringBillPlanRecord?,categories:List<TransactionCategoryRecord>,wallets:List<LedgerWalletRecord>,
    language:CategoryNameLanguage,
    onSave:suspend (RecurringBillDraft)->Result<RecurringBillPlanRecord>,
    onPause:suspend (String)->Result<Unit>,onResume:suspend (String)->Result<Unit>,onArchive:suspend (String)->Result<Unit>,onDismiss:()->Unit,
) {
    val zone=ZoneId.systemDefault()
    val initial=remember(owner,bill?.id) {bill?.let {RecurringBillEditorState.from(it,LocalDate.now(zone),zone)} ?: RecurringBillEditorState.fresh(LocalDate.now(zone),"JPY")}
    var state by rememberSaveable(owner,bill?.id,stateSaver=RecurringBillEditorState.saver(owner)) {mutableStateOf(initial)}
    var busy by remember {mutableStateOf(false)}
    var discard by remember {mutableStateOf(false)}
    var picker by remember {mutableStateOf<String?>(null)}
    var action by remember {mutableStateOf<String?>(null)}
    var error by remember {mutableStateOf<Int?>(null)}
    val scope=rememberCoroutineScope()
    val changed=state!=initial
    fun close() {if(!busy) {if(changed) discard=true else onDismiss()}}
    fun update(next:RecurringBillEditorState) {state=next.normalizedAutoPay();error=null}
    val sheet=rememberModalBottomSheetState(skipPartiallyExpanded=true,confirmValueChange={
        if(it==SheetValue.Hidden && (busy || changed)) {if(!busy) discard=true;false} else true
    })
    val selected=categories.firstOrNull {it.ownerUserId==owner && it.id==state.categoryId && it.deletedAt==null}
    ModalBottomSheet(onDismissRequest={close()},sheetState=sheet) {
        Column(Modifier.testTag("bill.editor").fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.CenterVertically) {
                Text(stringResource(if(bill==null) R.string.planning_planning_add_bill else R.string.planning_planning_s_a_h_a_n),style=MaterialTheme.typography.titleLarge)
                TextButton(onClick={close()},enabled=!busy,modifier=Modifier.testTag("bill.close")) {Text(stringResource(R.string.common_close))}
            }
            TextButton(onClick={picker="category"},enabled=!busy,modifier=Modifier.fillMaxWidth().testTag("bill.category")) {
                CategoryIcon(selected?.iconSymbolName ?: bill?.iconSymbolName ?: "mistia.plan.bill",TransactionCategoryKind.EXPENSE,selected?.iconColorHex ?: "#8A8A8E")
                Spacer(Modifier.width(12.dp));Text(selected?.localizedBudgetName(language) ?: stringResource(R.string.planning_planning_payment_category))
            }
            OutlinedTextField(state.name,onValueChange={state=state.copy(name=it);error=null},label={Text(stringResource(R.string.planning_planning_bill_name))},enabled=!busy,modifier=Modifier.fillMaxWidth().testTag("bill.name"))
            OutlinedTextField(state.amountText,onValueChange={state=state.copy(amountText=it);error=null},label={Text(stringResource(R.string.planning_planning_amount_optional))},suffix={Text(state.currencyCode)},keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Decimal),enabled=!busy,modifier=Modifier.fillMaxWidth().testTag("bill.amount"))
            Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                BillScheduleKind.entries.forEach {kind -> FilterChip(selected=state.scheduleKind==kind,onClick={update(state.copy(scheduleKind=kind))},enabled=!busy,
                    label={Text(stringResource(if(kind==BillScheduleKind.RECURRING) R.string.planning_planning_recurring else R.string.planning_planning_one_time))})}
            }
            if(state.scheduleKind==BillScheduleKind.RECURRING) {
                BillPickerButton(R.string.planning_planning_payment_day,stringResource(R.string.planning_planning_day_value,state.paymentStartDay.toString()),!busy,"bill.start") {picker="startDay"}
                if(bill==null) Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    listOf(false,true).forEach {next -> FilterChip(selected=state.startsNextMonth==next,onClick={state=state.copy(startsNextMonth=next)},enabled=!busy,
                        label={Text(stringResource(if(next) R.string.planning_planning_next_month else R.string.planning_planning_current_month))})}
                }
            } else BillPickerButton(R.string.planning_planning_payment_date,state.paymentStartDate,!busy,"bill.start") {picker="startDate"}
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.CenterVertically) {
                Text(stringResource(R.string.planning_planning_has_deadline));Switch(state.hasDeadline,onCheckedChange={update(state.copy(hasDeadline=it))},enabled=!busy)
            }
            if(state.hasDeadline) BillPickerButton(R.string.planning_planning_deadline,
                if(state.scheduleKind==BillScheduleKind.RECURRING) stringResource(R.string.planning_planning_day_value,state.dueDay.toString()) else state.dueDate,!busy,"bill.deadline") {
                picker=if(state.scheduleKind==BillScheduleKind.RECURRING) "dueDay" else "dueDate"
            }
            if(state.scheduleKind==BillScheduleKind.RECURRING) Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.CenterVertically) {
                Text(stringResource(R.string.planning_planning_frequency_every_value_month_s,state.frequencyMonths.toString()))
                TextButton(onClick={state=state.copy(frequencyMonths=state.frequencyMonths-1)},enabled=!busy && state.frequencyMonths>1) {Text("−")}
                TextButton(onClick={state=state.copy(frequencyMonths=state.frequencyMonths+1)},enabled=!busy && state.frequencyMonths<12) {Text("+")}
            }
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.CenterVertically) {
                Text(stringResource(R.string.planning_planning_auto_pay));Switch(state.autoPayEnabled,onCheckedChange={update(state.copy(autoPayEnabled=it))},enabled=!busy)
            }
            if(state.autoPayEnabled) BillPickerButton(if(state.scheduleKind==BillScheduleKind.RECURRING) R.string.planning_planning_auto_pay_day else R.string.planning_planning_auto_pay_date,
                if(state.scheduleKind==BillScheduleKind.RECURRING) stringResource(if(state.hasDeadline && state.dueDay<state.paymentStartDay && state.autoPayDay<state.paymentStartDay) R.string.planning_planning_day_value_next_month else R.string.planning_planning_day_value,state.autoPayDay.toString()) else state.autoPayDate,!busy,"bill.autoPay") {
                picker=if(state.scheduleKind==BillScheduleKind.RECURRING) "autoDay" else "autoDate"
            }
            BillPickerButton(R.string.planning_planning_payment_wallet,wallets.firstOrNull {it.ownerUserId==owner && it.id==state.paymentWalletId}?.name ?: stringResource(R.string.planning_planning_choose_wallet),!busy,"bill.wallet") {picker="wallet"}
            error?.let {Text(stringResource(it),color=MaterialTheme.colorScheme.error)}
            Button(onClick={
                val draft=try {state.toDraft(zone)} catch(validation:Exception) {error=billError(validation);return@Button}
                busy=true;error=null
                scope.launch {val result=onSave(draft);busy=false;result.fold(onSuccess={onDismiss()},onFailure={error=billError(it)})}
            },enabled=!busy,modifier=Modifier.fillMaxWidth().testTag("bill.save")) {
                if(busy) CircularProgressIndicator(Modifier.size(20.dp),strokeWidth=2.dp) else Text(stringResource(R.string.common_save))
            }
            if(bill!=null) {
                if(bill.scheduleKind==BillScheduleKind.RECURRING && state.scheduleKind==BillScheduleKind.RECURRING) TextButton(onClick={action=if(bill.isPaused) "resume" else "pause"},enabled=!busy,modifier=Modifier.fillMaxWidth().testTag("bill.pauseResume")) {
                    Text(stringResource(if(bill.isPaused) R.string.planning_planning_resume_bill else R.string.planning_planning_pause_bill))
                }
                TextButton(onClick={action="archive"},enabled=!busy,modifier=Modifier.fillMaxWidth().testTag("bill.archive")) {Text(stringResource(R.string.planning_planning_archive_bill),color=MaterialTheme.colorScheme.error)}
            }
            Spacer(Modifier.height(16.dp))
        }
    }
    if(discard) AlertDialog(onDismissRequest={discard=false},title={Text(stringResource(R.string.planning_budget_editor_discard_title))},
        confirmButton={TextButton(onClick={discard=false;onDismiss()},modifier=Modifier.testTag("bill.discard")) {Text(stringResource(R.string.planning_budget_editor_discard))}},
        dismissButton={TextButton(onClick={discard=false}) {Text(stringResource(R.string.planning_budget_editor_keep_editing))}})
    action?.let {operation ->
        val title=when(operation) {"pause" -> R.string.planning_planning_pause_bill;"resume" -> R.string.planning_planning_resume_bill;else -> R.string.planning_planning_archive_bill}
        val message=when(operation) {"pause" -> R.string.planning_planning_pause_bill_message;"resume" -> R.string.planning_planning_resume_bill_message;else -> R.string.planning_planning_archived_bills_will_no_longer_appear_in}
        AlertDialog(onDismissRequest={if(!busy) action=null},title={Text(stringResource(title))},text={Text(stringResource(message))},
            confirmButton={TextButton(enabled=!busy,onClick={busy=true;error=null;scope.launch {
                val result=when(operation) {"pause" -> onPause(requireNotNull(bill).id);"resume" -> onResume(requireNotNull(bill).id);else -> onArchive(requireNotNull(bill).id)}
                busy=false;action=null;result.fold(onSuccess={onDismiss()},onFailure={error=if((it as? RecurringBillValidationException)?.reason==RecurringBillValidationError.UNPAID_CYCLES) R.string.planning_bill_archive_unpaid_cycles_message else when(operation) {"pause" -> R.string.planning_planning_couldn_t_pause_this_bill_right_now;"resume" -> R.string.planning_planning_couldn_t_resume_this_bill_right_now;else -> R.string.planning_planning_couldn_t_archive_this_bill_right_now}})
            }},modifier=Modifier.testTag("bill.confirmAction")) {Text(stringResource(title))}},dismissButton={TextButton(enabled=!busy,onClick={action=null}) {Text(stringResource(R.string.common_cancel))}})
    }
    if(picker in listOf("startDate","dueDate","autoDate")) {
        val value=when(picker) {"startDate" -> state.paymentStartDate;"dueDate" -> state.dueDate;else -> state.autoPayDate}
        val date=rememberDatePickerState(initialSelectedDateMillis=LocalDate.parse(value).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            selectableDates=object:SelectableDates {
                override fun isSelectableDate(utcTimeMillis:Long):Boolean {
                    if(picker!="autoDate") return true
                    val day=Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate()
                    val start=LocalDate.parse(state.paymentStartDate)
                    val rawEnd=LocalDate.parse(state.dueDate)
                    val end=if(state.hasDeadline && rawEnd>=start) rawEnd else start
                    return day in start..end
                }
            })
        DatePickerDialog(onDismissRequest={picker=null},confirmButton={TextButton(onClick={date.selectedDateMillis?.let {
            val selectedDate=Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()
            update(when(picker) {"startDate" -> state.withPaymentStartDate(selectedDate);"dueDate" -> state.copy(dueDate=selectedDate.toString());else -> state.copy(autoPayDate=selectedDate.toString())})
        };picker=null}) {Text(stringResource(R.string.common_save))}},dismissButton={TextButton(onClick={picker=null}) {Text(stringResource(R.string.common_cancel))}}) {DatePicker(date)}
    } else if(picker!=null) AlertDialog(onDismissRequest={picker=null},title={Text(stringResource(when(picker) {"category" -> R.string.planning_planning_payment_category;"wallet" -> R.string.planning_planning_payment_wallet;else -> R.string.planning_planning_payment_day}))},
        text={Column(Modifier.heightIn(max=400.dp).verticalScroll(rememberScrollState())) {
            when(picker) {
                "category" -> {
                    val active=categories.filter {it.ownerUserId==owner && it.deletedAt==null && !it.isArchived && it.kind==TransactionCategoryKind.EXPENSE && it.hierarchyRole==CategoryHierarchyRole.CHILD}
                    val byKey=active.groupBy {it.systemKey}.mapValues {(_,rows) -> rows.maxBy {Instant.parse(it.updatedAt)}}
                    val keys=listOf("rent","mortgage_installment","electricity","water","internet","phone","gas","condo_fee","public_transport","parking","tolls","fuel","vehicle_maintenance","vehicle_repair","child_tuition","childcare","health_insurance","insurance","vehicle_insurance","vehicle_registration","subscriptions","work_software_subscriptions","fitness_gym","banking_fees","loan_repayment","taxes_fees")
                    val quick=keys.mapNotNull {byKey[it]}
                    val choices=selected?.takeIf {it.kind==TransactionCategoryKind.EXPENSE && it.hierarchyRole==CategoryHierarchyRole.CHILD && it !in quick}?.let {listOf(it)+quick} ?: quick
                    choices.forEach {category -> Row(Modifier.fillMaxWidth().testTag("bill.category.${category.id}").clickable {state=state.copy(categoryId=category.id);picker=null}.padding(8.dp),verticalAlignment=Alignment.CenterVertically) {
                        CategoryIcon(category.iconSymbolName,category.kind,category.iconColorHex);Spacer(Modifier.width(8.dp));Text(category.localizedBudgetName(language))
                    }}
                }
                "wallet" -> wallets.filter {it.ownerUserId==owner && it.deletedAt==null && (!it.isArchived || it.id==bill?.paymentWalletId || it.id==state.paymentWalletId)}.forEach {wallet -> TextButton(onClick={state=state.copy(paymentWalletId=wallet.id);picker=null},modifier=Modifier.testTag("bill.wallet.${wallet.id}")) {Text(wallet.name)}}
                else -> (if(picker=="autoDay") state.autoPayDayOptions else (1..31).toList()).forEach {day -> TextButton(onClick={update(when(picker) {"startDay" -> state.copy(paymentStartDay=day);"dueDay" -> state.copy(dueDay=day);else -> state.copy(autoPayDay=day)});picker=null}) {
                    Text(stringResource(if(picker=="autoDay" && state.hasDeadline && state.dueDay<state.paymentStartDay && day<state.paymentStartDay) R.string.planning_planning_day_value_next_month else R.string.planning_planning_day_value,day.toString()))
                }}
            }
        }},confirmButton={TextButton(onClick={picker=null}) {Text(stringResource(R.string.common_close))}})
}

@Composable private fun BillPickerButton(label:Int,value:String,enabled:Boolean,tag:String,onClick:()->Unit) {
    TextButton(onClick=onClick,enabled=enabled,modifier=Modifier.fillMaxWidth().testTag(tag)) {Text(stringResource(label),Modifier.weight(1f));Text(value)}
}
private fun billError(error:Throwable):Int = when((error as? RecurringBillValidationException)?.reason) {
    RecurringBillValidationError.NAME_REQUIRED -> R.string.planning_planning_enter_a_bill_name_before_saving
    RecurringBillValidationError.CATEGORY_REQUIRED,RecurringBillValidationError.INVALID_CATEGORY -> R.string.planning_planning_choose_an_expense_child_category_for_this
    RecurringBillValidationError.WALLET_REQUIRED,RecurringBillValidationError.INVALID_WALLET -> R.string.planning_planning_choose_a_payment_wallet_for_this_bill
    RecurringBillValidationError.DEADLINE_BEFORE_START -> R.string.planning_planning_deadline_cannot_be_before_the_payment_date
    else -> R.string.planning_planning_couldn_t_save_this_bill_right_now
}
