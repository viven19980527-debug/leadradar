# 反跟踪扫描（iOS）— 手机上直接查定位器 / 追踪器 / 窃听设备

一个能装在 iPhone 上的 App：**扫描周边 BLE 广播，把 AirTag / SmartTag / Tile / Chipolo / 陌生信标揪出来，用"两地对比 + 热冷定位"确认它是不是在跟着你；再用磁力计扫房间里的磁铁/喇叭（偷拍设备最常见的物理特征）。**

---

## 一、先把"能查什么"说清楚

| 目标类型 | 这个 App 能不能发现 | 依据 |
|---|---|---|
| **AirTag / 第三方"查找"网络防丢器** | ✅ 能，还能读"是否与主人分离" | BLE 广播 `4C 00 12 19 <status> …`，status 的 bit5 = 在主人身边 |
| **Samsung SmartTag** | ✅ 能 | 厂商 ID `0x0075` |
| **Tile / Chipolo** | ✅ 能 | 服务 UUID `FE9F / FEEC / FE3x` |
| **Google Fast Pair 设备** | ✅ 能（低风险标注） | 厂商 ID `0xFE2C` |
| **小米 / MiBeacon** | ✅ 能（低风险标注） | 厂商 ID `0xFE95` |
| **名字里带 tracker 的杂牌定位器** | ✅ 能（关键字匹配） | 广播名 |
| **藏磁铁 / 带喇叭的偷拍设备** | ⚠️ 只能发现"有磁异常"，需要人靠近确认 | 磁力计 |
| **纯 Wi-Fi 摄像头** | ❌ 手机查不了 | iOS 不给 AP 扫描 API → 用配套的 `counter-surv/lan_hunt.py` |
| **只走蜂窝 / GPS 回传的定位器** | ❌ 查不了 | 不发射 BLE，手机侧无感知手段 |
| **关机状态的设备** | ❌ 查不了 | 不发射就没有信号 |
| **有线/离线录音笔** | ❌ 查不了 | 物理搜查 |

**一句话**：手机上能做到"BLE 追踪器全覆盖 + 磁异常初筛"，做不到"所有定位器和窃听器"。后面这类要靠电脑 + 物理排查，配套工具已经给你了。

---

## 二、为什么"两地对比"是唯一靠谱的判据

单个地点扫到 AirTag 毫无意义——邻居家、电梯里、咖啡店都有。真正能定性的是：

```
在 A 地点扫 60 秒  →  记录地点 A
走到 B 地点扫 60 秒  →  记录地点 B
同一个指纹在 A、B 都出现，且信号强度差不多  →  它跟着你
```

所以 App 里做的是：
1. 连续扫描，按**指纹**记账（AirTag 的 MAC 每 ~15 分钟轮换，光看 MAC 会漏）
2. 点「记录地点 A / B / C」打点
3. 「跟随判定」页只显示 **≥2 个地点 + 持续 >120 秒** 的设备，标 🔴

判据写死在代码里（`TrackerHit.isFollowing`），不会因为"看着像"就报警。

---

## 三、界面（5 个页签）

| 页签 | 作用 |
|---|---|
| **扫描** | 开始/停止扫描，按风险排序列表，点「记录地点 X」打点 |
| **跟随判定** | 只看追踪器类；显示指纹、地点链、持续时长、信号范围、**是否与主人分离** |
| **找它** | 选中设备后进入热冷模式：越近震得越急（重/中/轻震动 + 强度条 + RSSI 曲线） |
| **磁扫** | 磁力计实时偏差曲线，超过 25 µT 变橙、50 µT 变红；可重设基线 |
| **报告** | 生成文字报告，可直接分享（ShareLink） |

---

## 四、编译部署

> **Windows 上编译不了 iOS 二进制**（没有 Xcode / iOS SDK）。仓库里已经带了**手写的 `.xcodeproj`**，
> 拿到 Mac 或走云端就能直接开工程，不需要再装 XcodeGen。

**你有付费开发者账号 → 走 TestFlight，最省事** → 完整步骤见 **[SIGNING.md](SIGNING.md)**

```powershell
cd tracker-sweep
.\scripts\push-to-github.ps1 -Repo "https://github.com/<你的用户名>/tracker-sweep.git"
# → codemagic.io 用 GitHub 登录 → Add application → 选仓库 → Other
# → Teams → Integrations → App Store Connect → 名字填 ASC_KEY，粘 Issuer ID / Key ID / .p8
# → 推一个 tag：git tag v1.0.0 && git push origin v1.0.0
# → 5~8 分钟后 TestFlight 里出现「反跟踪扫描」→ 手机 TestFlight App 安装
```

| 路径 | 用在哪 | 文档 |
|---|---|---|
| TestFlight（推荐） | 日常迭代，90 天有效 | [SIGNING.md §3.1](SIGNING.md) |
| ad hoc（不过期） | 装自己几台设备，需注册 UDID | [SIGNING.md §3.2](SIGNING.md) |
| 未签名 + Sideloadly | 应急 / 没有开发者账号时 | [BUILD.md](BUILD.md) |
| GitHub Actions 兜底 | 不想用 Codemagic 时 | `.github/workflows/build-ipa.yml` |

云端接线（Codemagic 三个工作流的细节）：[CODEMAGIC.md](CODEMAGIC.md)。

---

## 五、正确用法（照这个顺序，别乱扫）

1. **先在自己家做基线**：什么都不带，扫 60 秒，记地点 `A`。把自己的耳机、手表、钥匙扣认一遍。
2. **出门**：把随身物品放桌上，扫 60 秒，记 `B`。
3. **到目的地**：扫 60 秒，记 `C`。
4. 看「跟随判定」：只有跨地点都出现的才是候选。
5. 对候选点「去定位」→ 热冷模式走一圈，震动变强就靠近了。
6. 找到了先**别拆**：拍照留存（含位置、时间），再决定怎么处理。
7. 对房间做**磁扫**：关掉附近电器，贴墙面 / 插座 / 闹钟 / 烟雾报警器 / 路由器平扫。

---

## 六、误报从哪来（必须知道）

| 现象 | 真实原因 |
|---|---|
| 同一个 AirTag 一直在 | 可能是**你自己的**（钥匙、包、车）。先把自己名下的设备配对登记一遍 |
| 邻居的 AirTag 也"跨地点" | 你俩住得近、走同一条路。看 `separated` 与信号强度：真跟随的信号更稳更强 |
| 分享单车、共享充电宝、商场信标 | 大量 BLE 信标，正常。看名字与厂商 |
| 磁力计乱跳 | 手机壳带磁吸、MagSafe、金属桌面、电梯、音箱、门吸。**换位置重设基线**再测 |
| 磁异常但找不到东西 | 墙内钢筋、水管、配电箱。贴着墙走，找"点状"而不是"大片" |

---

## 七、文件

```
tracker-sweep/
├── project.yml                  XcodeGen 配置
├── TrackerSweep/
│   ├── Info.plist               蓝牙 / 运动 / 定位 / 后台 central 权限
│   ├── TrackerModel.swift       扫描、报文解析、指纹、地点记账、热冷、报告
│   ├── Magnetometer.swift       磁力计偏差检测
│   └── Views.swift              @main 入口 + 5 个页签
└── README.md
```

判定逻辑集中在 `TrackerModel.classify()`：
- Apple：`4C 00` + 子类型（`0x12` = FindMy）→ 读 status bit5 判定"是否与主人分离"
- Samsung：`75 00`；Fast Pair：`2C FE`；MiBeacon：`95 FE`
- Tile / Chipolo：服务 UUID 前缀
- 名字兜底：`airtag / tile / smarttag / chipolo / tracker / 防丢 / 定位器`

---

## 八、手机上还应该开的两个系统功能

1. **「跟踪提醒」**（iOS 自带）：设置 → 通知 → 查找 → 打开。陌生 AirTag 跟随你一段时间后系统会主动推。
2. **「查找」里的物品列表**：设置 → 隐私与安全性 → 定位服务 → 系统服务 → 查找 → 检查「共享我的位置」是否被你不需要的人共享着。

这两项比任何第三方 App 都更早发现"被 AirTag 跟"，**别关**。

---

全文功能对照（每个按钮实现什么、底层用哪层 API、边界在哪）：**[FEATURES.md](FEATURES.md)**

## 九、攻击台的鉴权诊断（0x05 / 0x0F）

BLE 攻击台原来只会说「写入被设备拒绝」，一句话把三种完全不同的原因混在一起。现在每个失败都会落到具体的 ATT 码上：

| 码 | 含义 | 说明 |
|---|---|---|
| 0x05 | 需要认证配对 | 链路没做过 MITM 配对。Just Works 不算 |
| 0x0F | 需要加密 | 只要配对成功就能写（最好打的一类） |
| 0x03 | 不可写 | 属性本身不允许，换特征 |
| 0x08 | 缺应用层授权 | 先写配套的使能特征 |
| 0x0D | 长度不符 | 1 / 2 / 4 / 8 / 16 / 20 字节逐个试 |
| 0x06 | 操作不支持 | 写改读、写改订阅 |

界面上多了三个按钮：

- **鉴权探针**：对每条可写特征写 1 字节，一次摸清每条特征的门槛
- **触发配对**：写受保护特征逼出 iOS 系统配对框（不点配对，之后全是 0x05）
- **断开重连**：iOS 会缓存失败的安全状态，断链重连再打

另外两处行为修正：

- **盲写不再算成功**：`WriteWithoutResponse` 不产生任何回调，现在单独计为「盲写」，不再混进成功数
- **优先有确认写**：只要特征声明了 `write`，就走 `withResponse`，否则永远读不到 ATT 错误码
- **主动断开不再算打崩**：自己点「断开」不会被记进断线次数

---

## 十、直攻：真正绕过 ATT 权限的四条路

ATT 有两种写：

| 操作码 | 名称 | 有回调 | 很多固件的权限检查 |
|---|---|---|---|
| 0x12 | Write Request | 有 | ✅ 会查 |
| 0x52 | Write Command | 无 | ❌ 经常漏查（直接交给应用层） |

所以「0x05 挡住」不等于「写不进去」，只等于「这条路径被挡」。App 现在会自动做四件事：

**① Write Command 重发（自动）**
`didWriteValueFor` 收到 0x05/0x0F，只要该特征还声明了 `writeNR`，立刻把同一份 payload 用 0x52 重发一遍。命中就说明固件只在 Write Request 上查权限。
因为没有回调，成功靠**读回**或**通知变化**证明：`commandSent` 记录发出值，读到一致值 → `绕过确认 +1`。

**② 手动直攻**
每条带 `writeNR` 的特征旁边有红色「直攻」按钮，用当前 hex 直接走 0x52。

**③ 可打面扫描**
优先找「不受保护又能造成影响」的入口，而不是硬啃受保护特征：

- `0x1530 / 0x1531` Nordic DFU —— 固件上传，通常只要加密 → 刷进去就是完整控制
- `0x1812` HID over GATT —— 写 Report 特征等于注入按键
- `0xFFF0 / 0xFFE0 / 0xFF00` 厂商私有 —— 最常漏鉴权
- `89D3…` Apple AMS —— Control Point 控制媒体

**④ 绑定表冲刷**
反复「触发配对 → 断链 → 重连」。Nordic 默认 8 个绑定槽，满了淘汰最旧一条，旧配对的已认证状态随之作废，可以重新配对拿新 bond。每轮系统弹框必须点配对。

### 边界（写清楚，免得白打）

- iOS 侧没有 LESС 密码学绕过。0x05 的根因是链路没做过 MITM 配对，协议栈层面无法伪造。
- 能绕的只有三类：**实现漏检**（第 ①、②条）、**次级面**（第 ③条）、**绑定槽管理**（第 ④条）。
- 设备如果每条路径都严格校验、且没有 DFU/HID/私有服务，iPhone 上到此为止 —— 剩下的是硬件活（双 nRF52840 中继、Ubertooth 嗅探、SPI 抠 LTK）。

---

## 十一、打 Apple 生态：为什么必须上硬件

iPhone 打 iPhone 恒为 0 收益，四条原因全在 Apple 手里：GATT server 不对第三方开放写入口、Apple 私有面用 iCloud 身份密钥配对、iOS 不允许 App 设置 manufacturer data、私有面只声明 `write` 不给 `writeNR`。

外接一块 nRF52840 能拿到 iOS 拿不到的四件事：自定义广播（Apple 弹窗 / AirTag 克隆）、ATT handle 级读写、空口嗅探、central+peripheral 同板代理。

- 方案与刷写步骤：[hardware/README.md](hardware/README.md)
- 固件：`hardware/nrf52/apple_adv_spoof/`（Apple 广播伪造）、`hardware/nrf52/ble_proxy/`（单板代理）
- App ↔ 板子串口协议：[hardware/protocol.md](hardware/protocol.md)
