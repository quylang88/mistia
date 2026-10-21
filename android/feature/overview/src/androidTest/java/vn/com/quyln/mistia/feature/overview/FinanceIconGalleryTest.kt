package vn.com.quyln.mistia.feature.overview

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import vn.com.quyln.mistia.core.designsystem.*

/** Real packaged-art gallery, supplementing the six independently chosen pixel-reference cases. */
class FinanceIconGalleryTest {
    @get:Rule val compose=createComposeRule()
    @Test fun everyRegisteredSourceLoadsAndEveryArtworkRendersInBothThemesAtActual130() {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val manifest=InstrumentationRegistry.getInstrumentation().context.assets.open("finance-icon-reference/registry.json").bufferedReader().use {Json.parseToJsonElement(it.readText()).jsonObject}
        val descriptors=manifest.getValue("descriptors").jsonArray.map {it.jsonObject}
        for(row in descriptors) {
            val token=row.getValue("token").jsonPrimitive.content
            val actual=financeIconAsset(token)
            assertNotNull("Source token $token must remain usable",actual)
            assertEquals(row.getValue("assetName").jsonPrimitive.content,actual!!.assetName)
            assertEquals(row.getValue("primaryHex").jsonPrimitive.content,actual.primaryHex)
            assertEquals(row.getValue("template").jsonPrimitive.boolean,actual.template)
        }
        val tokens=descriptors.distinctBy {it.getValue("assetName").jsonPrimitive.content}.map {it.getValue("token").jsonPrimitive.content}
        val pages=tokens.chunked(16);var page by mutableIntStateOf(0);var dark by mutableStateOf(false)
        compose.setContent {
            val density=LocalDensity.current
            CompositionLocalProvider(LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {
                MistiaTheme(darkTheme=dark) {
                    Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.background).padding(12.dp).testTag("finance.gallery"),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                        for(group in pages[page].chunked(4)) Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                            for(token in group) Column(Modifier.weight(1f),horizontalAlignment=Alignment.CenterHorizontally) {
                                FinanceIcon(token,Modifier.size(44.dp).testTag("finance.gallery.$token"))
                                Text(financeIconAsset(token)!!.assetName.removePrefix("ic_fluent_").removeSuffix("_24_color").removeSuffix("_24_filled"),fontSize=10.sp,lineHeight=12.sp,color=MaterialTheme.colorScheme.onSurface,modifier=Modifier.testTag("finance.gallery.label.$token"))
                            }
                        }
                    }
                }
            }
        }
        for(theme in listOf(false,true)) for(index in pages.indices) {
            compose.runOnIdle {dark=theme;page=index}
            for(token in pages[index]) {
                val actual=compose.onNodeWithTag("finance.gallery.$token").captureToImage().asAndroidBitmap()
                assertTrue(actual.width>0 && actual.height>0)
                val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                compose.onNodeWithTag("finance.gallery.label.$token",useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
                val layout=layouts.single();assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
                assertEquals(layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true))
            }
            val bitmap=compose.onNodeWithTag("finance.gallery").captureToImage().asAndroidBitmap()
            java.io.File(context.getExternalFilesDir(null),"finance-native-gallery-${index+1}-${if(theme) "dark" else "light"}-font130.png").outputStream().use {bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)}
        }
    }
}
