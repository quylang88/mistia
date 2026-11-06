package vn.com.quyln.mistia.feature.planning

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.com.quyln.mistia.core.designsystem.MistiaGlassCard
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

internal fun LazyListScope.planningCreditCardContent(owner: UserId, load: PlanningCreditCardLoad, onRetry: () -> Unit,
    onAdd: () -> Unit, onEdit: (String) -> Unit, onOpenStatement: (String) -> Unit) {
    when (val state = load.forOwner(owner)) {
        is PlanningCreditCardLoad.Loading -> item("cards-loading-${owner.value}") {
            Row(Modifier.fillMaxWidth().padding(24.dp).testTag("planning.cards.loading"),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                CircularProgressIndicator(Modifier.size(24.dp))
                Text(stringResource(R.string.app_mistia_loading_your_data))
            }
        }
        is PlanningCreditCardLoad.Failed -> item("cards-error-${owner.value}") {
            MistiaGlassCard(Modifier.testTag("planning.cards.error")) { _ ->
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(stringResource(R.string.planning_card_accounts_load_failed))
                    TextButton(onClick = onRetry, modifier = Modifier.testTag("planning.cards.retry")) { Text(stringResource(R.string.planning_installment_retry)) }
                }
            }
        }
        is PlanningCreditCardLoad.Loaded -> {
            if (state.accounts.isEmpty()) item("cards-empty-${owner.value}") {
                MistiaGlassCard(Modifier.testTag("planning.cards.empty")) { _ ->
                    Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            listOf(Icons.Default.CreditCard, Icons.Default.Contactless, Icons.Default.AccountBalance, Icons.Default.Add).forEach {
                                Icon(it, null, Modifier.size(42.dp).background(Color(0xFF9A67FF).copy(alpha = .12f), CircleShape).padding(10.dp), tint = Color(0xFF9A67FF))
                            }
                        }
                        Text(stringResource(R.string.planning_planning_no_credit_cards_yet), style = MaterialTheme.typography.titleMedium)
                        Text(stringResource(R.string.planning_planning_link_or_add_cards_here_to_show), style = MaterialTheme.typography.bodyMedium)
                        PlanningAddCardButton(onAdd)
                    }
                }
            } else {
                items(state.accounts, key = { "planning-card-${owner.value}-${it.wallet.id}" }) { card ->
                    PlanningCreditCardCard(card, onEdit = { onEdit(card.wallet.id) }, onOpenStatement = { onOpenStatement(card.wallet.id) })
                }
                item("cards-add-${owner.value}") { PlanningAddCardButton(onAdd) }
            }
        }
    }
}

@Composable private fun PlanningAddCardButton(onAdd: () -> Unit) {
    Button(onClick = onAdd, modifier = Modifier.fillMaxWidth().testTag("planning.card.add")) {
        Icon(Icons.Default.Add, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.planning_planning_add_credit_card))
    }
}

@Composable private fun PlanningCreditCardCard(card: PlanningCreditCardAccount, onEdit: () -> Unit, onOpenStatement: () -> Unit) {
    val dark = MaterialTheme.colorScheme.background.luminance() < .5f
    val locale = LocalConfiguration.current.locales[0]
    val networkName = if (card.network == CreditCardNetwork.OTHER) stringResource(R.string.shared_corelogic_financeenums_other_wallet) else planningCreditCardNetworkName(card.network)
    val issuer = card.profile.issuerName.trim().ifEmpty { networkName }.uppercase(locale)
    val linked = card.paymentSourceWalletName?.let { stringResource(R.string.planning_planning_linked_wallet_value, it) }
        ?: stringResource(R.string.planning_planning_no_linked_wallet)
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().heightIn(min = maxWidth / 1.586f).clip(RoundedCornerShape(24.dp))
            .background(Brush.linearGradient(planningCreditCardColors(card.network)))
            .border(.8.dp, Color.White.copy(alpha = .12f), RoundedCornerShape(24.dp))
            .testTag("planning.card.${card.wallet.id}").clickable(onClick = onEdit)) {
            Box(Modifier.align(Alignment.BottomStart).offset(x = (-48).dp, y = 50.dp).size(150.dp)
                .blur(28.dp, edgeTreatment = BlurredEdgeTreatment.Unbounded).background(Color.White.copy(alpha = if (dark) .08f else .14f), CircleShape))
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(card.wallet.name, fontSize = 15.sp, lineHeight = 18.sp, fontWeight = FontWeight.Bold, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(issuer, fontSize = 10.5.sp, lineHeight = 13.sp, fontWeight = FontWeight.Black, color = Color.White.copy(alpha = .7f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(7.dp)) {
                        PlanningCreditCardNetworkMark(card.network, networkName, Modifier.testTag("planning.card.network.${card.wallet.id}"))
                        Text("•••• ${card.last4}", fontSize = 12.sp, lineHeight = 14.sp, fontWeight = FontWeight.Black, color = Color.White.copy(alpha = .84f))
                    }
                }
                CardMoneyPair(card)
                Row(Modifier.background(Color.White.copy(alpha = if (dark) .13f else .16f), CircleShape).padding(horizontal = 10.dp, vertical = 7.dp),
                    horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.AccountBalanceWallet, null, Modifier.size(15.dp), tint = Color.White.copy(alpha = .68f))
                    Text(linked, fontSize = 11.5.sp, lineHeight = 14.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = .76f), maxLines = 1,
                        overflow = TextOverflow.Ellipsis, modifier = Modifier.testTag("planning.card.linked.${card.wallet.id}"))
                }
                CardStatementFooter(card, onOpenStatement)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable private fun CardStatementFooter(card: PlanningCreditCardAccount, onOpenStatement: () -> Unit) {
    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            StatementMiniLabel(stringResource(R.string.planning_planning_close), card.profile.statementClosingDay.toString())
            StatementMiniLabel(stringResource(R.string.planning_planning_due), card.profile.paymentDueDay.toString())
        }
        TextButton(onClick = onOpenStatement, modifier = Modifier.testTag("planning.card.statement.${card.wallet.id}")
            .background(Color.White.copy(alpha = .18f), CircleShape).border(.8.dp, Color.White.copy(alpha = .16f), CircleShape),
            contentPadding = PaddingValues(horizontal = 11.dp, vertical = 7.dp)) {
            Icon(Icons.Default.Description, null, Modifier.size(13.dp), tint = Color.White)
            Spacer(Modifier.width(5.dp))
            Text(stringResource(R.string.planning_planning_statement), fontSize = 11.5.sp, lineHeight = 14.sp, fontWeight = FontWeight.Black, color = Color.White)
        }
    }
}

@Composable private fun StatementMiniLabel(title: String, value: String) {
    Row(Modifier.background(Color.White.copy(alpha = .14f), CircleShape).padding(horizontal = 9.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, fontSize = 10.5.sp, lineHeight = 13.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = .64f))
        Text(value, fontSize = 13.5.sp, lineHeight = 16.sp, fontWeight = FontWeight.Black, color = Color.White)
    }
}

@Composable private fun CardMoneyPair(card: PlanningCreditCardAccount) {
    val available = formatMinorUnits(card.availableCreditMinor, card.currencyCode)
    val debt = formatMinorUnits(card.currentDebtMinor, card.currencyCode)
    val measure = rememberTextMeasurer()
    val density = LocalDensity.current
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val halfWidth = with(density) { (maxWidth - 12.dp).toPx() / 2 }
        val stacked = measure.measure(AnnotatedString(available), TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Black), softWrap = false).size.width > halfWidth ||
            measure.measure(AnnotatedString(debt), TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Black), softWrap = false).size.width > halfWidth - with(density) { 20.dp.toPx() }
        if (stacked) Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            CardMoneyBlock(available, true, "planning.card.available.${card.wallet.id}", Modifier.fillMaxWidth())
            CardMoneyBlock(debt, false, "planning.card.debt.${card.wallet.id}", Modifier.fillMaxWidth())
        } else Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Bottom) {
            CardMoneyBlock(available, true, "planning.card.available.${card.wallet.id}", Modifier.weight(1f))
            CardMoneyBlock(debt, false, "planning.card.debt.${card.wallet.id}", Modifier.weight(1f))
        }
    }
}

@Composable private fun CardMoneyBlock(value: String, primary: Boolean, tag: String, modifier: Modifier) {
    val dark = MaterialTheme.colorScheme.background.luminance() < .5f
    Column(modifier.then(if (primary) Modifier else Modifier.background(Color.White.copy(alpha = if (dark) .11f else .15f), RoundedCornerShape(14.dp)).padding(horizontal = 10.dp, vertical = 8.dp)),
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(stringResource(if (primary) R.string.planning_planning_available_credit else R.string.planning_planning_current_debt),
            fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = if (primary) .7f else .62f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        val measurer = rememberTextMeasurer()
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val width = with(LocalDensity.current) { maxWidth.toPx() }
            var size = if (primary) 24f else 16f
            while (size > 9f && measurer.measure(AnnotatedString(value), TextStyle(fontSize = size.sp, fontWeight = FontWeight.Black, letterSpacing = 0.sp), softWrap = false).size.width > width) size -= .5f
            Text(value, Modifier.fillMaxWidth().testTag(tag), style = TextStyle(fontSize = size.sp, fontWeight = FontWeight.Black, letterSpacing = 0.sp),
                color = Color.White, maxLines = 1, softWrap = false)
        }
    }
}
