package com.github.panlf.fueltrack

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.github.panlf.fueltrack/location"
        private const val SPEED_CHANNEL = "com.github.panlf.fueltrack/speed"
        private const val LOCATION_TIMEOUT_MS = 10_000L
        private const val PERMISSION_REQUEST_CODE = 4201
    }

    /** 定位超时调度器，页面销毁时统一回收，避免向已分离的引擎回传结果。 */
    private val timeoutHandler = Handler(Looper.getMainLooper())

    /** 在途的系统权限弹窗回调；Result 只允许回调一次。 */
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrentLocation" -> getCurrentLocation(result)
                "requestLocationPermission" -> requestLocationPermission(result)
                "openAppSettings" -> openAppSettings(result)
                "setKeepScreenOn" -> {
                    if (call.argument<Boolean>("on") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // GPS 测速高频定位流
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SPEED_CHANNEL)
            .setStreamHandler(GnssSpeedStream(this))
    }

    override fun onDestroy() {
        timeoutHandler.removeCallbacksAndMessages(null)
        pendingPermissionResult?.error("ACTIVITY_DESTROYED", "页面已销毁", null)
        pendingPermissionResult = null
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST_CODE) return
        val granted = permissions.indices.any { i ->
            (permissions[i] == Manifest.permission.ACCESS_FINE_LOCATION ||
                permissions[i] == Manifest.permission.ACCESS_COARSE_LOCATION) &&
                grantResults[i] == PackageManager.PERMISSION_GRANTED
        }
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    /**
     * 申请定位权限：已授予直接成功；系统弹窗结果经
     * [onRequestPermissionsResult] 回传（永久拒绝时返回 false，由 Dart 引导去设置页）。
     */
    private fun requestLocationPermission(result: MethodChannel.Result) {
        val granted = listOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ).any {
            ActivityCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }
        if (granted) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            // 已有弹窗在途，不叠加请求
            result.success(false)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ),
            PERMISSION_REQUEST_CODE
        )
    }

    /** 跳转本应用系统设置页，用于永久拒绝后的手动授权。 */
    private fun openAppSettings(result: MethodChannel.Result) {
        try {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName")
                )
            )
            result.success(null)
        } catch (e: Exception) {
            result.error("FAILED", "无法打开系统设置: ${e.message}", null)
        }
    }

    /**
     * 获取一次当前位置：
     * 1. 遍历可用提供者（北斗/GPS/网络）读取最近缓存位置（毫秒级返回）；
     * 2. 无缓存时请求单次网络定位，[LOCATION_TIMEOUT_MS] 超时兜底。
     */
    private fun getCurrentLocation(result: MethodChannel.Result) {
        val locationManager = getSystemService(LOCATION_SERVICE) as LocationManager

        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED
            && ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION_DENIED", "定位权限未授予", null)
            return
        }

        val providers = locationManager.getProviders(true)

        // 优先取所有提供者中缓存时间最新的位置
        var bestLocation: Location? = null
        for (provider in providers) {
            val lastKnown = locationManager.getLastKnownLocation(provider)
            if (lastKnown != null && (bestLocation == null || lastKnown.time > bestLocation.time)) {
                bestLocation = lastKnown
            }
        }
        bestLocation?.let {
            result.success(
                mapOf(
                    "latitude" to it.latitude,
                    "longitude" to it.longitude,
                    "provider" to (it.provider ?: "unknown")
                )
            )
            return
        }

        if (providers.isEmpty()) {
            result.error("NO_PROVIDER", "无可用定位提供者", null)
            return
        }

        // 无缓存时请求单次定位（优先网络定位，速度更快）
        val provider = if (providers.contains(LocationManager.NETWORK_PROVIDER)) {
            LocationManager.NETWORK_PROVIDER
        } else {
            providers.first()
        }

        // result 只允许回调一次，called 保证超时/禁用/成功互斥
        var called = false
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (!called) {
                    called = true
                    locationManager.removeUpdates(this)
                    result.success(
                        mapOf(
                            "latitude" to location.latitude,
                            "longitude" to location.longitude,
                            "provider" to (location.provider ?: "unknown")
                        )
                    )
                }
            }

            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {
                if (!called) {
                    called = true
                    locationManager.removeUpdates(this)
                    result.error("PROVIDER_DISABLED", "定位提供者已禁用: $provider", null)
                }
            }
        }

        locationManager.requestSingleUpdate(provider, listener, null)

        timeoutHandler.postDelayed({
            if (!called) {
                called = true
                locationManager.removeUpdates(listener)
                result.error("TIMEOUT", "定位超时", null)
            }
        }, LOCATION_TIMEOUT_MS)
    }
}
