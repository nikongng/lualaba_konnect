package com.example.lualaba_konnect;

import android.content.Context;
import android.content.Intent;

import androidx.annotation.Nullable;

import java.util.HashMap;
import java.util.Map;

public final class SosLaunchStore {
    public static final String ACTION_OPEN_SOS_CHAT = "com.example.lualaba_konnect.OPEN_SOS_CHAT";
    public static final String EXTRA_CHAT_ID = "sos_chat_id";
    public static final String EXTRA_CHAT_NAME = "sos_chat_name";
    public static final String EXTRA_FROM_NAME = "sos_from_name";
    public static final String EXTRA_ALERT_ID = "sos_alert_id";
    public static final String EXTRA_ANDROID_NOTIFICATION_ID = "sos_android_notification_id";

    @Nullable
    private static Map<String, Object> pendingLaunch;

    private SosLaunchStore() {}

    public static Intent createMainLaunchIntent(
            Context context,
            String chatId,
            String chatName,
            String fromName,
            String alertId
    ) {
        Intent intent = new Intent(context, MainActivity.class);
        intent.setAction(ACTION_OPEN_SOS_CHAT);
        intent.putExtra(EXTRA_CHAT_ID, chatId);
        intent.putExtra(EXTRA_CHAT_NAME, chatName);
        intent.putExtra(EXTRA_FROM_NAME, fromName);
        intent.putExtra(EXTRA_ALERT_ID, alertId);
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_NEW_TASK);
        return intent;
    }

    public static synchronized void updateFromIntent(@Nullable Intent intent) {
        if (intent == null) {
            return;
        }

        String chatId = intent.getStringExtra(EXTRA_CHAT_ID);
        if (chatId == null || chatId.trim().isEmpty()) {
            return;
        }

        HashMap<String, Object> data = new HashMap<>();
        data.put("chatId", chatId.trim());

        String chatName = safeTrim(intent.getStringExtra(EXTRA_CHAT_NAME));
        if (!chatName.isEmpty()) {
            data.put("chatName", chatName);
        }

        String fromName = safeTrim(intent.getStringExtra(EXTRA_FROM_NAME));
        if (!fromName.isEmpty()) {
            data.put("fromName", fromName);
        }

        String alertId = safeTrim(intent.getStringExtra(EXTRA_ALERT_ID));
        if (!alertId.isEmpty()) {
            data.put("alertId", alertId);
        }

        pendingLaunch = data;
    }

    @Nullable
    public static synchronized HashMap<String, Object> consumePendingLaunch() {
        if (pendingLaunch == null) {
            return null;
        }
        HashMap<String, Object> copy = new HashMap<>(pendingLaunch);
        pendingLaunch = null;
        return copy;
    }

    @Nullable
    public static synchronized HashMap<String, Object> peekPendingLaunch() {
        if (pendingLaunch == null) {
            return null;
        }
        return new HashMap<>(pendingLaunch);
    }

    private static String safeTrim(@Nullable String value) {
        return value == null ? "" : value.trim();
    }
}
