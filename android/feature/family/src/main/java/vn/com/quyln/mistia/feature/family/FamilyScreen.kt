package vn.com.quyln.mistia.feature.family

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import vn.com.quyln.mistia.core.designsystem.MistiaGlassCard
import vn.com.quyln.mistia.core.designsystem.MistiaRecordRow
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.string
import vn.com.quyln.mistia.core.model.FamilyRepository
import vn.com.quyln.mistia.core.model.UserId

@Composable
fun FamilyScreen(
    ownerUserId: UserId,
    repository: FamilyRepository,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val rows by repository.observeFamilyRows(ownerUserId).collectAsStateWithLifecycle(emptyList())
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            IconButton(onClick = onBack) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = stringResource(R.string.common_close),
                )
            }
            Text(stringResource(R.string.family_family_family), style = MaterialTheme.typography.headlineMedium)
        }
        if (rows.isEmpty()) {
            item {
                MistiaGlassCard { padding ->
                    Text(
                        stringResource(R.string.family_family_family_is_waiting_for_the_connection),
                        modifier = Modifier.padding(padding),
                    )
                }
            }
        } else {
            items(rows, key = { "${it.entity}:${it.id}" }) { row ->
                MistiaGlassCard { padding ->
                    MistiaRecordRow(
                        title = row.string("family_name")
                            ?: row.string("display_name")
                            ?: stringResource(R.string.family_family_member),
                        subtitle = row.string("role") ?: row.string("status"),
                        modifier = Modifier.padding(padding),
                    )
                }
            }
        }
    }
}
