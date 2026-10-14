package vn.com.quyln.mistia

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class AndroidWalletReminderPlatformTest {
    private class IsolatedContext(base:Context):ContextWrapper(base) {
        private val suffix=UUID.randomUUID().toString()
        override fun getSharedPreferences(name:String,mode:Int)=super.getSharedPreferences("$name.$suffix",mode)
        override fun deleteSharedPreferences(name:String)=super.deleteSharedPreferences("$name.$suffix")
    }
    private fun context()=IsolatedContext(ApplicationProvider.getApplicationContext())
    private fun ticket():NativeWalletReminder {
        val zone=ZoneId.systemDefault();val wallet=UUID.randomUUID().toString()
        return NativeWalletReminder(UUID.randomUUID().toString(),"mistia.reminder.wallet.$wallet",wallet,
            Instant.now().atZone(zone).toLocalDate().plusDays(1).atTime(LocalTime.of(9,0)).atZone(zone).toInstant().toString(),zone.id)
    }
    @Test fun durableNativeStateReopensWithDailyDeliveryHistory() {
        val context=context()
        try {
            val target=ticket();val state=NativeWalletReminderState(listOf(target),mapOf(target.tag to target.fireAt))
            AndroidWalletReminderPlatform(context).writeState(state)
            assertEquals(state,AndroidWalletReminderPlatform(context).readState())
        } finally {context.deleteSharedPreferences("mistia.native.wallet.reminders")}
    }
    @Test fun futureAlarmCreatesOwnedImmutablePendingIntentAndCanBeCancelled() {
        val context=context();val target=ticket();val platform=AndroidWalletReminderPlatform(context)
        val intent=Intent(context,WalletReminderAlarmReceiver::class.java).setAction("vn.com.quyln.mistia.WALLET_REMINDER")
            .setData(Uri.Builder().scheme("mistia").authority("wallet-reminder-alarm").appendPath(target.ownerUserId).appendPath(target.walletId).build())
        try {
            platform.schedule(target)
            assertNotNull(PendingIntent.getBroadcast(context,0,intent,PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE))
            platform.cancel(target)
            assertNull(PendingIntent.getBroadcast(context,0,intent,PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE))
        } finally {platform.cancel(target);context.deleteSharedPreferences("mistia.native.wallet.reminders")}
    }
    @Test fun permissionGrantedPostUsesWalletChannelCurrentCopyAndStableTag() {
        val context=context();val platform=AndroidWalletReminderPlatform(context);assumeTrue(platform.permissionGranted)
        val target=ticket()
        try {
            val row=AppNotificationRecord(target.ownerUserId,target.key,"Reminder test","Current wallet balance test","lowWallet",source="localReminder",
                resourceType="wallet",resourceId=target.walletId,createdAt=target.fireAt,updatedAt=Instant.now().toString())
            platform.post(target,row);platform.post(target,row)
            val manager=context.getSystemService(NotificationManager::class.java)
            val posted=manager.activeNotifications.filter {it.tag==target.tag}.single().notification
            assertEquals(AndroidWalletReminderPlatform.CHANNEL,posted.channelId)
            assertEquals(row.title,posted.extras.getCharSequence("android.title").toString())
            assertEquals(row.body,posted.extras.getCharSequence("android.text").toString())
            platform.dismiss(target.tag);assertTrue(manager.activeNotifications.none {it.tag==target.tag})
        } finally {platform.dismiss(target.tag);context.deleteSharedPreferences("mistia.native.wallet.reminders")}
    }
}
