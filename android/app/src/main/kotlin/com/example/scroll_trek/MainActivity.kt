
package com.example.scroll_trek

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "scroll_trek/measurements"
        private const val PREFS_NAME = "scroll_trek_stats"

        private var channel: MethodChannel? = null
        private val mainHandler = Handler(Looper.getMainLooper())

        fun sendScrollUpdate(data: Map<String, Any>) {
            mainHandler.post {
                channel?.invokeMethod("scrollUpdate", data)
            }
        }
    }

    private fun estimateDistanceMeters(totalPixels: Long): Double {
        val dpi = resources.displayMetrics.densityDpi
        if (dpi <= 0) return 0.0

        return totalPixels * 0.0254 / dpi
    }

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        val methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        channel = methodChannel

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getStats" -> {
                    val prefs = getSharedPreferences(
                        PREFS_NAME,
                        Context.MODE_PRIVATE
                    )

                    val totalY = prefs.getLong(
                        "device.totalAbsDeltaY", 0L
                    )

                    val stats = mapOf(
                        "totalAbsDeltaY" to totalY,
                        "totalAbsDeltaX" to prefs.getLong(
                            "device.totalAbsDeltaX", 0L
                        ),
                        "validEvents" to prefs.getLong(
                            "device.validEvents", 0L
                        ),
                        "zeroEvents" to prefs.getLong(
                            "device.zeroEvents", 0L
                        ),
                        "unmeasurableEvents" to prefs.getLong(
                            "device.unmeasurableEvents", 0L
                        ),
                        "estimatedDistanceMeters" to
                            estimateDistanceMeters(totalY)
                    )

                    result.success(
                        mapOf("device" to stats)
                    )
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        channel = null
        super.onDestroy()
    }
}
