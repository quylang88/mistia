package vn.com.quyln.mistia.core.model

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.serialization.json.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class InvestmentAccountingParityNativeTest {
    @Test fun sameSwiftGoldensOnRealAndroidRuntime() {
        val source=InstrumentationRegistry.getInstrumentation().context.assets.open("investment-accounting-v1.json")
            .bufferedReader().use { it.readText() }
        InvestmentAccountingVectorAssertions.check(Json.parseToJsonElement(source).jsonObject)
    }
}
