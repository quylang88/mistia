package vn.com.quyln.mistia.core.designsystem

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp

/** Original registered artwork follows Swift's 0.86-frame image and template-color rules. */
@Composable
fun FinanceIcon(token:String,modifier:Modifier=Modifier) {
    val asset=financeIconAsset(token) ?: return
    Box(modifier.size(34.dp),contentAlignment=Alignment.Center) {
        Image(painterResource(asset.drawableRes),contentDescription=null,modifier=Modifier.fillMaxSize(0.86f),contentScale=ContentScale.Fit,
            colorFilter=if(asset.template) ColorFilter.tint(categoryColorFromHex(asset.primaryHex)) else null)
    }
}
