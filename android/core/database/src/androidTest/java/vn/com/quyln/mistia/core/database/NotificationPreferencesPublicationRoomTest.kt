package vn.com.quyln.mistia.core.database

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collect
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NotificationPreferencesPublicationRoomTest {
    @Test fun anOlderListenerReadCannotPublishMasterOnAfterTheOffMutation()=runBlocking<Unit> {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val file="mistia-notification-preferences"
        val master="mistia.notifications.enabled"
        context.deleteSharedPreferences(file)
        val backing=context.getSharedPreferences(file,Context.MODE_PRIVATE)
        val armed=AtomicBoolean(false)
        val captured=CountDownLatch(1);val release=CountDownLatch(1)
        fun pauseCapturedOn(value:Boolean) {
            if(value && Looper.myLooper()==Looper.getMainLooper() && armed.compareAndSet(true,false)) {
                captured.countDown()
                check(release.await(5,TimeUnit.SECONDS)){"Listener read was not released"}
            }
        }
        val preferences=object:SharedPreferences by backing {
            override fun getBoolean(key:String?,defaultValue:Boolean):Boolean {
                val value=backing.getBoolean(key,defaultValue)
                if(key==master)pauseCapturedOn(value)
                return value
            }
            override fun getAll():MutableMap<String,*> {
                val value=backing.all
                pauseCapturedOn(value[master]as?Boolean ?: false)
                return value
            }
        }
        val controlled=object:ContextWrapper(context) {
            override fun getSharedPreferences(name:String,mode:Int):SharedPreferences =
                if(name==file)preferences else super.getSharedPreferences(name,mode)
        }
        val emissions=Collections.synchronizedList(mutableListOf<Boolean>())
        var watcher:Job?=null;var writer:Thread?=null
        val writerFailure=AtomicReference<Throwable?>()
        try {
            val store=LocalNotificationPreferencesStore(controlled)
            armed.set(true);store.setMaster(true)
            assertTrue("Actual main listener did not capture on",captured.await(5,TimeUnit.SECONDS))
            watcher=launch(Dispatchers.Unconfined,start=CoroutineStart.UNDISPATCHED){store.state.collect{emissions+=it.enabled}}
            val attempted=CountDownLatch(1);val finished=CountDownLatch(1)
            writer=Thread {
                attempted.countDown()
                try{store.setMaster(false)}catch(failure:Throwable){writerFailure.set(failure)}
                finally{finished.countDown()}
            }.apply{start()}
            assertTrue(attempted.await(5,TimeUnit.SECONDS))
            // The broken setter can finish while the old read is held. The corrected setter
            // waits for that read's lock; always release it, without asserting a timing limit.
            finished.await(500,TimeUnit.MILLISECONDS)
            release.countDown();writer.join(5000)
            assertFalse("Off writer did not complete",writer.isAlive);assertNull(writerFailure.get())
            InstrumentationRegistry.getInstrumentation().runOnMainSync{}
            val values=synchronized(emissions){emissions.toList()}
            val off=values.indexOf(false)
            assertTrue("No off publication: $values",off>=0)
            assertTrue("Old listener republished on after off: $values",values.drop(off).none{it})
            assertFalse(backing.getBoolean(master,true))
            assertFalse(store.state.value.enabled)
            assertEquals(store.state.value,LocalNotificationPreferencesStore(context).state.value)
        }finally{
            release.countDown();writer?.join(5000);watcher?.cancelAndJoin()
            context.deleteSharedPreferences(file)
        }
    }
    @Test fun mainListenerReentryCannotRepublishTheOuterOnValueAfterAnObserverTurnsItOff()=runBlocking<Unit> {
        val context=ApplicationProvider.getApplicationContext<Context>();val file="mistia-notification-preferences"
        context.deleteSharedPreferences(file)
        var watcher:Job?=null
        try {
            val store=LocalNotificationPreferencesStore(context);val reflected=AtomicBoolean(false)
            watcher=launch(Dispatchers.Unconfined,start=CoroutineStart.UNDISPATCHED){store.state.collect{
                if(it.enabled && reflected.compareAndSet(false,true))store.setMaster(false)
            }}
            InstrumentationRegistry.getInstrumentation().runOnMainSync{store.setMaster(true)}
            InstrumentationRegistry.getInstrumentation().runOnMainSync{}
            assertTrue(reflected.get())
            assertFalse(context.getSharedPreferences(file,Context.MODE_PRIVATE).getBoolean("mistia.notifications.enabled",true))
            assertFalse("Outer update republished an older on value",store.state.value.enabled)
        }finally{watcher?.cancelAndJoin();context.deleteSharedPreferences(file)}
    }
    @Test fun aWriteDuringListenerRegistrationIsIncludedInTheInitialPublishedSnapshot() {
        val context=ApplicationProvider.getApplicationContext<Context>();val file="mistia-notification-preferences"
        context.deleteSharedPreferences(file)
        try {
            val backing=context.getSharedPreferences(file,Context.MODE_PRIVATE)
            val preferences=object:SharedPreferences by backing {
                override fun registerOnSharedPreferenceChangeListener(listener:SharedPreferences.OnSharedPreferenceChangeListener?) {
                    backing.edit().putBoolean("mistia.notifications.enabled",true).commit()
                    backing.registerOnSharedPreferenceChangeListener(listener)
                }
            }
            val controlled=object:ContextWrapper(context) {
                override fun getSharedPreferences(name:String,mode:Int):SharedPreferences =
                    if(name==file)preferences else super.getSharedPreferences(name,mode)
            }
            val store=LocalNotificationPreferencesStore(controlled)
            assertTrue(backing.getBoolean("mistia.notifications.enabled",false))
            assertTrue("Constructor missed the write before listener registration",store.state.value.enabled)
        }finally{context.deleteSharedPreferences(file)}
    }

}
