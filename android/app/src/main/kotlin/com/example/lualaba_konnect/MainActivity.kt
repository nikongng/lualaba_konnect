package com.example.lualaba_konnect

import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var sosLaunchChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        SosLaunchStore.updateFromIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        SosLaunchStore.updateFromIntent(intent)
        notifyPendingSosLaunch()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sosLaunchChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lualaba_konnect/sos_launch",
        )
        sosLaunchChannel?.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "consumePendingSosLaunch" -> result.success(SosLaunchStore.consumePendingLaunch())
                "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                "openFullScreenIntentSettings" -> result.success(openFullScreenIntentSettings())
                else -> result.notImplemented()
            }
        }
        notifyPendingSosLaunch()
    }

    private fun notifyPendingSosLaunch() {
        val pending = SosLaunchStore.peekPendingLaunch() ?: return
        sosLaunchChannel?.invokeMethod("onPendingSosLaunch", pending)
    }

    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return true
        }
        val notificationManager = getSystemService(NotificationManager::class.java)
        return notificationManager?.canUseFullScreenIntent() ?: false
    }

    private fun openFullScreenIntentSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return false
        }
        return try {
            val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }
}
