package com.sales.ba

import android.media.MediaDrm
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.UUID

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.sales.ba/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "getStableId") result.success(stableId()) else result.notImplemented()
            }
    }

    /**
     * Widevine device id: belongs to the phone, not to the app. It does not change on
     * uninstall/reinstall and does not depend on the signing key (debug, release or
     * Play-signed all give the same value). Only a hash is returned.
     * Returns null when the phone has no Widevine DRM.
     */
    private fun stableId(): String? {
        var drm: MediaDrm? = null
        return try {
            drm = MediaDrm(UUID.fromString("edef8ba9-79d6-4ace-a3c8-27dcd51d21ed"))
            val raw = drm.getPropertyByteArray(MediaDrm.PROPERTY_DEVICE_UNIQUE_ID)
            if (raw == null || raw.isEmpty()) null
            else MessageDigest.getInstance("SHA-256").digest(raw)
                .joinToString("") { "%02x".format(it) }.substring(0, 32)
        } catch (e: Exception) {
            null
        } finally {
            try {
                if (Build.VERSION.SDK_INT >= 28) {
                    drm?.close()
                } else {
                    @Suppress("DEPRECATION")
                    drm?.release()
                }
            } catch (_: Exception) {}
        }
    }
}
