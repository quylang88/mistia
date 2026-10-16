package vn.com.quyln.mistia.feature.settings

import android.content.Context
import android.os.Process
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.LocalCurrencyPreferencesStore
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class CurrencyPreferencesProcessTest {
    @Test fun preferencesRetainExactValuesAcrossExplicitProcessPhases() {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val phase=InstrumentationRegistry.getArguments().getString("currencyPreferencesPhase")
        val name=if(phase == null) "currency-roundtrip-${java.util.UUID.randomUUID()}" else "currency-process-fixture-v94"
        val raw=context.getSharedPreferences(name,Context.MODE_PRIVATE)
        val expected=CurrencyPreferences(listOf("JPY","VND"),"VND",CurrencyRateMode.AUTOMATIC,"170.12345679")
        if(phase != "read") {
            assertTrue(raw.edit().clear().commit())
            LocalCurrencyPreferencesStore(context,name).use { store ->
                store.setEnabled("VND",true);store.setPrimary("VND");store.setDisplayedManualRate("170.123456785");store.setAutomatic(true)
                assertEquals(expected,store.state.value)
            }
            // Metadata shares the actual preferences file; commit flushes preceding apply writes before this phase exits.
            assertTrue(raw.edit().putInt("fixture.writer.pid",Process.myPid()).commit())
        }
        if(phase != "write") {
            try {
                LocalCurrencyPreferencesStore(context,name).use { assertEquals(expected,it.state.value) }
                if(phase == "read") {
                    val writer=raw.getInt("fixture.writer.pid",-1)
                    assertTrue(writer > 0);assertNotEquals(writer,Process.myPid())
                }
            } finally {assertTrue(raw.edit().clear().commit())}
        }
        println("Currency preferences phase=${phase ?: "roundtrip"} pid=${Process.myPid()}")
    }
}
