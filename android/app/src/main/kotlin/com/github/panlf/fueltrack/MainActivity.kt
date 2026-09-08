package com.github.panlf.fueltrack

import android.Manifest
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.github.panlf.fueltrack/location"
        private const val LOCATION_TIMEOUT_MS = 10_000L
    }

    /** 定位超时调度器，页面销毁时统一回收，避免向已分离的引擎回传结果。 */
    private val timeoutHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getCurrentLocation") {
                getCurrentLocation(result)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        timeoutHandler.removeCallbacksAndMessages(null)
        super.onDestroy()
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
