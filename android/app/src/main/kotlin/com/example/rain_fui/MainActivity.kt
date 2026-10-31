package com.example.rain_fui

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes the two Android-only facts the FFmpeg runner needs, plus the
 * permission skeleton of spec §7.
 *
 * The bundled FFmpeg binary ships as `lib/<abi>/libffmpeg_exe.so` because
 * Android 10+ refuses to exec anything from the app's data directory. Its real
 * location is `ApplicationInfo.nativeLibraryDir`, which has no `dart:io`
 * equivalent, so it is served over the `rain_fui/ffmpeg` channel.
 *
 * `rain_fui/permissions` serves `AndroidPermissionService` in Dart: it asks for
 * `POST_NOTIFICATIONS` on Android 13+ and opens the all-files settings screen.
 * The notification feature itself is out of scope for this phase, so these are
 * the declaration and request skeleton only.
 */
class MainActivity : FlutterActivity() {
    /**
     * Result of the POST_NOTIFICATIONS request currently with the system.
     * `onRequestPermissionsResult` answers it; null when nothing is pending.
     */
    private var pendingNotificationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FFMPEG_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                    "abi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull())
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSIONS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotificationPermission" -> requestNotificationPermission(result)
                    "openManageAllFilesSettings" -> openManageAllFilesSettings(result)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_REQUEST_CODE) {
            return
        }
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingNotificationResult?.success(granted)
        pendingNotificationResult = null
    }

    /** API 33+ shows a runtime prompt; older releases grant notifications on install. */
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        // A second request while one is still waiting must not leave the first
        // Dart future hanging.
        pendingNotificationResult?.success(false)
        pendingNotificationResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_REQUEST_CODE,
        )
    }

    /** Opens the per-app all-files screen, falling back to the global one. */
    private fun openManageAllFilesSettings(result: MethodChannel.Result) {
        val appSettings = Intent(
            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
            Uri.parse("package:$packageName"),
        )
        try {
            startActivity(appSettings)
        } catch (notFound: ActivityNotFoundException) {
            try {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            } catch (ignored: ActivityNotFoundException) {
                // No such settings screen on this build; the call is fire-and-forget.
            }
        }
        result.success(null)
    }

    private companion object {
        const val FFMPEG_CHANNEL = "rain_fui/ffmpeg"
        const val PERMISSIONS_CHANNEL = "rain_fui/permissions"
        const val NOTIFICATION_REQUEST_CODE = 1001
    }
}
