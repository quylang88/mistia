package vn.com.quyln.mistia

import android.app.Application
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject
import vn.com.quyln.mistia.core.model.SyncEngine
import vn.com.quyln.mistia.core.sync.SyncRuntime

@HiltAndroidApp
class MistiaApplication : Application() {
    @Inject lateinit var syncEngine: SyncEngine

    override fun onCreate() {
        super.onCreate()
        SyncRuntime.engine = syncEngine
    }
}
