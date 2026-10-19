package com.example.scroll_trek

import android.accessibilityservice.AccessibilityService
import android.content.SharedPreferences
import android.graphics.Rect
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import kotlin.math.abs

class ScrollAccessibilityService : AccessibilityService() {

  companion object {
    private const val TAG = "ScrollPOC"
    private const val PREFS_NAME = "scroll_trek_stats"

    private const val KEY_TOTAL_Y = "device.totalAbsDeltaY"
    private const val KEY_TOTAL_X = "device.totalAbsDeltaX"
    private const val KEY_VALID = "device.validEvents"
    private const val KEY_ZERO = "device.zeroEvents"
    private const val KEY_UNMEASURABLE = "device.unmeasurableEvents"

    private const val OWN_PACKAGE = "com.example.scroll_trek"
  }

  private lateinit var preferences: SharedPreferences

  private fun logScrollableNodes(event: AccessibilityEvent) {
    val root = rootInActiveWindow ?: return

    try {
      fun inspect(node: android.view.accessibility.AccessibilityNodeInfo, depth: Int) {
        if (depth > 15) return

        if (node.isScrollable) {
          val rect = Rect()
          node.getBoundsInScreen(rect)

          Log.d(
            TAG,
            "SCROLLABLE_NODE " +
              "package=${node.packageName} " +
              "class=${node.className} " +
              "id=${node.viewIdResourceName} " +
              "bounds=$rect " +
              "actions=${node.actionList.map { it.id }}",
          )
        }

        for (i in 0 until node.childCount) {
          val child = node.getChild(i) ?: continue
          try {
            inspect(child, depth + 1)
          } finally {
            child.recycle()
          }
        }
      }

      inspect(root, 0)
    } finally {
      root.recycle()
    }
  }

  private data class DeviceScrollStats(
    var totalAbsDeltaY: Long = 0L,
    var totalAbsDeltaX: Long = 0L,
    var validEvents: Long = 0L,
    var zeroEvents: Long = 0L,
    var unmeasurableEvents: Long = 0L,
  )

  private var deviceStats = DeviceScrollStats()

  // Baselines are separated by app and node to avoid comparing
  // positions belonging to different scroll containers.
  private val lastScrollYByNode = mutableMapOf<String, Int>()

  override fun onServiceConnected() {
    super.onServiceConnected()

    preferences = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)

    deviceStats =
      DeviceScrollStats(
        totalAbsDeltaY = preferences.getLong(KEY_TOTAL_Y, 0L),
        totalAbsDeltaX = preferences.getLong(KEY_TOTAL_X, 0L),
        validEvents = preferences.getLong(KEY_VALID, 0L),
        zeroEvents = preferences.getLong(KEY_ZERO, 0L),
        unmeasurableEvents = preferences.getLong(KEY_UNMEASURABLE, 0L),
      )

    Log.i(TAG, "SERVICE_CONNECTED")
    Log.i(TAG, "Device-wide tracking enabled; own dashboard excluded")
    Log.i(TAG, "RESTORED totalAbsDeltaY=${deviceStats.totalAbsDeltaY}")
  }

  /**
   * Returns a vertical movement delta when one can be measured.
   *
   * Android's reported scroll delta is preferred. If unavailable, try a scroll-position difference.
   */
  private fun measureVerticalMovement(event: AccessibilityEvent, packageName: String): Int? {
    val reportedDelta = event.scrollDeltaY

    // Trust Android's delta when it reports actual movement.
    if (reportedDelta != -1 && reportedDelta != 0) {
      return reportedDelta
    }

    // A zero or unavailable delta may require a position fallback.
    val node =
      event.source
        ?: run {
          Log.d(
            TAG,
            "NO_SCROLL_SOURCE package=$packageName " +
              "reportedDelta=$reportedDelta scrollY=${event.scrollY}",
          )
          return if (reportedDelta == 0) 0 else null
        }

    try {
      val bounds = Rect()
      node.getBoundsInScreen(bounds)

      val nodeKey = buildString {
        append(packageName)
        append('|')
        append(node.className?.toString().orEmpty())
        append('|')
        append(node.viewIdResourceName.orEmpty())
        append('|')
        append(bounds.flattenToString())
      }

      val currentY = event.scrollY
      val previousY = lastScrollYByNode.put(nodeKey, currentY)

      if (previousY == null) {
        Log.d(
          TAG,
          "POSITION_BASELINE package=$packageName " +
            "class=${node.className} y=$currentY " +
            "reportedDelta=$reportedDelta",
        )

        return if (reportedDelta == 0) 0 else null
      }

      val positionDelta = currentY - previousY

      Log.d(
        TAG,
        "POSITION_FALLBACK package=$packageName " +
          "previousY=$previousY currentY=$currentY " +
          "positionDelta=$positionDelta " +
          "reportedDelta=$reportedDelta",
      )

      return if (positionDelta != 0) positionDelta else reportedDelta
    } catch (e: Exception) {
      Log.w(TAG, "Position fallback failed for $packageName", e)
      return if (reportedDelta == 0) 0 else null
    } finally {
      node.recycle()
    }
  }

  private fun persistStats() {
    preferences
      .edit()
      .putLong(KEY_TOTAL_Y, deviceStats.totalAbsDeltaY)
      .putLong(KEY_TOTAL_X, deviceStats.totalAbsDeltaX)
      .putLong(KEY_VALID, deviceStats.validEvents)
      .putLong(KEY_ZERO, deviceStats.zeroEvents)
      .putLong(KEY_UNMEASURABLE, deviceStats.unmeasurableEvents)
      .apply()
  }

  private fun estimatedDistanceMeters(): Double {
    val dpi = resources.displayMetrics.densityDpi
    if (dpi <= 0) return 0.0

    // Physical-screen-equivalent estimate, not real-world distance.
    return deviceStats.totalAbsDeltaY * 0.0254 / dpi
  }

  private fun sendStats(sourcePackage: String, deltaY: Int, deltaX: Int, measured: Boolean) {
    MainActivity.sendScrollUpdate(
      mapOf(
        "sourcePackage" to sourcePackage,
        "scope" to "device",
        "deltaY" to deltaY,
        "deltaX" to deltaX,
        "measured" to measured,
        "totalAbsDeltaY" to deviceStats.totalAbsDeltaY,
        "totalAbsDeltaX" to deviceStats.totalAbsDeltaX,
        "validEvents" to deviceStats.validEvents,
        "zeroEvents" to deviceStats.zeroEvents,
        "unmeasurableEvents" to deviceStats.unmeasurableEvents,
        "estimatedDistanceMeters" to estimatedDistanceMeters(),
      )
    )
  }

  override fun onAccessibilityEvent(event: AccessibilityEvent?) {

    if (event == null) return

    val packageName = event.packageName?.toString() ?: return

    Log.d(
      TAG,
      "EVENT package=$packageName " +
        "type=${event.eventType} " +
        "class=${event.className} " +
        "scrollY=${event.scrollY} " +
        "maxScrollY=${event.maxScrollY} " +
        "deltaY=${event.scrollDeltaY}",
    )

    // Don't count scrolling inside Scroll Trek itself.
    if (packageName == OWN_PACKAGE) return

    // Count scroll events from any app, not a predefined app list.
    if (event.eventType != AccessibilityEvent.TYPE_VIEW_SCROLLED) {
      return
    }

    if (!::preferences.isInitialized) return

    val deltaY = measureVerticalMovement(event, packageName)

    val reportedDeltaX = event.scrollDeltaX
    val deltaX =
      if (reportedDeltaX != -1) {
        reportedDeltaX
      } else {
        0
      }

    if (deltaY == null) {
      deviceStats.unmeasurableEvents++
      persistStats()

      Log.d(
        TAG,
        "SCROLL_UNMEASURABLE package=$packageName " + "count=${deviceStats.unmeasurableEvents}",
      )

      sendStats(sourcePackage = packageName, deltaY = 0, deltaX = deltaX, measured = false)
      return
    }

    if (deltaY != 0 || deltaX != 0) {
      deviceStats.validEvents++
    } else {
      deviceStats.zeroEvents++
    }

    deviceStats.totalAbsDeltaY += abs(deltaY.toLong())
    deviceStats.totalAbsDeltaX += abs(deltaX.toLong())

    persistStats()

    sendStats(sourcePackage = packageName, deltaY = deltaY, deltaX = deltaX, measured = true)

    Log.i(
      TAG,
      "DEVICE_SCROLL package=$packageName " +
        "deltaY=$deltaY " +
        "totalAbsDeltaY=${deviceStats.totalAbsDeltaY} " +
        "estimatedMeters=${estimatedDistanceMeters()} " +
        "valid=${deviceStats.validEvents} " +
        "unmeasurable=${deviceStats.unmeasurableEvents}",
    )
  }

  override fun onInterrupt() {
    Log.w(TAG, "SERVICE_INTERRUPTED")
  }

  override fun onDestroy() {
    lastScrollYByNode.clear()
    super.onDestroy()
  }
}
