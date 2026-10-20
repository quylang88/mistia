package vn.com.quyln.mistia.feature.overview

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.platform.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.math.BigInteger
import java.time.*
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class OverviewCategoryVisualTest {
    @get:Rule val compose=createComposeRule()
    private val context=ApplicationProvider.getApplicationContext<Context>()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val now=Instant.now()
    private val zone=ZoneId.systemDefault()
    private val day=now.atZone(zone).toLocalDate()
    private val month=java.time.YearMonth.from(day)
    private val childId=UUID.randomUUID().toString()
    private val rootId=UUID.randomUUID().toString()
    private fun slice(id:String,name:String,amount:Long,children:List<OverviewCategorySpendingSlice> = emptyList())=
        OverviewCategorySpendingSlice("category-$id",id,name,"fork.knife","#FF8A4C",BigInteger.valueOf(amount),children)
    private val child=slice(childId,"Grocery",7)
    private val root=slice(rootId,"Food",7,listOf(child))
    private fun page(slices:List<OverviewCategorySpendingSlice> = listOf(root))=OverviewCategorySpendingMonth(month,"JPY",slices,slices.fold(BigInteger.ZERO){a,b->a+b.amountMinor})
    @Composable private fun Environment(language:String="en",dark:Boolean=false,content:@Composable ()->Unit) {
        val config=android.content.res.Configuration(context.resources.configuration).apply {setLocale(Locale.forLanguageTag(language))}
        val density=LocalDensity.current
        CompositionLocalProvider(LocalContext provides context.createConfigurationContext(config),LocalConfiguration provides config,
            LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {MistiaTheme(darkTheme=dark) {content()}}
    }
    @Composable private fun Chart(source:OverviewCategorySpendingMonth=page()) {
        Scaffold {padding ->Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(padding).verticalScroll(rememberScrollState()).padding(18.dp)) {
            OverviewCategoryChart(listOf(source),month,{}) {}
        }}
    }
    private fun details():OverviewExpenseDay {
        val id=UUID.randomUUID().toString()
        val record=LedgerTransactionRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("entry_status_raw_value","posted");put("primary_kind_raw_value","expense");put("title","Original expense")
            put("amount_minor",7);put("source_currency_code","JPY");put("occurred_at",now.toString());put("created_at",now.toString())
        },now.toString(),null,0))
        return overviewExpenseDay(owner,listOf(record),emptyList(),day,"JPY",zone=zone)
    }
    @Test fun transactionCountCaptionHasCorrectMeaningInAllThreeLanguagesAtActual130() {
        var language by mutableStateOf("en");val details=details()
        compose.setContent {Environment(language) {OverviewDayTransactionsSheet(details,emptyMap(),emptyMap(),zone,{},{})}}
        for((code,caption) in listOf("en" to "Transactions","vi" to "Giao d\u1ecbch","ja" to "\u53d6\u5f15\u4ef6\u6570")) {
            compose.runOnIdle {language=code};compose.onNodeWithTag("overview.day.count").assertTextEquals("1")
            compose.onNodeWithText(caption).assertExists();assertComplete(compose.onNodeWithText(caption))
        }
    }
    @Test fun singleCategoryPieUsesVisibleInteriorGradientInsteadOfFlatColor() {
        compose.setContent {Environment {Chart()}}
        compose.onNodeWithTag("overview.category.pie").performScrollTo().assertIsDisplayed()
        val pixels=compose.onNodeWithTag("overview.category.pie").captureToImage().toPixelMap()
        fun luminance(y:Float):Float {
            var sum=0f
            for(dx in -2..2) for(dy in -2..2) {val c=pixels[pixels.width/2+dx,(pixels.height*y).toInt()+dy];sum+=0.2126f*c.red+0.7152f*c.green+0.0722f*c.blue}
            return sum/25
        }
        Assert.assertTrue("Category pie is visually flat",kotlin.math.abs(luminance(0.25f)-luminance(0.75f))>0.025f)
    }
    @Test fun drilldownBackIncludesCategoryIconAlongsideItsLabel() {
        compose.setContent {Environment {Chart()}}
        compose.onNodeWithTag("overview.category.row.category-$rootId").performScrollTo().performTouchInput {click()}
        compose.onNodeWithTag("overview.category.back").assertExists()
        compose.onNodeWithTag("overview.category.back.icon",useUnmergedTree=true).assertIsDisplayed()
        compose.onNodeWithText("Food").assertExists()
    }
    @Test fun emptyCategoryStateIncludesPieIconAboveItsExplanation() {
        compose.setContent {Environment {Chart(page(emptyList()))}}
        compose.onNodeWithTag("overview.category.empty.icon",useUnmergedTree=true).assertIsDisplayed()
        compose.onNodeWithText("No spending yet").assertExists()
    }
    @Test fun categoryRootDrilldownAndEmptyVisualsRemainReadableAtActual130InThreeLanguagesLightDark() {
        val health=slice(UUID.randomUUID().toString(),"Health",3).copy(iconSymbolName="cross.case.fill",colorHex="#F45C7E")
        val home=slice(UUID.randomUUID().toString(),"Home",2).copy(iconSymbolName="house.fill",colorHex="#7556D8")
        val normal=page(listOf(root,health,home));var source by mutableStateOf(normal)
        var dark by mutableStateOf(false);var language by mutableStateOf("en")
        compose.setContent {Environment(language,dark) {Chart(source)}}
        for(code in listOf("en","vi","ja")) for(theme in listOf(false,true)) {
            compose.runOnIdle {language=code;dark=theme;source=normal}
            compose.onNodeWithTag("overview.category.pie").performScrollTo().assertIsDisplayed()
            for(item in normal.slices) assertComplete(compose.onNodeWithTag("overview.category.amount.${item.id}",useUnmergedTree=true))
            capture("overview-category-visual-root-$code-${if(theme) "dark" else "light"}-font130.png")
            compose.onNodeWithTag("overview.category.pie").performTouchInput {click(androidx.compose.ui.geometry.Offset(width*0.75f,height*0.5f))}
            compose.onNodeWithTag("overview.category.back.icon",useUnmergedTree=true).assertIsDisplayed()
            compose.onNodeWithTag("overview.category.amount.${child.id}",useUnmergedTree=true).assertExists()
            assertComplete(compose.onNodeWithText("Food"));assertComplete(compose.onNodeWithTag("overview.category.amount.${child.id}",useUnmergedTree=true))
            capture("overview-category-visual-drill-$code-${if(theme) "dark" else "light"}-font130.png")
            compose.onNodeWithTag("overview.category.back").performTouchInput {click()}
            compose.onNodeWithTag("overview.category.amount.${root.id}",useUnmergedTree=true).assertExists()
            compose.runOnIdle {source=page(emptyList())}
            compose.onNodeWithTag("overview.category.empty.icon",useUnmergedTree=true).assertIsDisplayed()
            compose.onNodeWithTag("overview.category.back").assertDoesNotExist()
            capture("overview-category-visual-empty-$code-${if(theme) "dark" else "light"}-font130.png")
        }
        Assert.assertEquals(BigInteger.valueOf(12),normal.totalMinor)
    }
    @Test fun dayTransactionCountCaptionAndExactMoneyRemainReadableInThreeLanguagesLightDark() {
        val details=details();var dark by mutableStateOf(false);var language by mutableStateOf("en")
        compose.setContent {Environment(language,dark) {OverviewDayTransactionsSheet(details,emptyMap(),emptyMap(),zone,{},{})}}
        val travel=compose.onAllNodes(isRoot()).fetchSemanticsNodes().maxOf {it.boundsInRoot.height}*0.35f
        compose.onNodeWithText("Day details").performTouchInput {swipe(center,center+androidx.compose.ui.geometry.Offset(0f,-travel),500)}
        val captions=mapOf("en" to "Transactions","vi" to "Giao d\u1ecbch","ja" to "\u53d6\u5f15\u4ef6\u6570")
        for(code in listOf("en","vi","ja")) for(theme in listOf(false,true)) {
            compose.runOnIdle {language=code;dark=theme}
            compose.onNodeWithTag("overview.day.count").assertIsDisplayed().assertTextEquals("1");compose.onNodeWithText(captions.getValue(code)).assertIsDisplayed();assertComplete(compose.onNodeWithText(captions.getValue(code)))
            assertComplete(compose.onNodeWithTag("overview.day.count"));assertComplete(compose.onNodeWithTag("overview.day.total",useUnmergedTree=true))
            capture("overview-day-count-caption-$code-${if(theme) "dark" else "light"}-font130.png")
        }
    }
    @Test fun legacyCategorySymbolRendersTheSameMeaningAsItsCanonicalCatalogIcon() {
        compose.setContent {Environment {Surface {Row(Modifier.padding(40.dp)) {
            vn.com.quyln.mistia.core.designsystem.CategoryIcon("fork.knife",null,"#FF8A4C",Modifier.size(32.dp).testTag("legacy.icon"))
            vn.com.quyln.mistia.core.designsystem.CategoryIcon("mistia.category.expense.food.grocery",null,"#FF8A4C",Modifier.size(32.dp).testTag("canonical.icon"))
        }}}}
        val legacy=compose.onNodeWithTag("legacy.icon",useUnmergedTree=true).captureToImage().toPixelMap()
        val canonical=compose.onNodeWithTag("canonical.icon",useUnmergedTree=true).captureToImage().toPixelMap()
        Assert.assertEquals(canonical.width,legacy.width);Assert.assertEquals(canonical.height,legacy.height)
        var different=0
        for(x in 0 until canonical.width) for(y in 0 until canonical.height) {
            val a=legacy[x,y];val b=canonical[x,y]
            if(kotlin.math.abs(a.red-b.red)+kotlin.math.abs(a.green-b.green)+kotlin.math.abs(a.blue-b.blue)>0.03f) different++
        }
        Assert.assertTrue("Legacy food icon changed meaning ($different pixels)",different<=4)
    }
    private fun assertComplete(node:SemanticsNodeInteraction) {
        val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>();node.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
        val layout=layouts.single();Assert.assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
        Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true))
        for(line in 0 until layout.lineCount) Assert.assertFalse(layout.isLineEllipsized(line))
        for(i in layout.layoutInput.text.indices) {val box=layout.getBoundingBox(i);Assert.assertTrue("glyph$i outside$box/${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
    }
    private fun capture(name:String) {
        compose.waitForIdle();val automation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline=android.os.SystemClock.uptimeMillis()+5000;var previous:android.graphics.Bitmap?=null;var stableFrames=0;var stable:android.graphics.Bitmap?=null
        while(android.os.SystemClock.uptimeMillis()<deadline) {val frame=checkNotNull(automation.takeScreenshot());stableFrames=if(previous?.sameAs(frame)==true) stableFrames+1 else 0;previous?.recycle();previous=frame;if(stableFrames>=3) {stable=frame;break}}
        if(stable==null) previous?.recycle();val bitmap=checkNotNull(stable){"Unsettled screenshot:$name"};java.io.File(context.getExternalFilesDir(null),name).outputStream().use {Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};bitmap.recycle()
    }

}
