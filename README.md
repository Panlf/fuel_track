# FuelTrack

一款极简的燃油车油耗追踪应用，所有数据存储在本地，无需注册、无需联网。

## 功能

- **加油记录** — 记录每次加油的里程、油量、单价、金额、加油站等信息
- **油耗统计** — 自动计算平均油耗，生成油耗趋势折线图
- **月度费用** — 柱状图展示最近 6 个月的加油花费
- **多车管理** — 支持添加多辆车，一键切换
- **数据导出** — 一键导出 Excel 文件，方便备份和分析

## 设计理念

- **极简** — 没有账号系统，没有云端同步，打开就用
- **本地优先** — 所有数据存储在设备本地 SQLite 数据库，你的数据只属于你
- **零依赖服务** — 不需要任何后端服务器，不需要网络权限

## 技术栈

- Flutter + Dart
- SQLite (sqflite) 本地数据库
- fl_chart 图表库
- shared_preferences 轻量配置存储

## 定位方案

本项目需要定位用户所在省份以查询当地油价。经过多轮调研和实测，总结了三种方案：

### 方案一：geolocator + geocoding（已弃用）

**原理**：Flutter 社区常用方案。`geolocator` 通过 Google Play Services 的 `FusedLocationProviderClient` 获取坐标，`geocoding` 通过 Android 系统 `Geocoder` 将坐标转为地址。

| 优点 | 缺点 |
|------|------|
| Flutter 生态成熟，API 简洁 | 依赖 Google Play Services，国内手机普遍缺失或被阉割 |
| 自动处理权限请求 | 定位失败率高，室内基本无法定位 |
| - | 逆地理编码依赖 Google 地址数据库，国内数据过时|
**实测结果**：国内 Android 设备上定位失败率极高，不可用。



### 方案二：原生 LocationManager + 系统 Geocoder（当前方案）

**原理**：通过 MethodChannel 调用 Android 原生 `LocationManager`，直接使用设备的北斗/GPS/网络定位能力。逆地理编码继续使用 Android 系统 `Geocoder`，国产手机厂商通常预装高德或 Petal Maps 数据。

**定位策略**：
1. 优先调用 `getLastKnownLocation` 读取系统缓存位置（毫秒级返回）
2. 无缓存时调用 `requestSingleUpdate` 请求一次定位（优先网络定位，10 秒超时）

| 优点 | 缺点 |
|------|------|
| 不依赖 Google Play Services，支持北斗/GPS/网络多模定位 | 逆地理编码依赖厂商预装地图数据，冷门机型可能不支持 |
| 速度快，`getLastKnownLocation` 毫秒级返回 | 国产手机厂商预装高德/Petal Maps 数据，逆地理编码可靠  |
| - |无缓存时需要网络（网络定位依赖 WiFi/基站数据库）|


**实测结果**：目前手机上定位秒出，省份暂时识别正确。



### 方案三：高德/百度地图 SDK（可选优化）

**原理**：接入高德地图或百度地图的 Flutter SDK，使用其定位和逆地理编码 API。这些 SDK 内置了完整的国内地图数据，支持 GCJ-02 坐标系处理。

| 优点 | 缺点 |
|------|------|
| 国内数据最新最全，逆地理编码 100% 可靠 | 需要申请 API Key（免费但需注册） |
| 完美处理 GCJ-02 坐标偏移 | 增加 APK 体积（高德 SDK 约 5-10MB） |
| 支持室内定位、WiFi 定位等高级功能 | 引入第三方依赖，后续维护成本 |
| 无需 Google Play Services | - |

**实测结果**：未接入。作为方案二的备选，当系统 Geocoder 不可靠时可考虑。



### 方案选择建议

| 场景 | 推荐方案 |
|------|---------|
| 国内 Android 设备（主流品牌） | 方案二：原生 LocationManager |
| 需要 100% 可靠的逆地理编码 | 方案三：高德/百度 SDK |
| 国际市场或需要跨平台一致性 | 方案一：geolocator（需保证 Google Play Services 可用） |