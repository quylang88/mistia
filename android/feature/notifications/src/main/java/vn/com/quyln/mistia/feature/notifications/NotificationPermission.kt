package vn.com.quyln.mistia.feature.notifications

import android.Manifest
import android.os.Build

object NotificationPermission {
    val runtimePermission: String?
        get() = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.POST_NOTIFICATIONS else null
}
