package vn.com.quyln.mistia.feature.overview

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
import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*
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

/** Literal source artworks independently pin mapping, template tint and native frame behavior. */
class FinanceIconArtworkTest {
    @get:Rule val compose=createComposeRule()
    private fun artwork(token:String,source:String,frame:Int=30,dark:Boolean=false,templateColor:Int?=null) {
        val background=if(dark) android.graphics.Color.BLACK else android.graphics.Color.WHITE
        compose.setContent {MistiaTheme(darkTheme=dark) {
            Box(Modifier.size(frame.dp).background(Color(background)).testTag("artwork")) {
                CategoryIcon(token,TransactionCategoryKind.EXPENSE,"#00FF00",Modifier.size(frame.dp))
            }
        }}
        val actual=compose.onNodeWithTag("artwork").captureToImage().asAndroidBitmap()
        assertSource(actual,source,background,templateColor)
    }
    private fun assertSource(actual:Bitmap,source:String,background:Int,templateColor:Int?=null) {
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
        assertTrue("$source must render source artwork at 0.86 frame with original color/tint; mean RGB error=$mean",mean<6.0)
    }
    @Test fun internetRendersOriginalWifiGradientInsteadOfHouseGroup()=artwork("mistia.category.expense.home_bills.internet","ic_fluent_wifi_24_color")
    @Test fun billRendersCalendarArtworkInsteadOfEllipsis()=artwork("mistia.plan.bill","ic_fluent_calendar_clock_24_color",44)
    @Test fun loanKeepsOriginalVaultColorsUnderDarkTheme()=artwork("mistia.plan.loan","ic_fluent_vault_24_color",44,true)
    @Test fun babyFoodTemplateUsesItsRegisteredAmberInsteadOfTheRequestedCustomGreen()=artwork("mistia.category.expense.family_children.baby_food","ic_fluent_bowl_salad_24_filled",30,false,0xFFFFB347.toInt())
    @Test fun cashRetainsOriginalMulticolorArtwork()=artwork("mistia.wallet.cash","ic_fluent_coin_multiple_24_color",44,true)
    @Test fun transferUsesTheRegisteredSyncArtworkInsteadOfExpenseFallback()=artwork("mistia.flow.transfer","ic_fluent_arrow_sync_24_color")
    @Test fun actualRecentTransferRowUsesRegisteredArtworkWithoutTheMaterialBypass() {
        val id="22222222-2222-2222-2222-222222222222";val owner="11111111-1111-1111-1111-111111111111"
        val now=Instant.parse("2026-10-21T00:00:00Z")
        val tx=LedgerTransactionRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner,buildJsonObject {
            put("id",id);put("user_id",owner);put("primary_kind_raw_value","transfer");put("entry_status_raw_value","posted")
            put("title","Transfer");put("amount_minor",5000);put("occurred_at",now.toString());put("created_at",now.toString())
        },now.toString(),null,0))
        compose.setContent {MistiaTheme(darkTheme=false) {
            Box(Modifier.background(Color.White)) {OverviewRecentTransactionRow(OverviewRecentRow(tx,Money(5000,"JPY")),null,now,ZoneId.of("Asia/Tokyo"))}
        }}
        val actual=compose.onNodeWithTag("overview.recent.icon.$id.mistia.flow.transfer",useUnmergedTree=true).captureToImage().asAndroidBitmap()
        assertSource(actual,"ic_fluent_arrow_sync_24_color",android.graphics.Color.WHITE)
    }

}
