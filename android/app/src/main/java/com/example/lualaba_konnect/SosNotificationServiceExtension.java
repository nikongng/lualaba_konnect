package com.example.lualaba_konnect;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;

import androidx.annotation.Keep;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;

import com.onesignal.notifications.IDisplayableMutableNotification;
import com.onesignal.notifications.INotificationReceivedEvent;
import com.onesignal.notifications.INotificationServiceExtension;

import org.json.JSONObject;

@Keep
public class SosNotificationServiceExtension implements INotificationServiceExtension {
    private static final String CHANNEL_ID = "lualaba_sos_emergency_v1";
    private static final long[] VIBRATION_PATTERN = new long[]{0L, 600L, 300L, 700L};

    @Override
    public void onNotificationReceived(INotificationReceivedEvent event) {
        IDisplayableMutableNotification notification = event.getNotification();
        JSONObject data = notification.getAdditionalData();
        if (data == null) {
            return;
        }

        String type = data.optString("type", "");
        if (!"sos_alert".equals(type)) {
            return;
        }

        Context context = event.getContext().getApplicationContext();
        String chatId = data.optString("chatId", "").trim();
        if (chatId.isEmpty()) {
            return;
        }

        String fromName = data.optString("fromName", "Un proche").trim();
        String chatName = data.optString("chatName", fromName).trim();
        String alertId = data.optString("alertId", notification.getNotificationId()).trim();
        Uri soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM);
        if (soundUri == null) {
            soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE);
        }

        event.preventDefault();
        ensureSosChannel(context, soundUri);

        Intent fullScreenIntent = SosAlertActivity.createIntent(
                context,
                chatId,
                chatName,
                fromName,
                alertId,
                notification.getAndroidNotificationId()
        );

        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }

        PendingIntent fullScreenPendingIntent = PendingIntent.getActivity(
                context,
                notification.getAndroidNotificationId(),
                fullScreenIntent,
                flags
        );

        String title = safeText(notification.getTitle(), "SOS urgent");
        String body = safeText(
                notification.getBody(),
                fromName + " a besoin d aide immediatement."
        );

        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.mipmap.launcher_icon)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setColor(Color.parseColor("#D50000"))
                .setOngoing(true)
                .setAutoCancel(false)
                .setFullScreenIntent(fullScreenPendingIntent, true)
                .setContentIntent(fullScreenPendingIntent)
                .setVibrate(VIBRATION_PATTERN);

        if (soundUri != null) {
            builder.setSound(soundUri);
        }

        NotificationManagerCompat.from(context).notify(
                notification.getAndroidNotificationId(),
                builder.build()
        );
    }

    private static void ensureSosChannel(Context context, Uri soundUri) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        NotificationManager notificationManager = context.getSystemService(NotificationManager.class);
        if (notificationManager == null) {
            return;
        }

        NotificationChannel existingChannel = notificationManager.getNotificationChannel(CHANNEL_ID);
        if (existingChannel != null) {
            return;
        }

        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "SOS Urgences",
                NotificationManager.IMPORTANCE_HIGH
        );
        channel.setDescription("Alertes SOS critiques en plein ecran");
        channel.enableVibration(true);
        channel.setVibrationPattern(VIBRATION_PATTERN);
        channel.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
        if (soundUri != null) {
            AudioAttributes audioAttributes = new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build();
            channel.setSound(soundUri, audioAttributes);
        }
        notificationManager.createNotificationChannel(channel);
    }

    private static String safeText(String value, String fallback) {
        if (value == null) {
            return fallback;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? fallback : trimmed;
    }
}
