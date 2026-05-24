package com.example.lualaba_konnect;

import android.animation.ArgbEvaluator;
import android.animation.ValueAnimator;
import android.app.Activity;
import android.app.KeyguardManager;
import android.content.Context;
import android.content.Intent;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.TextView;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationManagerCompat;

public class SosAlertActivity extends Activity {
    private ValueAnimator flashAnimator;
    @Nullable
    private TextView senderView;
    @Nullable
    private TextView detailsView;
    @Nullable
    private Ringtone ringtone;
    @Nullable
    private Vibrator vibrator;
    private int androidNotificationId = -1;
    private String chatId = "";
    private String chatName = "SOS";
    private String fromName = "Un proche";
    private String alertId = "";

    public static Intent createIntent(
            Context context,
            String chatId,
            String chatName,
            String fromName,
            String alertId,
            int androidNotificationId
    ) {
        Intent intent = new Intent(context, SosAlertActivity.class);
        intent.putExtra(SosLaunchStore.EXTRA_CHAT_ID, chatId);
        intent.putExtra(SosLaunchStore.EXTRA_CHAT_NAME, chatName);
        intent.putExtra(SosLaunchStore.EXTRA_FROM_NAME, fromName);
        intent.putExtra(SosLaunchStore.EXTRA_ALERT_ID, alertId);
        intent.putExtra(SosLaunchStore.EXTRA_ANDROID_NOTIFICATION_ID, androidNotificationId);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        return intent;
    }

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true);
            setTurnScreenOn(true);
        }
        getWindow().addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                        | WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                        | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                        | WindowManager.LayoutParams.FLAG_FULLSCREEN
        );

        setContentView(R.layout.activity_sos_alert);

        senderView = findViewById(R.id.sosSenderText);
        detailsView = findViewById(R.id.sosDetailsText);
        Button openButton = findViewById(R.id.sosOpenButton);
        Button dismissButton = findViewById(R.id.sosDismissButton);
        bindIntent(getIntent());

        startVisualAlert();
        startFeedback();

        openButton.setOnClickListener(v -> {
            cancelPostedNotification(androidNotificationId);
            requestDismissKeyguardIfPossible();
            Intent launchIntent = SosLaunchStore.createMainLaunchIntent(
                    SosAlertActivity.this,
                    chatId,
                    chatName,
                    fromName,
                    alertId
            );
            startActivity(launchIntent);
            finish();
        });

        dismissButton.setOnClickListener(v -> {
            cancelPostedNotification(androidNotificationId);
            finish();
        });
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        bindIntent(intent);
    }

    @Override
    protected void onDestroy() {
        stopVisualAlert();
        stopFeedback();
        super.onDestroy();
    }

    @Override
    public void onBackPressed() {
        // Keep the alert explicit. Users can dismiss with the dedicated button.
    }

    private void startVisualAlert() {
        final int startColor = 0xFF5A0000;
        final int endColor = 0xFFFF1F1F;
        flashAnimator = ValueAnimator.ofObject(new ArgbEvaluator(), startColor, endColor);
        flashAnimator.setDuration(700L);
        flashAnimator.setRepeatMode(ValueAnimator.REVERSE);
        flashAnimator.setRepeatCount(ValueAnimator.INFINITE);
        flashAnimator.addUpdateListener(animation ->
                findViewById(R.id.sosAlertRoot).setBackgroundColor((Integer) animation.getAnimatedValue())
        );
        flashAnimator.start();
    }

    private void stopVisualAlert() {
        if (flashAnimator != null) {
            flashAnimator.cancel();
            flashAnimator = null;
        }
    }

    private void startFeedback() {
        try {
            Uri ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM);
            if (ringtoneUri == null) {
                ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE);
            }
            ringtone = RingtoneManager.getRingtone(this, ringtoneUri);
            if (ringtone != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    ringtone.setLooping(true);
                }
                ringtone.play();
            }
        } catch (Throwable ignored) {
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                VibratorManager manager = getSystemService(VibratorManager.class);
                vibrator = manager == null ? null : manager.getDefaultVibrator();
            } else {
                vibrator = (Vibrator) getSystemService(VIBRATOR_SERVICE);
            }
            if (vibrator != null && vibrator.hasVibrator()) {
                long[] pattern = new long[]{0L, 600L, 300L, 700L};
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0));
                } else {
                    vibrator.vibrate(pattern, 0);
                }
            }
        } catch (Throwable ignored) {
        }
    }

    private void stopFeedback() {
        try {
            if (ringtone != null && ringtone.isPlaying()) {
                ringtone.stop();
            }
        } catch (Throwable ignored) {
        }
        ringtone = null;

        try {
            if (vibrator != null) {
                vibrator.cancel();
            }
        } catch (Throwable ignored) {
        }
        vibrator = null;
    }

    private void requestDismissKeyguardIfPossible() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        try {
            KeyguardManager keyguardManager = getSystemService(KeyguardManager.class);
            if (keyguardManager != null) {
                keyguardManager.requestDismissKeyguard(this, null);
            }
        } catch (Throwable ignored) {
        }
    }

    private void cancelPostedNotification(int notificationId) {
        if (notificationId < 0) {
            return;
        }
        try {
            NotificationManagerCompat.from(this).cancel(notificationId);
        } catch (Throwable ignored) {
        }
    }

    private void bindIntent(@Nullable Intent intent) {
        if (intent == null) {
            return;
        }

        fromName = readExtra(intent, SosLaunchStore.EXTRA_FROM_NAME, "Un proche");
        chatId = readExtra(intent, SosLaunchStore.EXTRA_CHAT_ID, "");
        chatName = readExtra(intent, SosLaunchStore.EXTRA_CHAT_NAME, fromName);
        alertId = readExtra(intent, SosLaunchStore.EXTRA_ALERT_ID, "");
        androidNotificationId = intent.getIntExtra(
                SosLaunchStore.EXTRA_ANDROID_NOTIFICATION_ID,
                -1
        );

        if (senderView != null) {
            senderView.setText(fromName + " a envoye un SOS");
        }
        if (detailsView != null) {
            detailsView.setText("Alerte urgente. Ouvrez immediatement la discussion.");
        }
    }

    private String readExtra(Intent intent, String key, String fallback) {
        String value = intent.getStringExtra(key);
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }
        return value.trim();
    }
}
