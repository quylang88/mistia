package vn.com.quyln.mistia.feature.transactions

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import java.math.BigInteger
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

@Composable internal fun TransactionInvestmentFundDialog(review:InvestmentFundUsageReview,wallets:List<LedgerWalletRecord>,onDismiss:()->Unit,onConfirm:()->Unit,isSaving:Boolean=false) {
    val comparison=review.comparison
    val rows=comparison.changes.ifEmpty {
        val prior=comparison.current.usages[review.consent.transactionId]
        val next=comparison.proposed.usages[review.consent.transactionId]
        val use=next ?: prior
        if(use==null)emptyList() else listOf(InvestmentFundTimelineWalletChange(use.walletId,use.currencyCode,
            prior?.investmentToUseMinor ?: BigInteger.ZERO,next?.investmentToUseMinor ?: BigInteger.ZERO,
            comparison.proposed.availableByWalletId[use.walletId] ?: BigInteger.ZERO))
    }
    fun kind(previous:BigInteger,proposed:BigInteger)=when {
        proposed.signum()==0->2
        previous.signum()>0 && previous!=proposed->1
        else->0
    }
    val mode=if(rows.size==1)kind(rows.single().previousMinor,rows.single().proposedMinor) else 1
    val title=when(mode){0->R.string.investment_wallet_use_funds_title;1->R.string.investment_wallet_update_funds_title;else->R.string.investment_wallet_restore_funds_title}
    val action=when(mode){0->R.string.investment_wallet_use_funds_action;1->R.string.investment_wallet_update_funds_action;else->R.string.investment_wallet_restore_funds_action}
    AlertDialog(modifier=Modifier.testTag("transaction.funds.review"),onDismissRequest={if(!isSaving)onDismiss()},title={Text(stringResource(title),Modifier.testTag("transaction.funds.title"))},
        text={Column(Modifier.heightIn(max=400.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(16.dp)) {
            rows.forEach{row->Column(Modifier.fillMaxWidth().testTag("transaction.funds.wallet."+row.walletId),verticalArrangement=Arrangement.spacedBy(6.dp)) {
                Text(wallets.firstOrNull{it.id==row.walletId}?.name.orEmpty(),Modifier.testTag("transaction.funds.name."+row.walletId),style=MaterialTheme.typography.titleSmall)
                val previous=formatMinorUnits(row.previousMinor,row.currencyCode);val proposed=formatMinorUnits(row.proposedMinor,row.currencyCode);val remaining=formatMinorUnits(row.remainingInvestmentMinor,row.currencyCode)
                Text(when(kind(row.previousMinor,row.proposedMinor)) {
                    0->stringResource(R.string.investment_wallet_use_funds_message,proposed,remaining)
                    1->stringResource(R.string.investment_wallet_update_funds_message,previous,proposed,remaining)
                    else->stringResource(R.string.investment_wallet_restore_funds_message,previous,remaining)
                },Modifier.testTag("transaction.funds.message."+row.walletId))
            }}
        }},
        confirmButton={TextButton(onClick=onConfirm,enabled=rows.isNotEmpty() && !isSaving,modifier=Modifier.heightIn(min=48.dp).testTag("transaction.funds.confirm")){Text(stringResource(action),Modifier.testTag("transaction.funds.confirm.text"))}},
        dismissButton={TextButton(onClick=onDismiss,enabled=!isSaving,modifier=Modifier.heightIn(min=48.dp).testTag("transaction.funds.cancel")){Text(stringResource(R.string.common_cancel),Modifier.testTag("transaction.funds.cancel.text"))}})
}
