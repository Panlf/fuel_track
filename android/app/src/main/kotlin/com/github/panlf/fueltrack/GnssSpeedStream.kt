package com.github.panlf.fueltrack

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.GnssStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel

/**
 * GPS 高频测速事件流。
 *
 * 以最小时间间隔（0ms）与最小距离（0m）订阅 GNSS 定位，把每次定位原样推给
 * Flutter，由 Dart 侧用相邻两点 Haversine 距离差分计算速度。minTime=0 时上报
 * 频率取决于芯片能力（常见 1Hz，部分机型可达 10Hz+）。
 *
 * 事件分两类：
 * - `{"status": "listening", "provider": ...}` 流启动，及 `{"status": "gnss",
 *   "satellites": n}` 卫星数变化（API 24+）；
 * - 无 status 键的为一次定位采样（经纬度/精度/时间等）。
 */
class GnssSpeedStream(private val context: Context) : EventChannel.StreamHandler {

    private var locationManager: LocationManager? = null
    private var locationListener: LocationListener? = null
    private var gnssCallback: GnssStatus.Callback? = null
    private var sink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (events == null) return
        sink = events
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        locationManager = lm

        // 防御：上一次监听未被取消时先移除，避免重复监听泄漏
        removeCallbacks()

        if (!hasLocationPermission()) {
            events.error("PERMISSION_DENIED", "定位权限未授予", null)
            return
        }

        // 优先 GNSS 硬件提供者（"gps" 聚合 GPS/北斗等全部卫星系统），
        // 卫星定位不可用时退回任意已启用提供者（网络定位等）
        val provider = when {
            lm.allProviders.contains(LocationManager.GPS_PROVIDER) &&
                lm.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            else -> lm.getProviders(true).firstOrNull()
        }
        if (provider == null) {
            events.error("NO_PROVIDER", "无可用定位提供者", null)
            return
        }

        events.success(mapOf("status" to "listening", "provider" to provider))

        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                sink?.success(
                    mapOf(
                        "latitude" to location.latitude,
                        "longitude" to location.longitude,
                        "altitude" to location.altitude,
                        "accuracy" to location.accuracy.toDouble(),
                        // 芯片多普勒测速，仅作 Dart 侧差分结果的对照参考
                        "speed" to location.speed.toDouble(),
                        "bearing" to location.bearing.toDouble(),
                        "time" to location.time,
                    )
                )
            }

            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }
        locationListener = listener

        try {
            // minTime=0 / minDistance=0 → 允许的最高上报频率
            lm.requestLocationUpdates(provider, 0L, 0f, listener)
        } catch (e: Exception) {
            events.error("REGISTER_FAILED", "定位监听注册失败: ${e.message}", null)
            return
        }

        // API 24+ 回传参与定位的卫星数，用于页面显示定位质量
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val callback = object : GnssStatus.Callback() {
                override fun onSatelliteStatusChanged(status: GnssStatus) {
                    var used = 0
                    for (i in 0 until status.satelliteCount) {
                        if (status.usedInFix(i)) used++
                    }
                    sink?.success(mapOf("status" to "gnss", "satellites" to used))
                }
            }
            try {
                lm.registerGnssStatusCallback(callback, null)
                gnssCallback = callback
            } catch (_: SecurityException) {
                // 权限在注册间隙被收回时静默放弃卫星统计，不影响测速流
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        removeCallbacks()
        sink = null
    }

    private fun removeCallbacks() {
        locationListener?.let { locationManager?.removeUpdates(it) }
        locationListener = null
        gnssCallback?.let {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                locationManager?.unregisterGnssStatusCallback(it)
            }
        }
        gnssCallback = null
    }

    private fun hasLocationPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
        val coarse = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION)
        return fine == PackageManager.PERMISSION_GRANTED || coarse == PackageManager.PERMISSION_GRANTED
    }
}
