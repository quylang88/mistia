package vn.com.quyln.mistia.core.designsystem

/** Shared source artwork; custom user colors apply only to unregistered fallbacks. */
data class FinanceIconAsset(val assetName:String,val drawableRes:Int,val primaryHex:String,val template:Boolean)
fun financeIconAsset(token:String):FinanceIconAsset?=generatedFinanceIconAssets[token]
