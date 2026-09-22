package vn.com.quyln.mistia.feature.management

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.TrendingDown
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.MedicalServices
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.ShoppingBag
import androidx.compose.material.icons.filled.Work
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.util.Locale
import kotlinx.coroutines.launch
import vn.com.quyln.mistia.core.designsystem.MistiaGlassCard
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.CategoryDraft
import vn.com.quyln.mistia.core.model.CategoryHierarchyRole
import vn.com.quyln.mistia.core.model.CategoryNameLanguage
import vn.com.quyln.mistia.core.model.CategoryValidationError
import vn.com.quyln.mistia.core.model.CategoryValidationException
import vn.com.quyln.mistia.core.model.TransactionCategoryKind
import vn.com.quyln.mistia.core.model.TransactionCategoryRecord

data class CategoryEditorState(
    val id: String?,
    val name: String,
    val kind: TransactionCategoryKind,
    val hierarchyRole: CategoryHierarchyRole,
    val parentCategoryId: String?,
    val isFavorite: Boolean,
    val iconSymbolName: String,
    val iconColorHex: String,
    val iconWasCustomized: Boolean,
    val sortOrder: Int?,
) {
    fun selectKind(selected: TransactionCategoryKind): CategoryEditorState = copy(
        kind = selected,
        parentCategoryId = if (selected == kind) parentCategoryId else null,
        iconSymbolName = if (iconWasCustomized) iconSymbolName else selected.defaultIcon,
        iconColorHex = if (iconWasCustomized) iconColorHex else selected.defaultColorHex,
    )

    fun selectRole(selected: CategoryHierarchyRole): CategoryEditorState {
        if (id != null) return this
        return copy(
            hierarchyRole = selected,
            parentCategoryId = if (selected == CategoryHierarchyRole.PARENT) null else parentCategoryId,
            isFavorite = selected == CategoryHierarchyRole.CHILD && isFavorite,
        )
    }

    fun customizeIcon(symbolName: String, colorHex: String): CategoryEditorState = copy(
        iconSymbolName = symbolName,
        iconColorHex = colorHex,
        iconWasCustomized = true,
    )

    fun toDraft(language: CategoryNameLanguage): CategoryEditorDraftResult {
        if (name.isBlank()) return CategoryEditorDraftResult(validation = CategoryEditorValidation.NAME_REQUIRED)
        if (hierarchyRole == CategoryHierarchyRole.CHILD && parentCategoryId == null) {
            return CategoryEditorDraftResult(validation = CategoryEditorValidation.PARENT_REQUIRED)
        }
        return CategoryEditorDraftResult(
            draft = CategoryDraft(
                id = id,
                name = name,
                nameLanguage = language,
                kind = kind,
                hierarchyRole = hierarchyRole,
                parentCategoryId = parentCategoryId,
                isFavorite = hierarchyRole == CategoryHierarchyRole.CHILD && isFavorite,
                iconSymbolName = iconSymbolName,
                iconColorHex = iconColorHex,
                sortOrder = sortOrder,
            )
        )
    }

    companion object {
        fun new(
            kind: TransactionCategoryKind,
            role: CategoryHierarchyRole = CategoryHierarchyRole.PARENT,
            parentCategoryId: String? = null,
        ) = CategoryEditorState(
            id = null,
            name = "",
            kind = kind,
            hierarchyRole = role,
            parentCategoryId = parentCategoryId,
            isFavorite = false,
            iconSymbolName = kind.defaultIcon,
            iconColorHex = kind.defaultColorHex,
            iconWasCustomized = false,
            sortOrder = null,
        )

        fun edit(
            category: TransactionCategoryRecord,
            language: CategoryNameLanguage = CategoryNameLanguage.VIETNAMESE,
        ): CategoryEditorState {
            val kind = requireNotNull(category.kind) { "Unknown category kind cannot be edited" }
            return CategoryEditorState(
                id = category.id,
                name = categoryName(category, language),
                kind = kind,
                hierarchyRole = category.hierarchyRole,
                parentCategoryId = category.parentCategoryId,
                isFavorite = category.isFavorite,
                iconSymbolName = category.iconSymbolName,
                iconColorHex = category.iconColorHex,
                iconWasCustomized = category.iconSymbolName != kind.defaultIcon ||
                    !category.iconColorHex.equals(kind.defaultColorHex, ignoreCase = true),
                sortOrder = category.sortOrder,
            )
        }
    }
}

data class CategoryEditorDraftResult(
    val draft: CategoryDraft? = null,
    val validation: CategoryEditorValidation? = null,
)

enum class CategoryEditorValidation { NAME_REQUIRED, PARENT_REQUIRED }

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun CategoryEditorSheet(
    category: TransactionCategoryRecord?,
    initialKind: TransactionCategoryKind,
    initialRole: CategoryHierarchyRole,
    initialParentId: String?,
    parents: List<TransactionCategoryRecord>,
    language: CategoryNameLanguage,
    onDismiss: () -> Unit,
    onSave: suspend (CategoryDraft) -> Result<TransactionCategoryRecord>,
    onArchive: suspend () -> Result<Unit>,
) {
    var state by remember(category?.id, initialKind, initialRole, initialParentId) {
        mutableStateOf(
            category?.let { CategoryEditorState.edit(it, language) }
                ?: CategoryEditorState.new(initialKind, initialRole, initialParentId)
        )
    }
    var validation by remember { mutableStateOf<CategoryEditorValidation?>(null) }
    var operationError by remember { mutableStateOf<CategoryValidationError?>(null) }
    var genericFailure by remember { mutableStateOf(false) }
    var archiveConfirmation by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val iconCatalog = CategoryIconCatalog.load(LocalContext.current)
    val eligibleParents = parents.filter {
        it.id != state.id && it.kind == state.kind && it.hierarchyRole == CategoryHierarchyRole.PARENT
    }

    ModalBottomSheet(onDismissRequest = { if (!isSaving) onDismiss() }) {
        Column(
            modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onDismiss, enabled = !isSaving) {
                    Text(stringResource(R.string.common_cancel))
                }
                Text(
                    stringResource(
                        if (category == null) R.string.management_category_editor_new_title
                        else R.string.management_category_editor_edit_title
                    ),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                )
                Button(
                    enabled = !isSaving,
                    onClick = {
                        val result = state.toDraft(language)
                        validation = result.validation
                        operationError = null
                        genericFailure = false
                        val draft = result.draft ?: return@Button
                        isSaving = true
                        scope.launch {
                            onSave(draft).fold(
                                onSuccess = { onDismiss() },
                                onFailure = { error ->
                                    isSaving = false
                                    operationError = (error as? CategoryValidationException)?.reason
                                    genericFailure = operationError == null
                                },
                            )
                        }
                    },
                ) { Text(stringResource(R.string.common_save)) }
            }

            MistiaGlassCard { padding ->
                Column(Modifier.padding(padding), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        stringResource(R.string.management_management_identity),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CategoryIcon(state.iconSymbolName, state.kind, state.iconColorHex, Modifier.size(48.dp))
                        Text(
                            stringResource(R.string.management_management_choose_a_coordinated_finance_icon_for_this),
                            modifier = Modifier.padding(start = 12.dp),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        iconCatalog.options(state.kind).forEach { option ->
                            CategoryIcon(
                                option.token,
                                state.kind,
                                state.iconColorHex,
                                Modifier.size(42.dp)
                                    .then(
                                        if (option.token == state.iconSymbolName) {
                                            Modifier.border(2.dp, MaterialTheme.colorScheme.primary, CircleShape)
                                        } else Modifier
                                    )
                                    .clickable { state = state.customizeIcon(option.token, option.colorHex) },
                            )
                        }
                    }
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        CATEGORY_COLORS.forEach { color ->
                            Box(
                                Modifier.padding(vertical = 4.dp)
                                    .size(if (state.iconColorHex.equals(color, true)) 32.dp else 28.dp)
                                    .clip(CircleShape)
                                    .background(colorFromHex(color))
                                    .clickable { state = state.customizeIcon(state.iconSymbolName, color) }
                            )
                        }
                    }
                }
            }

            MistiaGlassCard { padding ->
                Column(Modifier.padding(padding), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        stringResource(R.string.management_management_basic_details),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    OutlinedTextField(
                        value = state.name,
                        onValueChange = { state = state.copy(name = it) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.management_management_category_name)) },
                        singleLine = true,
                    )
                    Text(stringResource(R.string.management_management_category_type), style = MaterialTheme.typography.labelLarge)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TransactionCategoryKind.entries.forEach { kind ->
                            FilterChip(
                                selected = state.kind == kind,
                                onClick = { state = state.selectKind(kind) },
                                label = { Text(categoryKindTitle(kind)) },
                            )
                        }
                    }
                }
            }

            MistiaGlassCard { padding ->
                Column(Modifier.padding(padding), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        stringResource(R.string.management_management_structure),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    if (category == null) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            CategoryHierarchyRole.entries.forEach { role ->
                                FilterChip(
                                    selected = state.hierarchyRole == role,
                                    onClick = { state = state.selectRole(role) },
                                    label = {
                                        Text(
                                            stringResource(
                                                if (role == CategoryHierarchyRole.PARENT) {
                                                    R.string.shared_corelogic_financeenums_parent_category
                                                } else R.string.shared_corelogic_financeenums_child_category
                                            )
                                        )
                                    },
                                )
                            }
                        }
                    } else {
                        Text(
                            stringResource(
                                if (state.hierarchyRole == CategoryHierarchyRole.PARENT) {
                                    R.string.shared_corelogic_financeenums_parent_category
                                } else R.string.shared_corelogic_financeenums_child_category
                            ),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (state.hierarchyRole == CategoryHierarchyRole.CHILD) {
                        Text(stringResource(R.string.management_management_choose_parent_category), style = MaterialTheme.typography.labelLarge)
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            eligibleParents.forEach { parent ->
                                FilterChip(
                                    selected = state.parentCategoryId == parent.id,
                                    onClick = { state = state.copy(parentCategoryId = parent.id) },
                                    label = { Text(categoryName(parent, language)) },
                                )
                            }
                        }
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(stringResource(R.string.management_management_mark_as_favorite))
                            Switch(
                                checked = state.isFavorite,
                                onCheckedChange = { state = state.copy(isFavorite = it) },
                            )
                        }
                    }
                }
            }

            validation?.let { Text(categoryEditorValidationMessage(it), color = MaterialTheme.colorScheme.error) }
            operationError?.let { Text(categoryOperationMessage(it), color = MaterialTheme.colorScheme.error) }
            if (genericFailure) {
                Text(
                    stringResource(R.string.management_management_couldn_t_save_this_category_right_now),
                    color = MaterialTheme.colorScheme.error,
                )
            }

            if (category != null) {
                HorizontalDivider()
                OutlinedButton(
                    onClick = { archiveConfirmation = true },
                    enabled = !isSaving,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        stringResource(R.string.management_management_archive_category),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
                Text(
                    stringResource(R.string.management_management_archived_categories_will_no_longer_appear_in),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.height(28.dp))
        }
    }

    if (archiveConfirmation) {
        AlertDialog(
            onDismissRequest = { archiveConfirmation = false },
            title = { Text(stringResource(R.string.management_management_archive_category)) },
            text = { Text(stringResource(R.string.management_management_this_category_will_be_archived_archived_categories)) },
            dismissButton = {
                TextButton(onClick = { archiveConfirmation = false }) { Text(stringResource(R.string.common_cancel)) }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        archiveConfirmation = false
                        operationError = null
                        genericFailure = false
                        isSaving = true
                        scope.launch {
                            onArchive().fold(
                                onSuccess = { onDismiss() },
                                onFailure = { error ->
                                    isSaving = false
                                    operationError = (error as? CategoryValidationException)?.reason
                                    genericFailure = operationError == null
                                },
                            )
                        }
                    },
                ) { Text(stringResource(R.string.common_archive), color = MaterialTheme.colorScheme.error) }
            },
        )
    }
}

@Composable
internal fun CategoryIcon(
    symbolName: String,
    kind: TransactionCategoryKind?,
    colorHex: String,
    modifier: Modifier = Modifier,
) {
    val iconCatalog = CategoryIconCatalog.load(LocalContext.current)
    Box(
        modifier = modifier.clip(CircleShape).background(colorFromHex(colorHex).copy(alpha = 0.18f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            categoryIcon(symbolName, kind, iconCatalog.option(symbolName)?.fallbackIcon),
            contentDescription = null,
            tint = colorFromHex(colorHex),
            modifier = Modifier.size(24.dp),
        )
    }
}

@Composable
internal fun categoryKindTitle(kind: TransactionCategoryKind): String = stringResource(
    if (kind == TransactionCategoryKind.EXPENSE) R.string.shared_corelogic_financeenums_expense
    else R.string.shared_corelogic_financeenums_income
)

internal fun currentCategoryLanguage(locale: Locale = Locale.getDefault()): CategoryNameLanguage = when (locale.language) {
    "vi" -> CategoryNameLanguage.VIETNAMESE
    "ja" -> CategoryNameLanguage.JAPANESE
    else -> CategoryNameLanguage.ENGLISH
}

internal fun categoryName(category: TransactionCategoryRecord, language: CategoryNameLanguage): String = when (language) {
    CategoryNameLanguage.VIETNAMESE -> category.name
    CategoryNameLanguage.ENGLISH -> category.nameEnglish?.takeIf(String::isNotBlank) ?: category.name
    CategoryNameLanguage.JAPANESE -> category.nameJapanese?.takeIf(String::isNotBlank) ?: category.name
}

@Composable
private fun categoryEditorValidationMessage(validation: CategoryEditorValidation): String = stringResource(
    when (validation) {
        CategoryEditorValidation.NAME_REQUIRED -> R.string.management_management_enter_a_category_name_before_saving
        CategoryEditorValidation.PARENT_REQUIRED -> R.string.management_management_choose_a_parent_category_for_this_child
    }
)

@Composable
private fun categoryOperationMessage(error: CategoryValidationError): String = stringResource(
    when (error) {
        CategoryValidationError.DUPLICATE_NAME -> R.string.management_management_category_name_already_exists
        CategoryValidationError.PARENT_REQUIRED,
        CategoryValidationError.PARENT_KIND_MISMATCH,
        CategoryValidationError.PARENT_NOT_PARENT,
        CategoryValidationError.PARENT_NOT_ACTIVE,
        CategoryValidationError.SELF_PARENT,
        -> R.string.management_management_choose_a_parent_category_for_this_child
        CategoryValidationError.ARCHIVE_HAS_CHILDREN -> R.string.management_management_category_archive_blocked_has_children
        CategoryValidationError.ARCHIVE_HAS_TRANSACTIONS -> R.string.management_management_category_archive_blocked_has_transactions
        CategoryValidationError.ARCHIVE_HAS_BUDGETS -> R.string.management_management_category_archive_blocked_has_budgets
        CategoryValidationError.ARCHIVE_HAS_BILLS -> R.string.management_management_category_archive_blocked_has_bills
        CategoryValidationError.BUDGET_BRANCH_CURRENT_MONTH_BLOCK ->
            R.string.management_management_category_budget_branch_current_month_block
        else -> R.string.management_management_couldn_t_save_this_category_right_now
    }
)

private fun categoryIcon(
    symbolName: String,
    kind: TransactionCategoryKind?,
    fallbackIcon: String?,
): ImageVector = when (symbolName) {
    "mistia.flow.expense" -> Icons.AutoMirrored.Filled.TrendingDown
    "mistia.flow.income" -> Icons.AutoMirrored.Filled.TrendingUp
    else -> when (categoryIconFamily(fallbackIcon, kind)) {
        CategoryIconFamily.FOOD -> Icons.Default.Restaurant
        CategoryIconFamily.HOME -> Icons.Default.Home
        CategoryIconFamily.TRANSPORT -> Icons.Default.DirectionsCar
        CategoryIconFamily.SHOPPING -> Icons.Default.ShoppingBag
        CategoryIconFamily.HEALTH -> Icons.Default.MedicalServices
        CategoryIconFamily.WORK -> Icons.Default.Work
        CategoryIconFamily.GIFT -> Icons.Default.CardGiftcard
        CategoryIconFamily.INCOME -> Icons.AutoMirrored.Filled.TrendingUp
        CategoryIconFamily.OTHER -> Icons.Default.MoreHoriz
    }
}

private val CATEGORY_COLORS = listOf(
    "#FF7A59",
    "#2DAA9E",
    "#5B7BFF",
    "#9B51E0",
    "#FF9F1C",
    "#6BCB77",
    "#EC407A",
    "#8A8A8E",
)
