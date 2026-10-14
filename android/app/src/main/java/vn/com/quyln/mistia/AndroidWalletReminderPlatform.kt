package vn.com.quyln.mistia

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationCompat
import java.io.IOException
import java.time.Instant
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.sync.NativeWalletReminderPlatform
import vn.com.quyln.mistia.core.designsystem.R as DesignR

class AndroidWalletReminderPlatform(private val context:Context):NativeWalletReminderPlatform {
    private val preferences=context.getSharedPreferences("mistia.native.wallet.reminders",Context.MODE_PRIVATE)
    private val json=Json {ignoreUnknownKeys=true}
    private val alarms=context.getSystemService(AlarmManager::class.java)
    private val notifications=context.getSystemService(NotificationManager::class.java)
    override val permissionGranted:Boolean get()=notifications.areNotificationsEnabled() &&
        notifications.getNotificationChannel(CHANNEL)?.importance!=NotificationManager.IMPORTANCE_NONE &&
        (Build.VERSION.SDK_INT<33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED)
    override fun readState():NativeWalletReminderState = preferences.getString("state",null)?.let {
        runCatching {json.decodeFromString<NativeWalletReminderState>(it)}.getOrDefault(NativeWalletReminderState())
    } ?: NativeWalletReminderState()
    override fun writeState(state:NativeWalletReminderState) {
        if(!preferences.edit().putString("state",json.encodeToString(state)).commit()) throw IOException("Unable to persist native wallet reminders")
    }
    private fun alarmIntent(ticket:NativeWalletReminder)=Intent(context,WalletReminderAlarmReceiver::class.java)
        .setAction("vn.com.quyln.mistia.WALLET_REMINDER")
        .setData(Uri.Builder().scheme("mistia").authority("wallet-reminder-alarm").appendPath(ticket.ownerUserId).appendPath(ticket.walletId).build())
        .putExtra(WalletReminderDeliveryWorker.TICKET,json.encodeToString(ticket))
    override fun schedule(ticket:NativeWalletReminder) {
        val pending=PendingIntent.getBroadcast(context,0,alarmIntent(ticket),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        // Inexact idle-aware alarm: no exact-alarm special access is required.
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,Instant.parse(ticket.fireAt).toEpochMilli(),pending)
    }
    override fun cancel(ticket:NativeWalletReminder) {
        PendingIntent.getBroadcast(context,0,alarmIntent(ticket),PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)?.let {
            alarms.cancel(it);it.cancel()
        }
    }
    override fun post(ticket:NativeWalletReminder,record:AppNotificationRecord) {
        if(!permissionGranted) return
        notifications.createNotificationChannel(NotificationChannel(CHANNEL,
            context.getString(DesignR.string.settings_notifications_reminders_wallets),NotificationManager.IMPORTANCE_DEFAULT))
        val intent=Intent(context,MainActivity::class.java).setAction("vn.com.quyln.mistia.OPEN_WALLET_REMINDER")
            .setData(Uri.Builder().scheme("mistia").authority("wallet-reminder").appendPath(ticket.ownerUserId).appendPath(ticket.walletId).build())
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val open=PendingIntent.getActivity(context,0,intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val duplicate=notifications.activeNotifications.any {it.tag==ticket.tag && it.notification.extras.getString(FIRE_AT)==ticket.fireAt}
        val notification=NotificationCompat.Builder(context,CHANNEL).setSmallIcon(R.drawable.ic_wallet_notification)
            .setContentTitle(record.title).setContentText(record.body).setStyle(NotificationCompat.BigTextStyle().bigText(record.body))
            .setContentIntent(open).setAutoCancel(true).setOnlyAlertOnce(duplicate)
            .setCategory(NotificationCompat.CATEGORY_REMINDER).setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setExtras(Bundle().apply {putString(FIRE_AT,ticket.fireAt)}).build()
        notifications.notify(ticket.tag,1,notification)
    }
    override fun dismiss(tag:String) {notifications.cancel(tag,1)}
    override fun retainDisplayed(tags:Set<String>) {
        notifications.activeNotifications.filter {it.tag?.startsWith("mistia.reminder.wallet.")==true && it.tag !in tags}
            .forEach {notifications.cancel(it.tag,it.id)}
    }
    companion object {const val CHANNEL="mistia.wallet.reminders";private const val FIRE_AT="mistia.wallet.fireAt"}
}
