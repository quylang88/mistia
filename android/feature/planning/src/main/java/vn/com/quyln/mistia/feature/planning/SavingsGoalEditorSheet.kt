package vn.com.quyln.mistia.feature.planning

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Calculate
import androidx.compose.ui.platform.LocalFocusManager
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
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.AmountCalculatorDialog
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun SavingsGoalEditorSheet(
    owner:String,goal:SavingsGoalRecord?,wallets:List<LedgerWalletRecord>,
    onSave:suspend (SavingsGoalDraft)->Result<SavingsGoalRecord>,
    onDelete:suspend (String)->Result<Unit>,onDismiss:()->Unit,
) {
    val zone=ZoneId.systemDefault()
    val initial=remember(owner,goal?.id) { goal?.let { SavingsGoalEditorState.from(it,zone) } ?: SavingsGoalEditorState.fresh(LocalDate.now(zone),"JPY") }
    var state by rememberSaveable(owner,goal?.id,stateSaver=SavingsGoalEditorState.saver(owner)) { mutableStateOf(initial) }
    var busy by remember { mutableStateOf(false) }
    var calculatorField by rememberSaveable(owner,goal?.id) { mutableStateOf<String?>(null) }
    var discard by remember { mutableStateOf(false) }
    var delete by remember { mutableStateOf(false) }
    var picker by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<Int?>(null) }
    val scope=rememberCoroutineScope()
    val changed=state!=initial
    fun close() { if(!busy) { if(changed) discard=true else onDismiss() } }
    val sheet=rememberModalBottomSheetState(skipPartiallyExpanded=true,confirmValueChange={
        if(it==SheetValue.Hidden && (changed || busy)) { if(!busy) discard=true;false } else true
    })
    ModalBottomSheet(onDismissRequest={close()},sheetState=sheet) {
        val focus=LocalFocusManager.current
        Column(Modifier.testTag("goal.editor").fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.CenterVertically) {
                Text(stringResource(if(goal==null) R.string.planning_planning_m_c_ti_u_m_i else R.string.planning_planning_s_a_m_c_ti_u),style=MaterialTheme.typography.titleLarge)
                TextButton(onClick={close()},enabled=!busy,modifier=Modifier.testTag("goal.close")) { Text(stringResource(R.string.common_close)) }
            }
            TextButton(onClick={focus.clearFocus();picker="icon"},enabled=!busy,modifier=Modifier.testTag("goal.icon")) {
                SavingsGoalIcon(state.iconSymbolName);Spacer(Modifier.width(12.dp));Text(stringResource(R.string.planning_planning_icon_m_c_ti_u))
            }
            OutlinedTextField(state.name,onValueChange={state=state.copy(name=it);error=null},label={Text(stringResource(R.string.planning_planning_goal_name))},enabled=!busy,modifier=Modifier.fillMaxWidth().testTag("goal.name"))
            OutlinedTextField(state.targetText,onValueChange={state=state.withTarget(it);error=null},label={Text(stringResource(R.string.planning_planning_target_amount))},suffix={Text(state.currencyCode)},
                trailingIcon={if(state.currencyCode in setOf("JPY","VND")) IconButton(enabled=!busy,onClick={focus.clearFocus();calculatorField="target"},modifier=Modifier.testTag("goal.target.calculator")) {
                    Icon(Icons.Filled.Calculate,contentDescription=stringResource(R.string.shared_amount_calculator_open_calculator))
                }},keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Decimal),enabled=!busy,modifier=Modifier.fillMaxWidth().testTag("goal.target"))
            OutlinedTextField(state.currentText,onValueChange={state=state.withCurrent(it);error=null},label={Text(stringResource(R.string.planning_planning_current_amount))},suffix={Text(state.currencyCode)},
                trailingIcon={if(state.currencyCode in setOf("JPY","VND")) IconButton(enabled=!busy,onClick={focus.clearFocus();calculatorField="current"},modifier=Modifier.testTag("goal.current.calculator")) {
                    Icon(Icons.Filled.Calculate,contentDescription=stringResource(R.string.shared_amount_calculator_open_calculator))
                }},keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Decimal),enabled=!busy,modifier=Modifier.fillMaxWidth().testTag("goal.current"))
            TextButton(onClick={focus.clearFocus();picker="date"},enabled=!busy,modifier=Modifier.fillMaxWidth().testTag("goal.date")) {
                Text(stringResource(R.string.planning_planning_target_date),Modifier.weight(1f));Text(LocalDate.parse(state.targetDate).format(java.time.format.DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.MEDIUM)))
            }
            TextButton(onClick={focus.clearFocus();picker="wallet"},enabled=!busy,modifier=Modifier.fillMaxWidth().testTag("goal.wallet")) {
                Text(stringResource(R.string.planning_planning_linked_wallet),Modifier.weight(1f))
                Text(wallets.firstOrNull { it.id==state.linkedWalletId && it.ownerUserId==owner }?.name ?: stringResource(R.string.planning_planning_not_linked))
            }
            error?.let { Text(stringResource(it),color=MaterialTheme.colorScheme.error) }
            Button(onClick={
                val draft=try { state.toDraft(zone) } catch(validation:Exception) {
                    error=when((validation as? SavingsGoalValidationException)?.reason) {
                        SavingsGoalValidationError.NAME_REQUIRED -> R.string.planning_planning_enter_a_goal_name_before_saving
                        SavingsGoalValidationError.INVALID_TARGET -> R.string.planning_planning_enter_a_target_amount_greater_than
                        else -> R.string.planning_goal_editor_invalid_amount
                    };return@Button
                }
                busy=true;error=null
                scope.launch { val result=onSave(draft);busy=false
                    result.fold(onSuccess={onDismiss()},onFailure={error=R.string.planning_planning_couldn_t_save_this_goal_right_now}) }
            },enabled=!busy,modifier=Modifier.fillMaxWidth().testTag("goal.save")) {
                if(busy) CircularProgressIndicator(Modifier.size(20.dp),strokeWidth=2.dp) else Text(stringResource(R.string.common_save))
            }
            if(goal!=null) TextButton(onClick={delete=true},enabled=!busy,modifier=Modifier.fillMaxWidth().testTag("goal.delete")) {
                Text(stringResource(R.string.planning_planning_delete_goal),color=MaterialTheme.colorScheme.error)
            }
            Spacer(Modifier.height(16.dp))
        }
    }
    calculatorField?.takeIf {it=="target" || it=="current"}?.let {field ->
        AmountCalculatorDialog(if(field=="target") state.targetText else state.currentText,"$owner:${goal?.id.orEmpty()}:${state.currencyCode}:$field",
            onCommit={state=if(field=="target") state.withTarget(it) else state.withCurrent(it);error=null},onDismiss={calculatorField=null})
    }
    if(discard) AlertDialog(onDismissRequest={discard=false},title={Text(stringResource(R.string.planning_budget_editor_discard_title))},text={Text(stringResource(R.string.planning_goal_editor_discard_message))},
        confirmButton={TextButton(onClick={discard=false;onDismiss()},modifier=Modifier.testTag("goal.discard")) { Text(stringResource(R.string.planning_budget_editor_discard)) }},
        dismissButton={TextButton(onClick={discard=false}) { Text(stringResource(R.string.planning_budget_editor_keep_editing)) }})
    if(delete) AlertDialog(onDismissRequest={delete=false},title={Text(stringResource(R.string.planning_planning_delete_this_goal))},
        confirmButton={TextButton(onClick={delete=false;busy=true;scope.launch { val result=onDelete(requireNotNull(goal).id);busy=false
            result.fold(onSuccess={onDismiss()},onFailure={error=R.string.planning_planning_couldn_t_delete_this_goal_right_now}) }},modifier=Modifier.testTag("goal.confirmDelete")) {Text(stringResource(R.string.common_delete))}},
        dismissButton={TextButton(onClick={delete=false}) {Text(stringResource(R.string.common_cancel))}})
    if(picker=="date") {
        val dateState=rememberDatePickerState(initialSelectedDateMillis=LocalDate.parse(state.targetDate).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(onDismissRequest={picker=null},confirmButton={TextButton(onClick={dateState.selectedDateMillis?.let { state=state.copy(targetDate=Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString()) };picker=null}) {Text(stringResource(R.string.common_save))}},dismissButton={TextButton(onClick={picker=null}) {Text(stringResource(R.string.common_cancel))}}) { DatePicker(dateState) }
    }
    if(picker=="wallet" || picker=="icon") AlertDialog(onDismissRequest={picker=null},title={Text(stringResource(if(picker=="wallet") R.string.planning_planning_linked_wallet else R.string.planning_planning_icon_m_c_ti_u))},
        text={Column(Modifier.heightIn(max=400.dp).verticalScroll(rememberScrollState())) {
            if(picker=="wallet") {
                TextButton(onClick={state=state.copy(linkedWalletId=null);picker=null}) {Text(stringResource(R.string.planning_planning_not_linked))}
                wallets.filter { it.ownerUserId==owner && it.deletedAt==null && (!it.isArchived || it.id==goal?.linkedWalletId) }
                    .sortedWith(compareBy(LedgerWalletRecord::sortOrder,LedgerWalletRecord::createdAt,LedgerWalletRecord::id)).forEach { wallet ->
                    Row(Modifier.fillMaxWidth().clickable { state=state.copy(linkedWalletId=wallet.id);picker=null }.padding(8.dp).testTag("goal.wallet.${wallet.id}"),verticalAlignment=Alignment.CenterVertically) {
                        RadioButton(state.linkedWalletId==wallet.id,onClick=null);Text(wallet.name)
                    }
                }
            } else goalIcons.forEach { (token,label,_) ->
                Row(Modifier.fillMaxWidth().clickable { state=state.copy(iconSymbolName=token);picker=null }.padding(8.dp),verticalAlignment=Alignment.CenterVertically) {
                    RadioButton(state.iconSymbolName==token,onClick=null);SavingsGoalIcon(token);Spacer(Modifier.width(8.dp));Text(stringResource(label))
                }
            }
        }},confirmButton={TextButton(onClick={picker=null}) {Text(stringResource(R.string.common_close))}})
}
