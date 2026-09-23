package vn.com.quyln.mistia.feature.management

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.FilterChip
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
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.time.Instant
import kotlinx.coroutines.launch
import vn.com.quyln.mistia.core.designsystem.MistiaGlassCard
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.CategoryDraft
import vn.com.quyln.mistia.core.model.CategoryHierarchyRole
import vn.com.quyln.mistia.core.model.CategoryNameLanguage
import vn.com.quyln.mistia.core.model.FinanceRepository
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.RecordId
import vn.com.quyln.mistia.core.model.TransactionCategoryKind
import vn.com.quyln.mistia.core.model.TransactionCategoryRecord
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.WalletDraft

@Composable
fun ManagementScreen(
    ownerUserId: UserId,
    repository: FinanceRepository,
    deviceIdProvider: suspend () -> String,
    onTranslatePendingCategories: suspend () -> Unit,
    onSyncNow: () -> Unit,
    onSignOut: () -> Unit,
    onOpenFamily: () -> Unit,
    onOpenInvestment: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val wallets by repository.observeWallets(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val categories by repository.observeCategories(ownerUserId).collectAsStateWithLifecycle(emptyList())
    var walletEditorTarget by remember { mutableStateOf<WalletEditorTarget?>(null) }
    var categoryEditorTarget by remember { mutableStateOf<CategoryEditorTarget?>(null) }
    var selectedCategoryKind by remember { mutableStateOf(TransactionCategoryKind.EXPENSE) }
    val categoryLanguage = currentCategoryLanguage(LocalConfiguration.current.locales[0])
    val screenScope = rememberCoroutineScope()
    androidx.compose.runtime.LaunchedEffect(ownerUserId.value) {
        onTranslatePendingCategories()
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        item {
            Text(
                stringResource(R.string.app_roottab_manage),
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
            )
        }
        item {
            WalletsSection(
                wallets = wallets,
                onAdd = { walletEditorTarget = WalletEditorTarget(null) },
                onEdit = { walletEditorTarget = WalletEditorTarget(it.id) },
            )
        }
        item {
            CategoriesSection(
                categories = categories,
                selectedKind = selectedCategoryKind,
                language = categoryLanguage,
                onSelectKind = { selectedCategoryKind = it },
                onAddParent = {
                    categoryEditorTarget = CategoryEditorTarget(
                        categoryId = null,
                        kind = selectedCategoryKind,
                        role = CategoryHierarchyRole.PARENT,
                    )
                },
                onAddChild = { parent ->
                    categoryEditorTarget = CategoryEditorTarget(
                        categoryId = null,
                        kind = selectedCategoryKind,
                        role = CategoryHierarchyRole.CHILD,
                        parentId = parent.id,
                    )
                },
                onEdit = { category ->
                    categoryEditorTarget = CategoryEditorTarget(
                        categoryId = category.id,
                        kind = requireNotNull(category.kind),
                        role = category.hierarchyRole,
                        parentId = category.parentCategoryId,
                    )
                },
                onFavorite = { category, favorite ->
                    repository.setCategoryFavorite(
                        ownerUserId,
                        RecordId(category.id),
                        favorite,
                        deviceIdProvider(),
                        Instant.now().toString(),
                    )
                },
            )
        }
        item {
            OutlinedButton(onClick = onOpenFamily, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.family_family_family))
            }
        }
        item {
            OutlinedButton(onClick = onOpenInvestment, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.investment_title))
            }
        }
        item {
            Button(onClick = onSyncNow, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.management_managementauth_sync_now))
            }
        }
        item {
            OutlinedButton(onClick = onSignOut, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.management_managementauth_sign_out_this_device))
            }
        }
        item { Spacer(Modifier.height(92.dp)) }
    }

    walletEditorTarget?.let { target ->
        val wallet = target.walletId?.let { id -> wallets.firstOrNull { it.id == id } }
        WalletEditorSheet(
            wallet = wallet,
            nextSortOrder = (wallets.maxOfOrNull(LedgerWalletRecord::sortOrder) ?: -1) + 1,
            onDismiss = { walletEditorTarget = null },
            onSave = { draft: WalletDraft ->
                repository.saveWallet(
                    ownerUserId = ownerUserId,
                    draft = draft,
                    deviceId = deviceIdProvider(),
                    now = Instant.now().toString(),
                )
            },
            onArchive = archive@{
                val id = target.walletId
                    ?: return@archive Result.failure(IllegalStateException("Wallet ID is missing"))
                repository.archiveWallet(
                    ownerUserId = ownerUserId,
                    walletId = RecordId(id),
                    deviceId = deviceIdProvider(),
                    now = Instant.now().toString(),
                )
            },
        )
    }

    categoryEditorTarget?.let { target ->
        val category = target.categoryId?.let { id -> categories.firstOrNull { it.id == id } }
        val parents = categories.filter { it.hierarchyRole == CategoryHierarchyRole.PARENT }
        CategoryEditorSheet(
            category = category,
            initialKind = target.kind,
            initialRole = target.role,
            initialParentId = target.parentId,
            parents = parents,
            language = categoryLanguage,
            onDismiss = { categoryEditorTarget = null },
            onSave = { draft: CategoryDraft ->
                val result = repository.saveCategory(
                    ownerUserId = ownerUserId,
                    draft = draft,
                    deviceId = deviceIdProvider(),
                    now = Instant.now().toString(),
                )
                if (result.isSuccess) {
                    screenScope.launch { onTranslatePendingCategories() }
                }
                result
            },
            onArchive = archive@{
                val id = target.categoryId
                    ?: return@archive Result.failure(IllegalStateException("Category ID is missing"))
                repository.archiveCategory(
                    ownerUserId = ownerUserId,
                    categoryId = RecordId(id),
                    deviceId = deviceIdProvider(),
                    now = Instant.now().toString(),
                )
            },
        )
    }
}

@Composable
private fun CategoriesSection(
    categories: List<TransactionCategoryRecord>,
    selectedKind: TransactionCategoryKind,
    language: CategoryNameLanguage,
    onSelectKind: (TransactionCategoryKind) -> Unit,
    onAddParent: () -> Unit,
    onAddChild: (TransactionCategoryRecord) -> Unit,
    onEdit: (TransactionCategoryRecord) -> Unit,
    onFavorite: suspend (TransactionCategoryRecord, Boolean) -> Result<Unit>,
) {
    var expandedIds by remember { mutableStateOf<Set<String>>(emptySet()) }
    var favoriteFailed by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val hierarchy = visibleCategoryHierarchy(categories, selectedKind)
    val parents = hierarchy.parents
    val children = hierarchy.children

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                stringResource(R.string.management_management_categories2),
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.SemiBold,
            )
            TextButton(onClick = onAddParent) {
                Icon(Icons.Default.Add, contentDescription = null)
                Text(stringResource(R.string.management_management_add_parent_category))
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TransactionCategoryKind.entries.forEach { kind ->
                FilterChip(
                    selected = selectedKind == kind,
                    onClick = { onSelectKind(kind) },
                    label = { Text(categoryKindTitle(kind)) },
                )
            }
        }
        MistiaGlassCard(contentPadding = PaddingValues(0.dp)) { _ ->
            if (parents.isEmpty()) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(22.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(
                        stringResource(
                            if (selectedKind == TransactionCategoryKind.EXPENSE) {
                                R.string.management_management_no_expense_categories_yet
                            } else R.string.management_management_no_income_categories_yet
                        ),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        stringResource(
                            if (selectedKind == TransactionCategoryKind.EXPENSE) {
                                R.string.management_management_create_expense_groups_so_your_transactions_and
                            } else R.string.management_management_separate_your_income_sources_to_clearly_track
                        ),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Button(onClick = onAddParent) {
                        Icon(Icons.Default.Add, contentDescription = null)
                        Text(stringResource(R.string.management_management_add_parent_category))
                    }
                }
            } else {
                Column {
                    parents.forEachIndexed { parentIndex, parent ->
                        val branchChildren = children.filter { it.parentCategoryId == parent.id }
                        val expanded = parent.id in expandedIds
                        CategoryParentRow(
                            parent = parent,
                            childCount = branchChildren.size,
                            expanded = expanded,
                            language = language,
                            onToggle = {
                                expandedIds = if (expanded) expandedIds - parent.id else expandedIds + parent.id
                            },
                            onEdit = { onEdit(parent) },
                        )
                        if (expanded) {
                            if (branchChildren.isEmpty()) {
                                Text(
                                    stringResource(R.string.management_management_there_are_no_child_categories_in_this),
                                    modifier = Modifier.padding(start = 72.dp, end = 16.dp, bottom = 8.dp),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            } else {
                                branchChildren.forEach { child ->
                                    CategoryChildRow(
                                        child = child,
                                        language = language,
                                        onEdit = { onEdit(child) },
                                        onFavorite = { favorite ->
                                            scope.launch {
                                                favoriteFailed = onFavorite(child, favorite).isFailure
                                            }
                                        },
                                    )
                                }
                            }
                            TextButton(
                                onClick = { onAddChild(parent) },
                                modifier = Modifier.fillMaxWidth().padding(start = 52.dp),
                            ) {
                                Icon(Icons.Default.Add, contentDescription = null)
                                Text(stringResource(R.string.management_management_add_child_category))
                            }
                        }
                        if (parentIndex != parents.lastIndex) HorizontalDivider(modifier = Modifier.padding(start = 72.dp))
                    }
                    HorizontalDivider(modifier = Modifier.padding(start = 72.dp))
                    TextButton(
                        onClick = onAddParent,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                    ) {
                        Icon(Icons.Default.Add, contentDescription = null)
                        Text(stringResource(R.string.management_management_add_parent_category))
                    }
                }
            }
        }
        if (favoriteFailed) {
            Text(
                stringResource(R.string.management_management_couldn_t_update_favorite),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

internal data class CategoryHierarchyRows(
    val parents: List<TransactionCategoryRecord>,
    val children: List<TransactionCategoryRecord>,
)

internal fun visibleCategoryHierarchy(
    categories: List<TransactionCategoryRecord>,
    kind: TransactionCategoryKind,
): CategoryHierarchyRows {
    val children = categories.filter {
        it.kind == kind &&
            it.hierarchyRole == CategoryHierarchyRole.CHILD &&
            !it.isBalanceAdjustmentSystemCategory
    }
    val parents = categories.filter {
        it.kind == kind &&
            it.hierarchyRole == CategoryHierarchyRole.PARENT &&
            (!it.hidesWhenEmpty || children.any { child -> child.parentCategoryId == it.id })
    }
    return CategoryHierarchyRows(parents, children)
}

@Composable
private fun CategoryParentRow(
    parent: TransactionCategoryRecord,
    childCount: Int,
    expanded: Boolean,
    language: CategoryNameLanguage,
    onToggle: () -> Unit,
    onEdit: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onToggle) {
            Icon(if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore, contentDescription = null)
        }
        CategoryIcon(parent.iconSymbolName, parent.kind, parent.iconColorHex, Modifier.size(42.dp))
        Column(
            modifier = Modifier.weight(1f).clickable(onClick = onToggle).padding(horizontal = 12.dp, vertical = 8.dp)
        ) {
            Text(categoryName(parent, language), fontWeight = FontWeight.SemiBold)
            Text(
                stringResource(R.string.management_management_value_child_categories, childCount),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        TextButton(onClick = onEdit) { Text(stringResource(R.string.management_management_edit)) }
    }
}

@Composable
private fun CategoryChildRow(
    child: TransactionCategoryRecord,
    language: CategoryNameLanguage,
    onEdit: () -> Unit,
    onFavorite: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onEdit).padding(start = 66.dp, end = 8.dp, top = 7.dp, bottom = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CategoryIcon(child.iconSymbolName, child.kind, child.iconColorHex, Modifier.size(38.dp))
        Text(
            categoryName(child, language),
            modifier = Modifier.weight(1f).padding(horizontal = 12.dp),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        IconButton(onClick = { onFavorite(!child.isFavorite) }) {
            Icon(
                if (child.isFavorite) Icons.Default.Star else Icons.Default.StarBorder,
                contentDescription = stringResource(
                    if (child.isFavorite) R.string.management_management_remove_favorite
                    else R.string.management_management_mark_as_favorite
                ),
                tint = if (child.isFavorite) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Icon(Icons.Default.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun WalletsSection(
    wallets: List<LedgerWalletRecord>,
    onAdd: () -> Unit,
    onEdit: (LedgerWalletRecord) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                stringResource(R.string.management_management_wallets),
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.SemiBold,
            )
            TextButton(onClick = onAdd) {
                Icon(Icons.Default.Add, contentDescription = null)
                Text(stringResource(R.string.management_management_add_wallet))
            }
        }

        MistiaGlassCard(contentPadding = PaddingValues(0.dp)) { _ ->
            if (wallets.isEmpty()) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(22.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(
                        stringResource(R.string.management_management_no_wallets_yet),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        stringResource(R.string.management_management_add_cash_pay_pay_bank_or_credit_card),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Button(onClick = onAdd) {
                        Icon(Icons.Default.Add, contentDescription = null)
                        Text(stringResource(R.string.management_management_add_wallet))
                    }
                }
            } else {
                Column {
                    wallets.forEachIndexed { index, wallet ->
                        WalletRow(wallet = wallet, onClick = { onEdit(wallet) })
                        if (index != wallets.lastIndex) {
                            HorizontalDivider(modifier = Modifier.padding(start = 72.dp))
                        }
                    }
                    HorizontalDivider(modifier = Modifier.padding(start = 72.dp))
                    TextButton(
                        onClick = onAdd,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                    ) {
                        Icon(Icons.Default.Add, contentDescription = null)
                        Text(stringResource(R.string.management_management_add_wallet))
                    }
                }
            }
        }
    }
}

@Composable
private fun WalletRow(wallet: LedgerWalletRecord, onClick: () -> Unit) {
    val editable = wallet.kind in WalletEditorState.supportedKinds
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = editable, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        WalletIcon(wallet.iconSymbolName, wallet.kind, wallet.iconColorHex, Modifier.size(44.dp))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                wallet.name,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                wallet.kind?.let { walletKindTitle(it) } ?: wallet.kindWireValue,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(
                formatMinorUnits(wallet.openingBalanceMinor, wallet.currencyCode),
                style = MaterialTheme.typography.labelLarge,
            )
            if (editable) {
                Icon(
                    Icons.Default.ChevronRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private data class WalletEditorTarget(val walletId: String?)
private data class CategoryEditorTarget(
    val categoryId: String?,
    val kind: TransactionCategoryKind,
    val role: CategoryHierarchyRole,
    val parentId: String? = null,
)
