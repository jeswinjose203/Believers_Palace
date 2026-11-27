package com.example.believers_palace

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.URL
import javax.net.ssl.HttpsURLConnection

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "believers_palace/android_update")
            .setMethodCallHandler { call, result ->
                if (call.method != "install") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val build = call.argument<Int>("build")
                val size = call.argument<Number>("size")?.toLong()
                val url = call.argument<String>("url")
                if (build == null || size == null || size !in 1L..500_000_000L ||
                    url == null || !releaseUrl.matches(url.replace("%2B", "+", ignoreCase = true))
                ) {
                    result.error("invalid_release", "Invalid update metadata", null)
                    return@setMethodCallHandler
                }
                installUpdate(URL(url), build, size, result)
            }
    }

    private fun installUpdate(url: URL, build: Int, size: Long, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            try {
                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                result.success("permissionRequired")
            } catch (error: Exception) {
                result.error("permission_unavailable", "Could not open install settings", null)
            }
            return
        }

        Thread {
            try {
                val apk = downloadUpdate(url, build, size)
                runOnUiThread {
                    try {
                        check(!isFinishing && !isDestroyed)
                        val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
                        val intent = Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        startActivity(intent)
                        result.success("installerOpened")
                    } catch (error: Exception) {
                        result.error("installer_unavailable", "Could not open the Android installer", null)
                    }
                }
            } catch (error: Exception) {
                result.error("download_failed", "Could not download or validate the APK", null)
            }
        }.start()
    }

    @Suppress("DEPRECATION")
    private fun downloadUpdate(url: URL, build: Int, size: Long): File {
        val directory = File(cacheDir, "app-update").apply { mkdirs() }
        val temporary = File.createTempFile("download-", ".apk", directory)
        try {
            val connection = openReleaseDownload(url)
            try {
                val deadline = SystemClock.elapsedRealtime() + 240_000
                connection.inputStream.use { input ->
                    temporary.outputStream().use { output ->
                        val buffer = ByteArray(64 * 1024)
                        var received = 0L
                        while (true) {
                            check(SystemClock.elapsedRealtime() < deadline)
                            val count = input.read(buffer)
                            if (count == -1) break
                            received += count
                            check(received <= size)
                            output.write(buffer, 0, count)
                        }
                        check(received == size)
                    }
                }
            } finally {
                connection.disconnect()
            }
            val archive = checkNotNull(packageManager.getPackageArchiveInfo(temporary.absolutePath, 0))
            val installed = packageManager.getPackageInfo(packageName, 0)
            check(archive.packageName == packageName &&
                archive.versionCode == build && build > installed.versionCode)

            val apk = File(directory, "believers-palace.apk")
            check(temporary.renameTo(apk))
            return apk
        } finally {
            if (temporary.exists()) temporary.delete()
        }
    }

    private fun openReleaseDownload(initial: URL): HttpsURLConnection {
        var url = initial
        repeat(5) {
            check(url.protocol == "https" && url.userInfo == null &&
                url.host in releaseHosts)
            val connection = url.openConnection() as HttpsURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 15_000
            connection.readTimeout = 20_000
            var connected = false
            try {
                val status = connection.responseCode
                if (status == 200) {
                    connected = true
                    return connection
                }
                check(status in listOf(301, 302, 303, 307, 308))
                url = URL(url, checkNotNull(connection.getHeaderField("Location")))
            } finally {
                // A successful response is closed by the caller after streaming.
                if (!connected) connection.disconnect()
            }
        }
        error("Too many release download redirects")
    }

    private companion object {
        val releaseUrl = Regex(
            """https://github\.com/jeswinjose203/Believers_Palace/releases/download/v\d+\.\d+\.\d+\+[1-9]\d{0,9}/believers-palace\.apk"""
        )
        val releaseHosts = setOf("github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com")
    }
}
