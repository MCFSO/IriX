# 安卓 GPS/北斗时间校准对接文档

| 项目 | 内容 |
|---|---|
| 文档版本 | v1.0（对接草案） |
| 面向对象 | Android/GNSS 侧开发、IriX 时间系统维护者 |
| 目标 | 用手机 GPS/北斗（GNSS）的 UTC 时间校准 IriX 应用时钟，把 24h 保持误差从几十毫秒压到毫秒级 |
| 对接方式 | Android 采集 `GnssTimeSample`，经 FFI 送入 Rust `xmc_time`，由卡尔曼滤波与 NTP 历史融合 |

---

## 1. 背景

IriX 已有一套独立于操作系统的时间系统：

- `zeitstempel` 单调时钟 + TSC 插值；
- `rusty_time-core` NTP 客户端、多源 falseticker；
- 4 状态卡尔曼滤波（偏移、频率、日老化、温度系数）；
- 应用时钟不修改系统时间，HTTPS 证书时间、设备签名、TOTP 等全部以它为准。

当前公网 NTP 的路径不对称和服务器误差通常在 **几毫秒~几十毫秒**，要继续压到 **24h 毫秒级**，需要更接近本地的 UTC 参考——手机 GNSS 是最容易获得的候选：

- GPS/北斗/Galileo 都广播 UTC 可溯源的时间；
- 手机 GNSS 芯片通常有 TCXO，短时稳定度远好于主板晶振；
- 不依赖网络，适合离线/内网/机房场景；
- 原始观测（Raw GNSS）在条件良好时可做到 **亚微秒~几微秒**，明显优于公网 NTP。

目标不是“用手机替换 NTP”，而是让 GNSS 成为 **高权重、可校验的本地参考源**，NTP 作为无 GNSS 时的兜底。

---

## 2. 总体架构

```text
┌──────────────────────── Android 侧 ────────────────────────┐
│ LocationManager / GnssMeasurementsCallback                  │
│   ├─ currentGnssTimeClock()     （粗：ms）                  │
│   ├─ GnssClock + GnssMeasurement（细：ns，Raw GNSS）         │
│   ├─ Location.getTime() + getElapsedRealtimeNanos()          │
│   └─ 质量评估：SV 数、C/N0、fix 类型、星座、uncertainty      │
│                          │                                  │
│                          ▼                                  │
│            GnssTimeSample（JSON / 二进制）                   │
└──────────────────────────┬─────────────────────────────────┘
                           │ FFI（同进程）或本地 socket
┌──────────────────────────▼─────────────────────────────────┐
│ IriX Rust xmc_time                                          │
│  1. 校验 mono_ns 与样本新鲜度                               │
│  2. 计算 offset = utc_ns - app_time(mono_ns)                │
│  3. Kalman update（R = gnss_uncertainty² + 传输/对齐误差²）  │
│  4. 调整应用时钟（step / slew），记录 source=gnss            │
│  5. 与 NTP 结果交叉校验；异常样本降权/丢弃                   │
└────────────────────────────────────────────────────────────┘
```

关键约束：**Android 与 Rust 必须使用同一条单调时间轴**。Android 的
`SystemClock.elapsedRealtimeNanos()` 对应 Linux `CLOCK_BOOTTIME`，与
`zeitstempel` 在 Android 上的 `now_including_suspend()` 同源；样本里必须带
`elapsedRealtimeNanos`，不能只给 UTC。

---

## 3. Android 侧两种采集方案

### 方案 A：`SystemClock.currentGnssTimeClock()`（快速落地，毫秒级）

```kotlin
// API 29+；公开 API，返回 GNSS 时间的 Clock
val utcMs = SystemClock.currentGnssTimeClock().millis()
val monoNs = SystemClock.elapsedRealtimeNanos()
```

- API：`SystemClock.currentGnssTimeClock()`，API 29+；
- 权限：`ACCESS_FINE_LOCATION`（运行时授权）；
- 精度：返回整数毫秒，实际受 fix 质量/芯片时间传递影响，通常 **1~10ms**；
- 优点：实现简单、无需 Raw GNSS；
- 用途：冷启动 bootstrap、Raw GNSS 不可用时的降级、交叉校验；
- 注意：`LocationManager.getGnssTimeMillis()` 不是公开 API，不建议使用。

**建议 uncertainty 至少填 `2_000_000 ns`（2ms）**，不要因为返回值是整数毫秒就填 1ms。

### 方案 B：Raw GNSS（`GnssClock` + `GnssMeasurement`，目标亚微秒~几微秒）

注册原始观测：

```kotlin
val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
val callback = object : GnssMeasurementsEvent.Callback() {
    override fun onGnssMeasurementsReceived(event: GnssMeasurementsEvent) {
        val clock = event.clock
        if (!clock.hasFullBiasNanos()) return
        // 1) GNSS 硬件时钟 -> GPS 时间 -> UTC
        val gpsNs = clock.timeNanos - (clock.fullBiasNanos + clock.biasNanos)
        val utcNs = gpsNs + 315_964_800_000_000_000L - clock.leapSecond * 1_000_000_000L

        // 2) 回调到达时的 CPU 单调时间（注意：包含回调延迟）
        val monoNs = SystemClock.elapsedRealtimeNanos()

        // 3) 质量评估
        val svCount = event.measurements.count {
            (it.state and GnssMeasurement.STATE_CODE_LOCK) != 0
        }
        val bestCn0 = event.measurements.maxOfOrNull { it.cn0DbHz } ?: 0.0
        val uncertaintyNs = estimateUncertaintyNs(clock, event)
        // 上报 GnssTimeSample
    }
}
lm.registerGnssMeasurementsCallback(callback, Handler(Looper.getMainLooper()))
```

关键字段：

| 字段 | 用途 |
|---|---|
| `GnssClock.timeNanos` | 接收机硬件时钟（测量时刻） |
| `GnssClock.fullBiasNanos` / `biasNanos` | 硬件时钟与 GPS 时间的偏差 |
| `GnssClock.leapSecond` | GPS-UTC 闰秒（当前 18s），用于换算 UTC |
| `GnssClock.biasUncertaintyNanos` | 偏差不确定度（1σ） |
| `GnssClock.driftNanosPerSecond` / `driftUncertaintyNanosPerSecond` | 时钟漂移及不确定度 |
| `GnssClock.hardwareClockDiscontinuityCount` | 硬件时钟跳变计数，跳变时样本作废 |
| `GnssMeasurement.constellationType` | GPS/BEIDOU/GALILEO/GLONASS… |
| `GnssMeasurement.svid` / `cn0DbHz` / `state` | 卫星号、载噪比、跟踪状态 |
| `GnssMeasurement.receivedSvTimeNanos` / `timeOffsetNanos` | 需要逐星时间传递时使用 |

**重要：`monoNs` 是回调到达 CPU 的时间，不是 `clock.timeNanos` 对应的 CPU 时刻。**
两者之间存在调度/回调延迟（通常 0.1~5ms，负载高时更大）。有三种处理方式：

1. **推荐（首版）**：把回调延迟计入 `uncertainty_ns`，例如
   `uncertainty = biasUncertainty + drift*age + 2ms`；卡尔曼会自动降权；
2. **进阶**：用连续多帧 `(clock.timeNanos, elapsedRealtimeNanos)` 做线性回归，
   估计 GNSS 硬件时钟到 CPU 单调时钟的映射，再把 UTC 对齐到目标 `monoNs`；
3. 若设备厂商提供 PPS/硬件时间戳接口，优先使用（Android 公共 API 不暴露 PPS）。

#### Raw GNSS 精度预期（室外、天空开阔）

| 条件 | 典型 1σ |
|---|---|
| `SystemClock.currentGnssTimeClock()` | 1~10ms |
| Raw GNSS clock，普通手机、多星座 | 0.1~2µs |
| Raw GNSS clock，高端手机/良好天空 | 50~500ns |
| 室内/城市峡谷/多径严重 | 10µs~ms，应降权或丢弃 |

手机没有 PPS，芯片时间传递、天线群延迟、多径是主要误差；不要承诺固定 100ns。

### 方案 C：`Location` 回调（简单，但只有 ms）

```kotlin
location.time            // UTC ms
location.elapsedRealtimeNanos // 同一 fix 的单调时间
```

适合方案 A 的补充，不推荐作为高精度主路径。

---

## 4. 北斗/多星座注意事项

1. **不要把 GPS 的 18s 闰秒直接套到北斗**。`GnssClock.leapSecond` 是
   GPS-UTC 闰秒；BDS 使用 BDT，BDT 与 UTC 的偏移需按 BDS ICD/芯片输出处理，
   不能假设等于 GPS-UTC。
2. 建议第一阶段只使用 **接收机输出的 UTC**（`SystemClock.currentGnssTimeClock()` 或
   `GnssClock` 换算后的 UTC），北斗作为可见卫星/健康度/冗余校验；
3. 若必须使用 BDS 原始观测，必须同时提供：
   - 星座类型（`CONSTELLATION_BEIDOU`）；
   - BDT-UTC 偏移来源（芯片/厂商/ICD 版本）；
   - 与 GPS/Galileo/UTC 的交叉校验结果；
4. 多星座（GPS+BDS+Galileo）时应按星座分别计算，再做鲁棒加权；不要混用不同
   时间系统的原始秒数。
5. 闰秒更新：`GnssClock.leapSecond` 会随固件/星历更新；样本中带上该值，Rust
   侧只做记录，不自行猜测。

---

## 5. 对接数据契约

### 5.1 FFI op

IriX 侧已提供统一入口 `time_request("gnss_sample", …)`（Rust `xmc_time` 已实现，
Android ABI 打包待补）：

```text
op = "gnss_sample"
args = {
  "utc_ns": 1794493228467212303,       // GNSS 导出的 UTC 纳秒（i64）
  "mono_ns": 1234567890123,            // 同一时刻的 elapsedRealtimeNanos（u64）
  "uncertainty_ns": 800,               // 1σ，纳秒；必须诚实
  "constellation": "gps",              // gps | bds | galileo | glonass | multi
  "sv_count": 12,                      // 参与解算的卫星数
  "fix": "3d",                         // none | 2d | 3d
  "leap_seconds": 18,                  // GPS-UTC；BDS 另带 bdt_utc_offset_s
  "source": "raw",                     // raw | gnss_time_millis | location
  "clock_discontinuity": 0,            // GnssClock 的 discontinuity count
  "age_ms": 2,                         // 样本从测量到送达的年龄
  // 可选：对齐方式与跨设备传输延迟
  "alignment": "gnss_elapsed_realtime",// gnss_elapsed_realtime | callback_unbounded | rtt_aligned
  "transport_delay_ns": 1500000,       // 跨设备单程延迟；同设备可省略
  "transport_delay_uncertainty_ns": 200000
}
```

返回：

```json
{"ok": true, "data": {"accepted": true, "offset_ms": -0.42,
  "rate_ppm": 3.1, "uncertainty_ms": 0.5, "reason": null}}
```

Rust 侧处理规则：

1. `mono_ns` 与本地单调时钟差 ≤2s：同设备/同轴，直接用 `mono_ns` 对齐；
   >2s：视为跨设备，必须提供 `transport_delay_ns`，否则拒绝；
2. `utc_ns` 必须在合理范围（2020~2200）；
3. `uncertainty_ns` 下限 **100ns**（防止虚报），上限 **50ms**（超过则不作为高精度源）；
4. `fix != "3d"` 或 `sv_count < 5`：降权（R 乘 10）或只做监控；
5. `clock_discontinuity` 变化：丢弃该帧；
6. 同设备：`offset = utc_ns - clock.raw_at(mono_ns)`；
   跨设备：`offset = utc_ns + age + transport_delay - clock.raw_at(now)`，
   跨设备默认 R ×100（无 RTT 对消时 Wi-Fi 抖动主导）；
7. 卡尔曼 update，`R = uncertainty_ns² + app_clock_uncertainty² + age²`
   （跨设备再加 `transport_delay_uncertainty²`，默认 5ms）；
8. 若 GNSS 与 NTP 的 offset 差超过 5σ，记录异常但**不立刻拨钟**，等下一帧；
9. 连续 3 帧一致才允许 step，避免单帧多径/欺骗；前两帧只做有界 drain。

### 5.2 时间轴对齐要求

- `mono_ns` 必须是 `SystemClock.elapsedRealtimeNanos()`（含 suspend 的 BOOTTIME）；
- 不能使用 `System.nanoTime()`（它对应 `CLOCK_MONOTONIC`，不含 suspend，和
  `zeitstempel` 的 BOOTTIME 不同源）；
- 若 Android 侧只能提供 `Location.elapsedRealtimeNanos()`，也可以，但要确保它和
  `utc_ns` 来自同一个 fix；
- Rust 侧会再用 `zeitstempel::now()` 做一次交叉检查：同设备偏差 >2s 时视为
  跨设备；跨设备必须提供 `transport_delay_ns`，并按到达时刻对齐，
  否则直接拒绝（不能把两条 BOOTTIME 轴相减）。

### 5.3 频率/老化

GNSS 样本不仅提供偏移，也让卡尔曼的 **频率、日老化、温度系数** 收敛更快：

- 连续 GNSS 样本（1Hz，几分钟）即可把频率估计压到 0.01ppm 量级；
- 温度变化时，GNSS 是“真值”，可用来学习 `temp_coeff`；
- 断网后 GNSS 仍可用，所以 24h 保持误差不再只依赖晶振自由漂移。

---

## 6. Android 集成清单

### 6.1 权限与前台服务

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<!-- 后台持续采集时 -->
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

- Android 6+ 运行时申请 `ACCESS_FINE_LOCATION`；
- Android 10+ 后台定位需单独引导；
- Android 12+ 用户可能只给 approximate location，必须检查
  `ACCESS_FINE_LOCATION` 是否真正授予；
- 长时间采集用前台服务，通知栏说明“时间校准”；
- Android 14 前台服务类型声明 `location`。

### 6.2 设备能力检查

```kotlin
val caps = lm.gnssCapabilities // API 31+
// 低版本可用 GnssStatus.Callback 观察星座；
// 通过 GnssMeasurement 是否回调判断 Raw GNSS 是否可用
```

- 不是所有手机都支持 Raw GNSS；不支持时自动降级到方案 A；
- 部分机型只支持 GPS，不输出 BDS；不要假设 BDS 一定可用；
- 检查 `GnssClock.hasFullBiasNanos()`，没有就无法算绝对 UTC。

### 6.3 Rust `xmc_time` Android 产物

Irix Android 原生 App（`D:\Irix-android`）已接入同进程 JNI：

- `app/src/main/jniLibs/arm64-v8a/libxmc_time.so`（API 23，`aarch64-linux-android`）；
- JNI shim：`app/src/main/cpp/time_jni.c` + `CMakeLists.txt`；
- Kotlin：`org.mcfso.irix.gnss.TimeNative`，通过 `System.loadLibrary("xmc_time")`
  加载，`TimeNative.ingest(GnssWire.argsJson(sample))` 送入 `gnss_sample`；
- `GnssCalibrationController` 用 `TimeNative.nowUnixMsOrSystem()` 作为诊断时间戳，
  库缺失时自动回退系统时钟；
- 构建脚本：`D:\Irix-android\tool\build_xmc_time_android.ps1`
  （NDK 28、API 23、arm64-v8a）。

仍需补：

- `armeabi-v7a` / `x86_64` ABI 的 `libxmc_time.so` 与 Gradle `abiFilters`；
- 原生 App 若要通过 `xmc_time_tls` 校验 HTTPS 证书，需要把 `time_tls` 的
  rustls `TimeProvider` 也接进 JNI/OkHttp（当前只嵌入时钟与 GNSS 融合）；
- `high_precision_clock` 仅 x86_64 可用；ARM 手机自动退回 `zeitstempel`，
  GNSS 时间仍然有效。

---

## 7. 精度目标与验收标准

### 7.1 单次 GNSS 样本

在室外、天空开阔、静止或慢速移动条件下，连续采集 ≥10 分钟：

| 指标 | 合格 | 良好 | 优秀 |
|---|---|---|---|
| Raw GNSS 相对 NTP/UTC 的 1σ | ≤10µs | ≤2µs | ≤500ns |
| `currentGnssTimeClock` 相对 NTP 的 1σ | ≤20ms | ≤10ms | ≤5ms |
| 样本年龄（测量→Rust） | ≤100ms | ≤20ms | ≤5ms |
| 有效样本率（1Hz） | ≥80% | ≥90% | ≥95% |

> NTP 本身有 ms 级误差，只能作为交叉参考；有条件时用已知 UTC 的实验室参考或
> 第二台已校准设备对比。

### 7.2 24h 保持

流程：

1. GNSS 校准 ≥30 分钟，让卡尔曼频率/老化收敛；
2. 关闭网络（或禁用 NTP），保持应用运行；
3. 24h 后与同一 GNSS/UTC 参考比较。

| 场景 | 目标 |
|---|---|
| TCXO + Raw GNSS + 温度稳定 | ≤1ms |
| 普通手机 + Raw GNSS + 室内温度变化 | ≤5ms |
| 仅毫秒时钟 | ≤20ms |
| 无 GNSS、仅 NTP 历史 | 几 ms~几十 ms（取决于晶振） |

**注意**：手机 GNSS 在室内会失锁；失锁后进入 holdover，误差按晶振漂移/温度模型
增长。验收必须区分“GNSS 持续可用”和“校准后失锁”两种场景。

### 7.3 必须记录的测试数据

- UTC 时间、`elapsedRealtimeNanos`、`uncertainty_ns`；
- 星座、SV 数、C/N0、fix 类型；
- `GnssClock` 的 bias/drift/leapSecond/discontinuity；
- 与 NTP/系统时钟的差值；
- 设备型号、Android 版本、芯片型号、室内/室外、温度。

---

## 8. 职责划分

### Android/GNSS 侧

- [ ] 实现方案 A（`SystemClock.currentGnssTimeClock`）作为保底；
- [ ] 实现方案 B（Raw GNSS），输出 `GnssTimeSample`；
- [ ] 权限/前台服务/省电策略；
- [ ] 设备能力检测与降级；
- [ ] 采集测试日志（≥24h，含失锁/温度变化）；
- [ ] 与 IriX 确认 `mono_ns` 对齐方式和 `uncertainty_ns` 估算；
- [ ] 提供一台测试机（型号/Android 版本/芯片）。

### IriX 时间系统侧

- [ ] `xmc_time` Android ABI 构建与打包（`libxmc_time.so`，arm64-v8a/armeabi-v7a/x86_64）；
- [x] `gnss_sample` FFI op 与卡尔曼融合（`Service::ingest_gnss`）；
- [x] GNSS 校验/拒收/降权、`GnssStatus` 状态；
- [x] 状态页显示 GNSS 来源/星座/SV/不确定度/采纳数；
- [ ] GNSS/NTP 5σ 交叉校验的统计报表；
- [ ] 24h holdover 自动化测试；
- [x] 更新 `docs/time-system.md` 与用户说明。

> 当前 Rust 侧已可通过 `time_request("gnss_sample", …)` 接收样本并驱动应用时钟；
> Android 采集端与 ABI 打包是下一步联调工作。

---

## 9. 风险与待确认问题

1. **Raw GNSS 可用性**：目标机型是否支持 `GnssMeasurementsCallback`？是否输出 BDS？
2. **`mono_ns` 对齐**：Android 侧能否提供与 `GnssClock` 同帧的
   `elapsedRealtimeNanos`？回调延迟分布是多少？
3. **BDT-UTC**：芯片/固件是否给出 BDT 与 UTC 的偏移？版本/闰秒如何更新？
4. **手机省电策略**：息屏/后台是否会降低 GNSS 频率或停止回调？
5. **室内/地下车库**：失锁后的 holdover 目标是否接受几 ms~几十 ms？
6. **设备差异**：不同厂商 GNSS 天线/芯片时间传递差异可能达 10 倍，是否需要
   按机型标定？
7. **安全**：GNSS 欺骗/多径会导致错误时间；是否需要多星座一致性检查、
   与 NTP 交叉校验、最大变更保护？（IriX 侧默认有 5σ/最大变更保护）

---

## 10. 附录

### 10.1 Raw GNSS UTC 计算（首版）

```kotlin
// 仅在 hasFullBiasNanos() 为 true 时使用
val gpsNs = clock.timeNanos - (clock.fullBiasNanos + clock.biasNanos)
// gpsNs 从 1980-01-06 起算；GPS 纪元到 Unix 纪元 = 315964800 s
val utcNs = gpsNs + 315_964_800_000_000_000L - clock.leapSecond * 1_000_000_000L
val ageSeconds = 1.0
val uncertaintyNs = (clock.biasUncertaintyNanos +
    abs(clock.driftUncertaintyNanosPerSecond) * ageSeconds +
    callbackLatencyNs).toLong()
```

- `fullBiasNanos` 缺失时不能算绝对 UTC；
- `leapSecond` 是 GPS-UTC，不是 BDT-UTC；
- 回调延迟必须计入 `uncertaintyNs`，或做硬件时钟到 CPU 单调时钟的回归。

### 10.2 参考链接

- Android `LocationManager.getGnssTimeMillis()`：
  <https://developer.android.com/reference/android/location/LocationManager#getGnssTimeMillis()>
- Android `GnssClock`：
  <https://developer.android.com/reference/android/location/GnssClock>
- Android `GnssMeasurement`：
  <https://developer.android.com/reference/android/location/GnssMeasurement>
- Android GNSS Raw Measurements（Google）：
  <https://developer.android.com/guide/topics/location/gnss-measurements>
- 北斗系统时间（BDT）官方说明：
  <http://en.beidou.gov.cn/SYSTEMS/Officialdocument/>

### 10.3 最小可用联调顺序

1. Android 用 `SystemClock.currentGnssTimeClock()` + `elapsedRealtimeNanos()` 上报，Rust 只记录
   不拨钟，确认时间轴对齐；
2. 户外 Raw GNSS 上报，比较 `utc_ns` 与 NTP，统计 offset/σ；
3. Rust 侧打开 GNSS 权重，观察卡尔曼 `freq/aging/temp_coeff`；
4. 断网 24h 测试；
5. 室内失锁/温度变化测试；
6. 多机型/多星座回归。

---

**结论**：Android GNSS 是 IriX 时间系统从“公网 NTP 毫秒级”走向“本地参考
亚微秒级”的关键输入。首版建议毫秒时钟保底 + Raw GNSS 主路径，
严格上报 `uncertainty_ns` 与 `elapsedRealtimeNanos`，由 IriX 卡尔曼滤波统一融合；
24h 毫秒级目标在 TCXO/良好天空/稳定温度下可期，普通手机+室内环境需按上表
设定合理验收值。
