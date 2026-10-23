package vn.com.quyln.mistia.core.designsystem

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

@Composable fun InvestmentFundUsageDialog(review:InvestmentFundUsageReview,wallets:List<LedgerWalletRecord>,onDismiss:()->Unit,onConfirm:()->Unit,isSaving:Boolean=false,tagPrefix:String="transaction.funds",canConfirm:Boolean=true,tradeChanges:Boolean=false,contextMessage:String?=null) {
    val comparison=review.comparison
    val rows=comparison.changes.ifEmpty {
        val prior=comparison.current.usages[review.consent.transactionId]
        val next=comparison.proposed.usages[review.consent.transactionId]
        val use=next ?: prior
        if(use==null)emptyList() else listOf(InvestmentFundTimelineWalletChange(use.walletId,use.currencyCode,
            prior?.investmentToUseMinor ?: BigInteger.ZERO,next?.investmentToUseMinor ?: BigInteger.ZERO,
            comparison.proposed.availableByWalletId[use.walletId] ?: BigInteger.ZERO))
    }
    fun kind(previous:BigInteger,proposed:BigInteger,allocationChanged:Boolean=false)=when {
        proposed.signum()==0->2
        previous==proposed && allocationChanged->3
        previous.signum()>0 && previous!=proposed->1
        else->0
    }
    val mode=if(rows.size==1)kind(rows.single().previousMinor,rows.single().proposedMinor,comparison.changes.isNotEmpty()) else 1
    val title=if(tradeChanges)R.string.investment_trade_cash_review_title else when(mode){0->R.string.investment_wallet_use_funds_title;1->R.string.investment_wallet_update_funds_title;3->R.string.investment_wallet_reallocate_funds_title;else->R.string.investment_wallet_restore_funds_title}
    val action=if(tradeChanges)R.string.investment_trade_cash_review_action else when(mode){0->R.string.investment_wallet_use_funds_action;1->R.string.investment_wallet_update_funds_action;3->R.string.investment_wallet_reallocate_funds_action;else->R.string.investment_wallet_restore_funds_action}
    AlertDialog(modifier=Modifier.testTag(tagPrefix+".review"),onDismissRequest={if(!isSaving)onDismiss()},title={Text(stringResource(title),Modifier.testTag(tagPrefix+".title"))},
        text={Column(Modifier.heightIn(max=400.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(16.dp)) {
            contextMessage?.let{Text(it,Modifier.testTag(tagPrefix+".context"))}
            rows.forEach{row->Column(Modifier.fillMaxWidth().testTag(tagPrefix+".wallet."+row.walletId),verticalArrangement=Arrangement.spacedBy(6.dp)) {
                Text(wallets.firstOrNull{it.id==row.walletId && it.ownerUserId==review.consent.ownerUserId}?.name.orEmpty(),Modifier.testTag(tagPrefix+".name."+row.walletId),style=MaterialTheme.typography.titleSmall)
                val previous=formatMinorUnits(row.previousMinor,row.currencyCode);val proposed=formatMinorUnits(row.proposedMinor,row.currencyCode);val remaining=formatMinorUnits(row.remainingInvestmentMinor,row.currencyCode)
                Text(if(tradeChanges)stringResource(R.string.investment_trade_cash_review_message,previous,proposed,remaining) else when(kind(row.previousMinor,row.proposedMinor,row in comparison.changes)) {
                    0->stringResource(R.string.investment_wallet_use_funds_message,proposed,remaining)
                    1->stringResource(R.string.investment_wallet_update_funds_message,previous,proposed,remaining)
                    3->stringResource(R.string.investment_wallet_reallocate_funds_message,proposed,remaining)
                    else->stringResource(R.string.investment_wallet_restore_funds_message,previous,remaining)
                },Modifier.testTag(tagPrefix+".message."+row.walletId))
            }}
        }},
        confirmButton={TextButton(onClick=onConfirm,enabled=rows.isNotEmpty() && !isSaving && canConfirm,modifier=Modifier.heightIn(min=48.dp).testTag(tagPrefix+".confirm")){Text(stringResource(action),Modifier.testTag(tagPrefix+".confirm.text"))}},
        dismissButton={TextButton(onClick=onDismiss,enabled=!isSaving,modifier=Modifier.heightIn(min=48.dp).testTag(tagPrefix+".cancel")){Text(stringResource(R.string.common_cancel),Modifier.testTag(tagPrefix+".cancel.text"))}})
}
