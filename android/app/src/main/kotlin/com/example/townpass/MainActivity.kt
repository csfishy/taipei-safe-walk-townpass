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
        // Safe Walk SOS: request an SMS without opening the messaging app.
        // Dart side: lib/features/safe_walk/platform/nearby_emergency/sms_sender.dart
        // Codes: handed = submission call returned; no_permission / invalid =
        // no submission attempted; failed = submission outcome is unknown.
        // None of these codes confirms that any message part was sent/delivered.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "safe_walk/sms")
            .setMethodCallHandler { call, result ->
                if (call.method != "send") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val number = call.argument<String>("number")
                val body = call.argument<String>("body")
                if (number.isNullOrBlank() || body.isNullOrBlank()) {
                    result.success("invalid")
                    return@setMethodCallHandler
                }
                if (checkSelfPermission(Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
                    // Never resume this request after permission is granted: the
                    // user must start a new SOS action with fresh consent/location.
                    requestPermissions(arrayOf(Manifest.permission.SEND_SMS), 1001)
                    // The OS may not show a dialog (for example after repeated
                    // denial); report missing permission, not a displayed prompt.
                    result.success("no_permission")
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
                    // No sent/delivery PendingIntents are registered. handed means
                    // only that this submission call returned without an exception;
                    // the carrier can still reject it or fail to deliver it later.
                    result.success("handed")
                } catch (e: Exception) {
                    result.success("failed")
                }
            }
    }
}
