package vn.com.quyln.mistia.feature.overview

import java.math.BigInteger
import vn.com.quyln.mistia.core.model.*

/** Compatibility delegate to the shared exact cash reader; inventory and FX remain report inputs. */
internal fun overviewAssetBalance(owner:UserId,records:List<CloudRecord>,wallets:List<CloudRecord>,currency:String,
    rates:List<ExchangeRateSnapshot> = emptyList(),inventoryCost:BigInteger?=BigInteger.ZERO,inventoryCurrency:String?=currency):BigInteger? {
    return financeWalletCashTotalRaw(owner,records,wallets,currency,rates,inventoryCost,inventoryCurrency)
}
