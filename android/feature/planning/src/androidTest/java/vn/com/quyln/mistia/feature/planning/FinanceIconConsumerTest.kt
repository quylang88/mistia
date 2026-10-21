package vn.com.quyln.mistia.feature.planning

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.Rect
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import vn.com.quyln.mistia.core.designsystem.*
import vn.com.quyln.mistia.core.model.TransactionCategoryKind

class FinanceIconConsumerTest {
    @get:Rule val compose=createComposeRule()
    private fun artwork(kind:String,token:String,source:String,frame:Int,dark:Boolean=false,templateColor:Int?=null) {
        val background=if(dark) android.graphics.Color.BLACK else android.graphics.Color.WHITE
        compose.setContent {MistiaTheme(darkTheme=dark) {
            Box(Modifier.size(frame.dp).background(Color(background)).testTag("artwork")) {
                if(kind=="goal") SavingsGoalIcon(token,Modifier.size(frame.dp)) else InstallmentIcon(token)
            }
        }}
        val actual=compose.onNodeWithTag("artwork").captureToImage().asAndroidBitmap()
        val original=InstrumentationRegistry.getInstrumentation().context.assets.open("finance-icon-reference/$source.png").use(BitmapFactory::decodeStream)
        val expected=Bitmap.createBitmap(actual.width,actual.height,Bitmap.Config.ARGB_8888)
        val canvas=Canvas(expected);canvas.drawColor(background)
        val width=kotlin.math.round(actual.width*0.86f).toInt();val height=kotlin.math.round(actual.height*0.86f).toInt()
        val left=(actual.width-width)/2;val top=(actual.height-height)/2
        val paint=Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        if(templateColor!=null) paint.colorFilter=PorterDuffColorFilter(templateColor,PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(original,null,Rect(left,top,left+width,top+height),paint)
        var error=0L
        for(y in 0 until actual.height) for(x in 0 until actual.width) {
            val a=actual.getPixel(x,y);val b=expected.getPixel(x,y)
            for(shift in listOf(0,8,16)) error+=kotlin.math.abs(((a shr shift) and 255)-((b shr shift) and 255))
        }
        val mean=error.toDouble()/(actual.width*actual.height*3)
        assertTrue("$token must render $source at 0.86 frame with original color/tint; mean RGB error=$mean",mean<6.0)
    }
    @Test fun goalUsesTheOriginalRegisteredArtwork()=artwork("goal","mistia.goal.home","ic_fluent_home_24_color",44)
    @Test fun installmentUsesTheOriginalRegisteredArtwork()=artwork("installment","mistia.plan.loan","ic_fluent_vault_24_color",40)
}
