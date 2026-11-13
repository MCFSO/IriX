# IriX 统一时间系统（xmc_time）

> 目标：应用内所有“现在”都来自同一个可解释、可校准、可审计的时间权威；
> 不再让每个 Rust crate / Dart 页面各自调用 `SystemTime::now()` / `DateTime.now()`。
> 时间系统同时是 HTTPS 证书有效期、设备绑定签名、TOTP、备份/日志/编排时间戳的依据。

## 1. 设计原则

1. **不修改操作系统时钟**。只维护应用自己的虚拟时钟，因此无需管理员权限，
   也不会影响其它进程；进程退出后系统时间保持不变。
2. **单调优先**。绝对时间由“单调时钟 + 偏移 + 频率修正”推导，避免系统时间被
   手动调整、NTP 步进或夏令时造成的时间倒退。
3. **可信来源 + 多源投票**。默认使用多个公共 NTP 服务器，按 RFC 5905 的
   falseticker 区间投票剔除说谎/故障源；单源可达时才允许单源工作。
4. **安全默认值**。随机 nonce 防 off-path 伪造、最大变更保护、HTTP `Date`
   只做偏差诊断绝不直接拨钟、HTTPS 证书时间由本系统裁决。
5. **降级不失败**。动态库缺失、NTP 全不可达、TSC 不稳定时逐级退化到
   `zeitstempel` / 操作系统时间，应用功能不中断。

## 2. 分层与 crate

| crate | 类型 | 职责 |
|---|---|---|
| `rust/time_base`（`xmc_time_base`） | rlib | `zeitstempel` 单调时钟、日历/HTTP 日期、跨 DLL 时间桥 |
| `rust/time`（`xmc_time`） | **cdylib**（`xmc_time.dll` / `.so` / `.dylib`） | NTP 客户端、纪律环、应用时钟、持久化、FFI |
| `rust/time_tls`（`xmc_time_tls`） | rlib | rustls `TimeProvider` + 根证书配置，供 http_client / downloader 使用 |

`time_base` / `time_tls` 是纯 rlib，不产出动态库；`tool/ffi_dlls.dart` 只审计
声明了 `crate-type = [..., "cdylib"]` 的成员，因此它们不会出现在 7 个 FFI 清单里。

### 跨 DLL 时间桥

每个 `xmc_*.dll` 在 Windows 上是独立模块，静态变量不共享。`xmc_time_base::link`
在运行时按以下顺序加载 `xmc_time.dll` 并调用其导出的 C 函数：

1. 可执行文件所在目录；
2. macOS `Contents/Frameworks` / `Resources`；
3. 当前工作目录、`windows/runner`、`linux`、`macos`；
4. 系统搜索路径。

找到后使用 NTP 校准后的应用时间；找不到（例如单独跑
`cargo test -p xmc_http_client`）则以 `zeitstempel` 单调时钟锚定首次读取的系统时间，
保证功能可用且不倒退。桥的导出函数刻意命名为 `xmc_time_*`，避免与各 crate
自己的 `free_string` / `get_last_error` 冲突（这是早期版本链接失败的根因）。

## 3. 时钟模型

```text
app_time(mono) = anchor_unix + (mono - anchor_mono) * (1 + rate_ppm * 1e-6)
                 + drain(mono)
```

- `mono`：`zeitstempel::now()`（Linux `CLOCK_MONOTONIC` / Windows QPC /
  macOS `mach_continuous_time`），跨线程一致且包含系统挂起时间；
- `rate_ppm`：实际施加给应用时钟的总频率修正 =
  `kf.freq_ppm + kf.temp_coeff*(T - T_ref)`（正 = 本机慢，需要走快）；
- `drain`：把残余偏移在限定时间内消化掉的临时速率，**有预算**；
- 每次改速率/步进前先 `rebase`，把已走过的修正固化进锚点，保证时间连续；
- `high_water`：进程内单调性保护。向后步进时输出短暂冻结（最多 5 秒）；
  超过 5 秒的向后跳变如实回退并记录 `backward_jumps`，避免应用被“冻死”。

不确定度 `uncertainty_ns = 上次同步误差 + holdover_ppm × 离线时长`，随断网时间
线性增长；`holdover_ppm` 默认 15（24h ≈ 1.3s），可在配置里按本机晶振调整。
权限判断/UI 用 `locked`（近期同步且不确定度 <10ms）区分“已同步”和“保持模式”。

## 4. NTP 客户端

协议编解码、偏移/时延运算、回归滤波、纪律环全部来自
[`rusty_time-core`](https://crates.io/crates/rusty_time-core)（rusty_time 的 NTP 引擎）；
本 crate 只做 I/O 与安全校验。

### 交换流程

1. 解析 `host[:port]`（支持 IPv4/IPv6/自定义端口），UDP `connect` 到服务器；
2. 生成 CSPRNG nonce 作为请求 `transmit_ts`（**不是**本机时间，防 off-path 伪造）；
3. 在 `send` 前记录 t1、在 `recv` 后记录 t4，均走应用时钟 + TSC 插值；
4. 校验响应：
   - 源地址由 UDP `connect` 内核过滤；
   - `origin_ts == nonce`；
   - `mode == Server`、版本 3/4、stratum 1..=15；
   - `leap != 3`、receive/transmit 非 0；
   - RTT 在 `-2ms .. 5s`；
   - stratum 0 视为 Kiss-o'-Death，读取 reference id 并退避；
5. `offset_delay(t1,t2,t3,t4)` 得到偏移/时延，连同服务器 root dispersion、
   precision 组成 `Sample`。

### 多源与纪律

- 每个服务器一个 `SampleRegister`（rusty_time 的加权线性回归窗口）；
- 每轮可发 `samples_per_poll` 个样本（默认 2，间隔 20ms）；
- `select()` 用区间交集找出 truechimers，按 stratum + root distance 选最优源；
- 只有被选中的源调用 `steer()`，但所有源的样本都进入各自窗口；
- `Discipline` 决定 step / slew / drain，并持有最大变更保护与 leap 处理；
- `poll_drain` 在 drain 预算用尽时由后台线程精确唤醒，保证纪律环账本与实际
  时钟一致（否则会把“没走完的修正”记成已完成，产生固定偏差）。

默认配置（可在 UI / FFI 修改）：

```text
servers          ntp.aliyun.com, ntp.tencent.com, cn.pool.ntp.org, time.cloudflare.com
min/max poll     2^4 (16s) .. 2^8 (256s)
samples_per_poll 2
step threshold   0.5s（前 4 次更新内）
max change       7 天（前 5 次更新豁免，用于修复严重错误的系统时钟）
holdover_ppm     15（断网保持漂移预算，可按晶振调整）
```

## 5. 卡尔曼滤波：偏移、频率、老化、温度

`rust/time/src/kalman.rs` 用 4 状态卡尔曼滤波取代了原先“回归斜率 + 纪律环累加”
的频率模型：

```text
x = [ offset_s, freq_ppm, aging_ppm_per_day, temp_coeff_ppm_per_c ]
```

- `offset_s`：需要加到本地时钟上的时间（正 = 本地慢）；
- `freq_ppm`：参考温度 `T_ref` 下需要施加的频率修正；
- `aging_ppm_per_day`：日老化率（频率每天变化多少 ppm）；
- `temp_coeff_ppm_per_c`：每升高 1°C 所需频率修正的变化量。

预测（`dt` 秒、温度 `T`）：

```text
offset += (freq + temp_coeff*(T - T_ref)) * 1e-6 * dt
          + 0.5 * aging * 1e-6 * dt^2 / 86400
freq   += aging * dt / 86400
```

观测只有 NTP 偏移（`H=[1,0,0,0]`），观测噪声 `R` 由 RTT/2、root dispersion、
批量时间戳不确定度合成。卡尔曼输出直接驱动应用时钟：

```text
clock.rate_ppm = freq + temp_coeff*(T - T_ref)
offset 用于纪律环的 step / drain 决策
```

**职责划分**：`MultiController` 的逐源回归现在只用于 falseticker 预筛和
step/drain 策略；真正决定时钟速率、老化、温度补偿的是卡尔曼状态。
`freq_ppm` 传给纪律环时设为 `None`，避免旧模型再次累加频率。

### 5.1 批量时间戳与调度抖动

`precise::batch_stamp(samples)` 在一次 NTP 收发前后各做 9 次 `(TSC, 单调时钟)`
采样：

1. 用 TSC→单调时钟的线性关系拟合；
2. 用残差中位数/MAD 剔除被调度器打断的离群点；
3. 在最后一个 TSC 采样点外推，返回 `mono_ns + uncertainty_ns + spread_ns`；
4. 不确定度直接加进 `Sample.dispersion`，最终进入卡尔曼的 `R`。

这不是“让时间戳没有误差”，而是**如实量化**时间戳误差：调度抖动越大，卡尔曼
越不会把这一帧当成高精度观测。配合 TSC 插值，正常桌面上的 t1/t4 读出不确定度
通常在几十纳秒到几微秒。

### 5.2 温度输入

`rust/time/src/thermal.rs`：

- Linux 读 `/sys/class/thermal/thermal_zone*/temp` 与
  `/sys/class/hwmon/hwmon*/temp*_input`（毫摄氏度），取可用传感器最大值；
- Windows/macOS 没有稳定的用户态温度接口，返回 `None`，由 Dart 侧通过
  FFI `time_request("temperature", {"celsius": …})` 注入；
- EMA（α=0.2）+ 60s 节流，避免把传感器噪声当成真实温度变化；
- 卡尔曼在线学习 `temp_coeff`；如果传感器测的不是晶振温度，学习到的是
  “机箱热环境→晶振”的等效系数，物理上仍会残留误差。

### 5.3 日老化率

`aging_ppm_per_day` 是卡尔曼第三状态：频率每天变化多少 ppm。预测时
`freq += aging * dt / 86400`，因此：

- 断网保持时频率会按老化率继续演化，而不是假设永远不变；
- 热启动时 `KalmanSnapshot` 持久化频率、老化率、温度系数与协方差对角，
  重启后继续沿用，不需要从 0 重新学习；
- 老化率是弱可观测量，靠长时间 NTP 历史慢慢收敛，状态里同时给出
  `aging_sd_ppm_day`，不要把估计值当成精确真值。

### 5.4 GNSS（GPS/北斗）融合

`Service::ingest_gnss` / FFI `time_request("gnss_sample", …)` 接收 Android 侧
GNSS 时间样本（接口与验收见
[`docs/android-gnss-time-calibration.md`](android-gnss-time-calibration.md)）：

- 输入：`utc_ns`、`mono_ns`（`elapsedRealtimeNanos`）、`uncertainty_ns`、
  `constellation`、`sv_count`、`fix`、`leap_seconds`、`source`、
  `clock_discontinuity`、`age_ms`，以及可选 `alignment`/`transport_delay_ns`；
- 校验：UTC 范围、不确定度 100ns~50ms、discontinuity 不变、fix 非 none、
  卫星数 ≥3；2D/少星降权；`mono_ns` 差 ≤2s 视为同轴，否则视为跨设备并要求
  `transport_delay_ns`（禁止两条 BOOTTIME 轴直接相减）；
- 观测方差 `R = uncertainty² + age²`，GNSS 通常远小于 NTP，卡尔曼会自动高权重；
- 同设备小残差用 ≤5% 的 drain 消化；连续 3 帧一致且 ≥step_threshold 才 step；
- 成功时 `sync.source = "gnss:<constellation>"`、`stratum=0`，不依赖 NTP 服务器；
- `GnssStatus` 记录最近星座/SV/fix/不确定度/对齐方式/采纳数/拒绝原因，UI 单独展示；
- `gnss_hello` 握手声明 `mono_axis_scope=device_boot` 与
  `external_axis_mapping=required`，避免接收端默认同轴。

### 5.5 ADB reverse 时间桥

`rust/time/src/gnss_bridge.rs` 提供本机 TCP 接收端，供原生 Android App 通过 USB
（`adb reverse`）把 GNSS 样本送到桌面 `xmc_time`：

- 默认监听 `127.0.0.1:47820`，token 默认 `irix-adb`；
- 协议：`gnss_hello`（token/协议/时间轴）→ `gnss_ping`（手机测 RTT）→
  `gnss_sample`（带 `rtt_ns`）；
- 接收端用 `transport_delay_ns = rtt/2`、`transport_delay_uncertainty_ns = rtt/4`
  调用 `ingest_gnss`，`alignment=adb_reverse`；
- 手机与桌面仍是两条 BOOTTIME 轴，**不直接相减**；
- 只有 `127.0.0.1`，不暴露 LAN；ADB reverse 负责 USB 端口映射；
- FFI：`gnss_bridge_start` / `gnss_bridge_stop` / `gnss_bridge_status`；
- 桌面 `TimeService.initialize()` 自动启动，手机 App 采集时自动连接并重连。

### 5.6 温度/日老化长基线收敛

KF 的 `aging` / `temp_coeff` 是弱可观测量，几分钟的 NTP 数据只能学 offset。
`rust/time/src/trend.rs` 增加长基线趋势：

- 每 5 分钟记录一个 `(unix_s, KF 频率, 温度)` 点，最多 7 天；
- 联合最小二乘 `freq ≈ f0 + aging*days + temp_coeff*(T-T_ref)`，避免时间趋势
  和温度趋势互相污染；
- 老化要求跨度 ≥6h、≥12 点、标准误 ≤5ppm/day；
- 温度系数要求温差 ≥1°C、≥12 点、标准误 ≤5ppm/°C；
- 只有拟合标准误优于 KF 当前方差时才写回 `aging`/`temp_coeff`，避免短数据
  “学出”假参数；
- 趋势点随 `state.json` 持久化，重启后继续累计；
- UI“精度提升”显示学习点数、时间跨度、温差、老化/温度是否收敛。

温度来源：Linux 读 thermal/hwmon；Android 通过 JNI 注入电池温度（仅环境代理，
不声称等于晶振温度）；Windows/macOS 暂无稳定内核温度接口，温度系数会保持
“学习中”，需要外部注入或使用 Linux/TCXO 设备才能收敛。

### 5.7 和操作系统时间比，准在哪里

两者最终都来自同一颗晶振，**绝对精度上限相同**；IriX 的优势不是“换了一颗更准的
晶振”，而是：

- **不信任系统时钟**：即使 Windows 时间服务被关掉、系统时间被手动改错，只要 NTP
  可达，应用时间仍然正确；
- **算法更好**：卡尔曼融合历史 NTP、温度、老化；批量时间戳量化抖动；多源
  falseticker；有预算的 drain；
- **单调、可审计**：不跟随系统时钟跳变，`step/slew/drain`、频率、老化、温度系数
  与不确定度都可解释；
- **分辨率更高**：TSC 插值 + 批量采样，把时间戳做到亚百纳秒/亚微秒级。

但要说清楚：**如果操作系统本身已经由同一个 NTP 源良好同步，IriX 不会神奇地比
UTC 更准**——两者受同样的网络不对称和服务器精度限制。IriX 通常胜在“系统时钟
没同步/被改错/经常跳变”的机器上；在一台已经精准对时的机器上，两者应当接近。

`status.system_skew_ms`（UI“与系统时间偏差”）就是应用时钟减系统时钟的实时差值，
可以直接看到我们相对系统时间修正了多少毫秒。

## 6. 精度提升与物理误差分析

### 6.1 TSC 插值

- 在 x86_64 上使用 [`high_precision_clock`](https://crates.io/crates/high_precision_clock)
  的 `SimpleHighPrecisionClock` 读取 `rdtsc`，在两次 `zeitstempel` 采样之间做
  亚百纳秒插值；
- 用最近 8 组 `(tsc, mono)` 做最小二乘拟合，斜率吸收 TSC 与单调时钟的频率差；
- 每 250ms 采样一次；拟合斜率允许 0.5~2.0（`high_precision_clock` 内部标定只有
  20ms，绝对比例可能偏离 1），与同刻单调时钟偏差超过 100µs 立即重置；
  连续失败 3 次整体禁用，退回纯 `zeitstempel`；
- 仅在需要高精度时间戳的路径生效（`AppClock::now` / NTP t1/t4）；ARM
  （Apple Silicon / Windows on ARM）自动不可用，状态里如实显示 `available=false`。

> 为什么不用 PTP：桌面环境的网卡/交换机普遍不支持 IEEE 1588 硬件时间戳，
> 纯软件 PTP 的精度收益不如本机 TSC 插值，且需要组播/主时钟配置。协议层
> 已经通过 `rusty_time_core::refclock`/`Sample` 预留了接入点。

### 6.2 24 小时误差的物理上限

频率误差 `ε`（ppm）在时间 `T` 上累积的时间误差：

```text
Δt = ε × 10^-6 × T
```

| 日频率误差 | 24h 时间误差 |
|---|---|
| 1 ppm | 86.4 ms |
| 0.1 ppm | 8.64 ms |
| 0.01 ppm | 0.864 ms |
| 0.001 ppm | 0.086 ms |

**要把 24h 误差压到 1 ms，残余频率误差必须小于 0.0116 ppm。** 这是硬指标，
卡尔曼滤波只能逼近它，不能违反它。

误差来源分解：

1. **NTP 测量噪声**：偏移噪声 `σ_θ`（几 ms 公网、几十 µs 局域网）与历史跨度
   `T_obs` 决定频率估计的统计下限：
   `σ_f ≈ sqrt(12/N) × σ_θ / T_obs`。以 σ_θ=1ms、T_obs=24h、N=1440 估算，
   统计项约 0.0006 ppm（<1ms/day），但要求噪声零均值、路径不对称不随温度/路由
   变化；现实中这些系统性误差才是主项。
2. **温度**：普通 AT-cut 晶振在 25°C 附近约 0.5~2 ppm/°C；1°C 变化就是
   43~173 ms/day。要把温度项压到 0.01 ppm，需要温度模型误差 <0.005~0.02°C——
   主板/CPU 传感器测的不是晶振温度，通常做不到。**因此毫秒级保持的前提是
   晶振温度稳定或使用 TCXO/OCXO**，仅靠软件融合 CPU 温度不够。
3. **老化**：普通晶振首年 1~5 ppm/year ≈ 0.003~0.014 ppm/day ≈ 0.26~1.2 ms/day。
   日老化率模型能吃掉其中的线性部分，但剩余随机游走/温度滞后仍会留下
   0.1~1 ms/day。
4. **晶振稳定度（Allan deviation）**：普通 XO 在 24h 的稳定度常在 0.1~1 ppm；
   TCXO 约 0.01~0.1 ppm；OCXO 可到 0.001 ppm 量级。**这是物理地板**：
   0.1 ppm 的晶振，无论滤波多好，24h 保持都不可能稳定在 1 ms。

结论：

- 这套组合拳（批量时间戳 + 卡尔曼 + 温度 + 老化）能把**几十毫秒级**的保持误差
  压到**个位数毫秒**，在 TCXO/温控良好、NTP 历史充分的条件下可以到
  **亚毫秒~1ms**；
- 在普通主板晶振 + CPU 温度传感器 + 公网 NTP 的条件下，**不能承诺稳定 1ms**；
  合理预期是几毫秒到十几毫秒/24h，具体取决于晶振和温度环境；
- 要真正跨过 1ms 门槛，需要 TCXO/OCXO、晶振附近的温度传感、或本地
  PTP/GPS 参考；软件只能把已有硬件的潜力逼近极限。

## 7. HTTPS / TLS

`xmc_time_tls::client_config()` 构建 rustls 客户端配置：

```rust
ClientConfig::builder_with_details(ring_provider, app_time_provider)
    .with_safe_default_protocol_versions()?
    .with_root_certificates(webpki_roots)
    .with_no_client_auth()
```

`AppTimeProvider` 实现 `rustls::time_provider::TimeProvider`，返回应用时钟的
Unix 秒。因此证书 `notBefore` / `notAfter` 由 NTP 校准后的时间裁决，而不是
可能被手动改错的操作系统时钟。

`http_client` / `downloader` 的 ureq agent 都设置
`.tls_config(xmc_time_tls::client_config())`。HTTP 响应的 `Date` 头只作为
`date_skew_ms` 诊断返回，**绝不直接拨钟**——单个恶意 HTTPS 服务器若能改时间，
就可以让过期证书重新“有效”，这是不可接受的攻击面。

## 8. FFI 与 Dart

### Rust 导出（`xmc_time.dll`）

| 符号 | 说明 |
|---|---|
| `time_request(op, args_json)` | 统一 JSON 入口，返回 `{"ok":true,"data":…}` |
| `xmc_time_now_unix_ns/ms()` | 热路径，跨 DLL 时间桥使用 |
| `xmc_time_mono_ns()` | 原始单调时钟 |
| `xmc_time_synced()` | 0/1 |
| `xmc_time_uncertainty_ns()` | 当前不确定度 |
| `xmc_time_note_http_date(s, rtt)` | HTTPS Date 偏差诊断 |
| `time_shutdown()` | 停线程并落盘 |
| `xmc_time_free_string` / `xmc_time_get_last_error` | 避免与其它 crate 的 `free_string` 重名 |
| `xmc_time_default_config_json()` | 默认配置 |

`op`：`init/start`、`stop/shutdown`、`now`、`status`、`configure`、`sync`、
`probe`、`accuracy`、`temperature`、`gnss_sample`、`gnss_hello`、
`gnss_bridge_start`、`gnss_bridge_stop`、`gnss_bridge_status`、`force_reanchor`、
`note_http_date`、`persist`、`reset`、`mono`、`bridge`、`self_test`。`accuracy` 会探测所有服务器并返回
“应用时钟 vs NTP 共识”的中位/平均偏差、服务器极差、应用时钟与系统时钟差值、
当前不确定度；它不拨钟，用于回答“到底比系统时间准多少”。`temperature` 注入
外部温度（°C），供卡尔曼融合；`gnss_sample` 注入 Android GPS/北斗时间样本。

### Dart 封装

- `lib/services/time_ffi.dart`：FFI 绑定 + 热路径；库缺失时抛 `TimeFfiException`；
- `lib/services/time_service.dart`：业务入口。`nowUnixMs/nowUnixSeconds/
  nowUnixMicros/nowUnixNs/nowUtc/nowLocal/httpDate`，`syncNow()/probe()` 在
  后台 isolate 执行避免卡 UI；`initialize()` 在 `main()` 中调用；
- `lib/screens/time_screen.dart`：状态/服务器/精度/配置页面（主页工具磁贴进入）。

**约定**：安全与时间敏感路径必须用 `TimeService`，不要用 `DateTime.now()`：

- `DeviceAuthProtocol.timestampText()`（登录/注册/逐请求证明的唯一时间来源）；
- `NodeAccountSession.isValid` / 登录过期回退；
- 设备挑战过期、绑定 `boundAt`；
- TOTP（`vault_crypto.dart`）；
- CHMLFRP token 过期；
- 集群迁移超时/同步标记、frpc 日志标记、日志限流、回收站/备份时间。

UI 显示、纯 ID/临时目录命名等非时间语义场景仍可用 `DateTime.now()`。

## 9. 持久化

文件：`<数据根>/clock/state.json`（`AppPaths.clockStateDir()`），原子写入
（临时文件 + rename）。字段：

```json
{
  "version": 1,
  "saved_at_unix_ns": "...",
  "saved_at_os_ns": "...",
  "offset_ns": "...",
  "uncertainty_ns": "...",
  "last_sync_unix_ns": "...",
  "last_freq_ppm": 12.3,
  "stratum": 2,
  "source": "ntp.aliyun.com",
  "synced": true,
  "total_syncs": 42,
  "trend": [
    {"unix_s": 1794556000, "freq_ppm": 0.012, "temp_c": 31.5}
  ]
}
```

只保存“应用时间 - 系统时钟”的差值，不保存绝对时间：即使系统时钟在两次启动
之间被校正，热启动仍以系统时钟为基准叠加已知偏移。超过 30 天、偏移超过 60 秒
或版本不匹配的文件直接丢弃。

**锚点污染保护**：若 `saved_at_unix_ns` 或 `saved_at_os_ns` 比当前系统时间超前
超过 **1 天**，判定为损坏；`state::load` 删除文件，`load_state` 重置应用时钟到
系统时间并清空 KF/历史锚点，随后重新走 NTP 冷启动。`persist` 也不会把
`app - os > 1 天` 的污染状态写回磁盘。

**人工强制重置**：FFI `force_reanchor` / UI“强制重置时间基准”会同步探测 NTP，
取可达服务器的中位偏移，调用 `AppClock::force_step` 无视 high_water/step 限制
硬切到 NTP 共识，并重置 KF 偏移。手机会作为更高优先级源：GNSS 连续有效时
NTP 暂停拨钟 5 分钟，避免两个源互相拉扯。

## 10. 测试

```bash
cargo test -p xmc_time_base -p xmc_time -p xmc_time_tls
flutter test test/time_ffi_test.dart
```

- Rust：54 个单元/集成测试，覆盖日历/HTTP 日期、单调性、步进/冻结、drain 预算、
  卡尔曼滤波（频率/温度系数/新息门限）、日老化、批量时间戳、温度注入、
  GNSS 样本采纳/拒绝、NTP 模拟服务器（偏移/KoD/era）、不可达源、纪律环 step；
- Dart：本地 UDP NTP mock（真实时间 +12.5s）验证同步、偏移、服务器状态、探测、
  self_test；动态库缺失时整组 skip。

## 11. 文件地图

```text
rust/time_base/src/{lib,mono,civil,httpdate,link}.rs
rust/time_tls/src/lib.rs
rust/time/src/{lib,ffi,clock,precise,ntp,kalman,thermal,gnss_bridge,service,state}.rs
lib/services/{time_ffi,time_service}.dart
lib/screens/time_screen.dart
test/time_ffi_test.dart
docs/time-system.md
```

## 12. 已知边界

- 不修改系统时钟，因此其它程序看到的仍是系统时间；IriX 只在自身进程内保证；
- NTP 无认证（NTS 未接入）。防伪造依赖随机 nonce + 多源投票 + 最大变更保护；
- 首次启动/长期离线后可能经历一次 step；`high_water` 会冻结不超过 5 秒；
- 卡尔曼状态（频率/老化/温度系数/协方差）会持久化并在重启后继续使用；但晶振
  老化/温度变化仍会让实际漂移偏离模型，`holdover_ppm` 是保守外推预算；
- **24h 毫秒级误差不是软件能单方面保证的**：需要残余频率误差 <0.0116ppm。
  普通主板晶振 + CPU 温度传感器 + 公网 NTP 的现实预期是个位数~十几毫秒；
  TCXO/OCXO、晶振附近测温和稳定 NTP 历史才可能稳定到亚毫秒~1ms（见 §6.2）；
- PTP 未实现，TSC 精度在非 x86_64 平台不可用（自动退化）；
- Android GPS/北斗时间校准的对接方式、FFI 数据契约与验收标准见
  [`docs/android-gnss-time-calibration.md`](android-gnss-time-calibration.md)。
