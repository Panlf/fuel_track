package com.github.panlf.fueltrack

import android.Manifest
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.github.panlf.fueltrack/location"

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

    private fun getCurrentLocation(result: MethodChannel.Result) {
        val locationManager = getSystemService(LOCATION_SERVICE) as LocationManager

        // 检查权限
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED
            && ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION_DENIED", "定位权限未授予", null)
            return
        }

        // 获取所有可用的定位提供者（支持北斗、GPS、网络等）
        val providers = locationManager.getProviders(true)
        var bestLocation: Location? = null

        // 先尝试获取上次已知位置（最快）
        for (provider in providers) {
            val lastKnown = locationManager.getLastKnownLocation(provider)
            if (lastKnown != null) {
                if (bestLocation == null || lastKnown.time > bestLocation.time) {
                    bestLocation = lastKnown
                }
            }
        }

        if (bestLocation != null) {
            val map = hashMapOf(
                "latitude" to bestLocation.latitude,
                "longitude" to bestLocation.longitude,
                "provider" to (bestLocation.provider ?: "unknown")
            )
            result.success(map)
            return
        }

        // 没有缓存位置，请求单次定位
        if (providers.isEmpty()) {
            result.error("NO_PROVIDER", "无可用定位提供者", null)
            return
        }

        val provider = if (providers.contains(LocationManager.NETWORK_PROVIDER)) {
            LocationManager.NETWORK_PROVIDER
        } else {
            providers.first()
        }

        var called = false
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (!called) {
                    called = true
                    locationManager.removeUpdates(this)
                    val map = hashMapOf(
                        "latitude" to location.latitude,
                        "longitude" to location.longitude,
                        "provider" to (location.provider ?: "unknown")
                    )
                    result.success(map)
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

        // 10秒超时
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            if (!called) {
                called = true
                locationManager.removeUpdates(listener)
                result.error("TIMEOUT", "定位超时", null)
            }
        }, 10000)
    }
}
