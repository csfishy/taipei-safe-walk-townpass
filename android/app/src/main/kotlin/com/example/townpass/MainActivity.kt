package com.example.townpass

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Safe Walk SOS: send an SMS without opening the messaging app.
        // Dart side: lib/features/safe_walk/platform/nearby_emergency/sms_sender.dart
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "safe_walk/sms")
            .setMethodCallHandler { call, result ->
                if (call.method != "send") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val number = call.argument<String>("number")
                val body = call.argument<String>("body")
                if (number.isNullOrBlank() || body.isNullOrBlank()) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                if (checkSelfPermission(Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
                    // First use: ask once. The user taps SOS again after granting.
                    requestPermissions(arrayOf(Manifest.permission.SEND_SMS), 1001)
                    result.success(false)
                    return@setMethodCallHandler
                }
                try {
                    val sms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        getSystemService(SmsManager::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        SmsManager.getDefault()
                    }
                    sms.sendMultipartTextMessage(number, null, sms.divideMessage(body), null, null)
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
    }
}
