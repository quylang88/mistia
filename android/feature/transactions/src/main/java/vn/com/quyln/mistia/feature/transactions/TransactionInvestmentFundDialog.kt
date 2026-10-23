package vn.com.quyln.mistia.feature.transactions

import androidx.compose.runtime.Composable
import vn.com.quyln.mistia.core.designsystem.InvestmentFundUsageDialog
import vn.com.quyln.mistia.core.model.*

@Composable internal fun TransactionInvestmentFundDialog(review:InvestmentFundUsageReview,wallets:List<LedgerWalletRecord>,onDismiss:()->Unit,onConfirm:()->Unit,isSaving:Boolean=false) {
    InvestmentFundUsageDialog(review,wallets,onDismiss,onConfirm,isSaving)
}
