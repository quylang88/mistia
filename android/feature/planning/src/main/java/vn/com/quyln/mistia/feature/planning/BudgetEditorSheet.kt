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
import vn.com.quyln.mistia.core.designsystem.AmountCalculatorDialog
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import kotlinx.coroutines.launch
import vn.com.quyln.mistia.core.designsystem.CategoryIcon
import vn.com.quyln.mistia.core.designsystem.MistiaSectionCard
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BudgetEditorSheet(
    ownerId: String,
    plan: BudgetPlanRecord?,
    selectedMonth: YearMonth,
    categories: List<TransactionCategoryRecord>,
    plans: List<BudgetPlanRecord>,
    transactions: List<LedgerTransactionRecord>,
    language: CategoryNameLanguage,
    categoryMetadata: List<TransactionCategoryRecord> = categories,
    onSave: suspend (BudgetDraft) -> Result<BudgetPlanRecord>,
    onArchive: suspend (String) -> Result<Unit>,
    onDelete: suspend (String) -> Result<Unit>,
    onDismiss: () -> Unit,
) {
    val zone = ZoneId.systemDefault()
    val identity = remember(ownerId, categoryMetadata) { CategoryIdentityIndex(UserId(ownerId), categoryMetadata) }
    fun branchCurrency(category: TransactionCategoryRecord?): String? {
        val branchId = identity.logical(category?.parentCategoryId ?: category?.id) ?: return null
        return budgetCurrencyConstraints(UserId(ownerId), plans, selectedMonth, zone, categoryMetadata)
            .firstOrNull { it.logicalAllocation(identity).branchCategoryId == branchId }?.currencyCode
    }
    val initial = remember(ownerId, plan?.id, selectedMonth) { BudgetEditorState.from(plan, selectedMonth, zone) }
    var state by rememberSaveable(ownerId, plan?.id, selectedMonth.toString(), stateSaver = BudgetEditorState.scopedSaver(ownerId)) { mutableStateOf(initial) }
    var busy by remember { mutableStateOf(false) }
    var calculator by rememberSaveable(ownerId, plan?.id, selectedMonth) { mutableStateOf(false) }
    val focus = LocalFocusManager.current
    var discard by remember { mutableStateOf(false) }
    var destructive by remember { mutableStateOf<String?>(null) }
    var pickerMode by remember { mutableStateOf(0) }
    var pickerSearch by remember { mutableStateOf("") }
    var categoryPicker by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<BudgetValidationError?>(null) }
    var storageError by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val now = Instant.now()
    val readOnly = state.isReadOnly(now, zone)
    val changed = !readOnly && state != initial
    fun requestClose() { if (!busy) { if (changed) discard = true else onDismiss() } }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = {
        if (it == SheetValue.Hidden && (busy || changed)) { if (!busy) discard = true; false } else true
    })
    ModalBottomSheet(onDismissRequest = { requestClose() }, sheetState = sheetState) {
        Column(Modifier.testTag("budget.editor").fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(if (plan == null) R.string.planning_planning_ng_n_s_ch_m_i else R.string.planning_planning_s_a_ng_n_s_ch), style = MaterialTheme.typography.titleLarge)
                TextButton(onClick = { requestClose() }, enabled = !busy, modifier=Modifier.testTag("budget.close")) { Text(stringResource(R.string.common_close)) }
            }
            MistiaSectionCard(stringResource(R.string.planning_planning_budget)) {
                Text(selectedMonth.toString(), style = MaterialTheme.typography.labelLarge)
                val category = identity.category(state.categoryId)
                val parent = identity.category(category?.parentCategoryId)
                val livePath = category?.let { selected ->
                    parent?.let { "${it.localizedBudgetName(language)} / ${selected.localizedBudgetName(language)}" } ?: selected.localizedBudgetName(language)
                }
                val label = (if (identity.logical(state.categoryId) == identity.logical(plan?.categoryId)) plan?.localizedBudgetPath(language) else null)
                    ?: livePath ?: stringResource(R.string.planning_planning_choose_category)
                TextButton(onClick = { categoryPicker = true }, enabled = !readOnly && !busy, modifier = Modifier.fillMaxWidth().testTag("budget.category")) {
                    Text(label, modifier = Modifier.weight(1f))
                }
                OutlinedTextField(state.amountText, onValueChange = { state = state.withAmount(it); error = null; storageError = false },
                    label = { Text(stringResource(R.string.planning_planning_budget_amount)) }, suffix = { Text(state.currencyCode) },
                    trailingIcon = { if (state.currencyCode in setOf("JPY", "VND")) IconButton(enabled = !readOnly && !busy,
                        onClick = { focus.clearFocus(); calculator = true }, modifier = Modifier.testTag("budget.amount.calculator")) {
                        Icon(Icons.Filled.Calculate, contentDescription = stringResource(R.string.shared_amount_calculator_open_calculator))
                    } },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), enabled = !readOnly && !busy, modifier = Modifier.fillMaxWidth().testTag("budget.amount"))
                if (state.id == null) {
                    val branchCurrency = branchCurrency(category)
                    Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                        listOf("JPY","VND").forEach { code -> FilterChip(selected=state.currencyCode==code,
                            enabled=!busy && (branchCurrency==null || branchCurrency==code),
                            onClick={ if(state.currencyCode!=code) state=state.copy(currencyCode=code,amountText="") },label={Text(code)}) }
                    }
                }
                Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {
                    Text(stringResource(R.string.planning_planning_cycle))
                    Text(stringResource(R.string.planning_planning_monthly))
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.planning_planning_rollover))
                    Switch(state.rolloverEnabled, onCheckedChange = { state = state.copy(rolloverEnabled = it) }, enabled = !readOnly && !busy)
                }
            }
            if (readOnly) Text(stringResource(R.string.planning_planning_past_budget_read_only_reference), style = MaterialTheme.typography.bodySmall)
            if (error != null || storageError) Text(stringResource(when (error) {
                BudgetValidationError.BRANCH_CURRENCY_MISMATCH -> R.string.planning_budget_editor_branch_currency_mismatch
                BudgetValidationError.CATEGORY_REQUIRED, BudgetValidationError.INVALID_CATEGORY -> R.string.planning_planning_choose_a_category_before_saving
                BudgetValidationError.INVALID_AMOUNT, BudgetValidationError.AMOUNT_OVERFLOW -> R.string.planning_budget_editor_invalid_amount
                BudgetValidationError.DUPLICATE_CATEGORY -> R.string.planning_planning_this_category_already_has_a_budget_in
                BudgetValidationError.PAST_READ_ONLY -> R.string.planning_planning_past_budget_read_only_reference
                else -> R.string.planning_planning_couldn_t_save_this_budget_right_now
            }), color = MaterialTheme.colorScheme.error)
            Button(onClick = {
                val draft = try { state.toDraft(zone) } catch (validation: BudgetValidationException) { error = validation.reason; return@Button }
                busy = true; error = null; storageError = false
                scope.launch {
                    val result = onSave(draft)
                    busy = false
                    result.fold(onSuccess = { onDismiss() }, onFailure = { error = (it as? BudgetValidationException)?.reason; storageError = true })
                }
            }, enabled = !readOnly && !busy, modifier = Modifier.fillMaxWidth().testTag("budget.save")) {
                if (busy) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                else Text(stringResource(R.string.common_save))
            }
            if (state.canArchive(now, zone) || state.canDelete(now, zone)) TextButton(
                onClick = { destructive = if (state.canArchive(now, zone)) "archive" else "delete" }, enabled = !busy, modifier = Modifier.fillMaxWidth().testTag("budget.destructive")) {
                Text(stringResource(if (state.canArchive(now, zone)) R.string.planning_planning_archive_budget else R.string.planning_planning_delete_budget), color = MaterialTheme.colorScheme.error)
            }
            Spacer(Modifier.height(16.dp))
        }
    }
    fun selectCategory(category: TransactionCategoryRecord) {
        val branchCurrency = branchCurrency(category)
        state = state.selectCategory(category.id, branchCurrency)
        categoryPicker = false
    }
    if (categoryPicker) AlertDialog(onDismissRequest = { categoryPicker = false },
        title = { Text(stringResource(R.string.planning_planning_choose_category)) },
        text = {
            val allowed = categories.filter { it.ownerUserId == ownerId && it.kind == TransactionCategoryKind.EXPENSE && it.deletedAt == null && !it.isBalanceAdjustmentSystemCategory &&
                (!it.isArchived || identity.logical(it.id) == identity.logical(plan?.categoryId) || identity.logical(it.id) == identity.logical(plan?.categoryParentIdSnapshot) || identity.logical(it.id) == identity.logical(identity.category(plan?.categoryId)?.parentCategoryId)) }
            Column(Modifier.heightIn(max=440.dp)) {
                Row(horizontalArrangement=Arrangement.spacedBy(4.dp)) {
                    listOf(R.string.core_ui_mistiacategorypicker_all,R.string.core_ui_mistiacategorypicker_recent,R.string.core_ui_mistiacategorypicker_favorites).forEachIndexed { index,title ->
                        FilterChip(selected=pickerMode==index,onClick={pickerMode=index},label={Text(stringResource(title))})
                    }
                }
                OutlinedTextField(pickerSearch,onValueChange={pickerSearch=it},label={Text(stringResource(R.string.core_ui_mistiacategorypicker_search_categories))},modifier=Modifier.fillMaxWidth())
                Column(Modifier.weight(1f,false).verticalScroll(rememberScrollState())) {
                    if (pickerMode==0) {
                        allowed.filter { it.hierarchyRole==CategoryHierarchyRole.PARENT }.forEach { parent ->
                            val children=allowed.filter { identity.logical(it.parentCategoryId)==identity.logical(parent.id) }
                            if (pickerSearch.isBlank() || parent.localizedBudgetName(language).contains(pickerSearch,true) || children.any { it.localizedBudgetName(language).contains(pickerSearch,true) }) {
                                BudgetCategoryChoice(parent,language,false,identity.logical(parent.id)==identity.logical(state.categoryId)) { selectCategory(parent) }
                                children.filter { pickerSearch.isBlank() || it.localizedBudgetName(language).contains(pickerSearch,true) || parent.localizedBudgetName(language).contains(pickerSearch,true) }.forEach { child ->
                                    BudgetCategoryChoice(child,language,true,identity.logical(child.id)==identity.logical(state.categoryId)) { selectCategory(child) }
                                }
                            }
                        }
                    } else {
                        val quick=budgetQuickCategories(UserId(ownerId),allowed,transactions,pickerMode==2,now,zone)
                            .filter { it.localizedBudgetName(language).contains(pickerSearch,true) }
                        if(quick.isEmpty()) Text(stringResource(if(pickerMode==2) R.string.core_ui_mistiacategorypicker_no_favorite_categories_yet else R.string.core_ui_mistiacategorypicker_no_recent_categories_yet))
                        quick.forEach { category -> BudgetCategoryChoice(category,language,false,identity.logical(category.id)==identity.logical(state.categoryId)) { selectCategory(category) } }
                    }
                }
            }
        }, confirmButton = { TextButton(onClick = { categoryPicker = false }) { Text(stringResource(R.string.common_close)) } })
    if (calculator && !readOnly) AmountCalculatorDialog(state.amountText, "$ownerId:${plan?.id.orEmpty()}:$selectedMonth:${state.currencyCode}",
        onCommit = { state = state.withAmount(it); error = null; storageError = false }, onDismiss = { calculator = false })
    if (discard) AlertDialog(onDismissRequest = { discard = false }, title = { Text(stringResource(R.string.planning_budget_editor_discard_title)) },
        text = { Text(stringResource(R.string.planning_budget_editor_discard_message)) },
        confirmButton = { TextButton(onClick = { discard = false; onDismiss() },modifier=Modifier.testTag("budget.discard")) { Text(stringResource(R.string.planning_budget_editor_discard)) } },
        dismissButton = { TextButton(onClick = { discard = false }) { Text(stringResource(R.string.planning_budget_editor_keep_editing)) } })
    if (destructive != null) {
        val archive = destructive == "archive"
        AlertDialog(onDismissRequest = { if (!busy) destructive = null }, title = { Text(stringResource(if (archive) R.string.planning_planning_archive_budget else R.string.planning_planning_delete_budget)) },
            text = { Text(stringResource(if (archive) R.string.planning_planning_this_budget_will_be_archived_archived_budgets else if (YearMonth.parse(state.selectedMonth) == YearMonth.from(now.atZone(zone))) R.string.planning_planning_delete_current_budget_message else R.string.planning_planning_delete_budget_message)) },
            confirmButton = { TextButton(onClick = {
                val id = state.id ?: return@TextButton
                busy = true
                scope.launch {
                    val result = if (archive) onArchive(id) else onDelete(id)
                    busy = false; destructive = null
                    result.fold(onSuccess = { onDismiss() }, onFailure = { storageError = true; error = (it as? BudgetValidationException)?.reason })
                }
            }, enabled = !busy,modifier=Modifier.testTag("budget.confirmDestructive")) { Text(stringResource(if (archive) R.string.common_archive else R.string.common_delete)) } },
            dismissButton = { TextButton(onClick = { destructive = null }, enabled = !busy) { Text(stringResource(R.string.common_cancel)) } })
    }
}

@Composable
private fun BudgetCategoryChoice(category: TransactionCategoryRecord, language: CategoryNameLanguage, child: Boolean, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.testTag("budget.category.${category.id}").fillMaxWidth().clickable(onClick = onClick).padding(start = if (child) 24.dp else 0.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        CategoryIcon(category.iconSymbolName, category.kind, category.iconColorHex, Modifier.size(36.dp))
        Text(category.localizedBudgetName(language), modifier = Modifier.weight(1f))
        RadioButton(selected = selected, onClick = null)
    }
}
