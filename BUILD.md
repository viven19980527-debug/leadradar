# 怎么把它变成手机上能点的 App

本机是 Windows，**没有 Xcode 也没有 Swift 编译器**（我在这台机器上实测过：`xcodebuild` / `swiftc` 都不存在，Windows 也没有 iOS SDK）。
所以这里的路线全部绕开"本地编译"，按成本从低到高排列。

---

## 路线 A：GitHub Actions 编译（推荐，不用 Mac，5 分钟出 ipa）

工作流已经写好了：[`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml)

```bash
cd tracker-sweep

# 1) 建一个空仓库（网页上建，或 gh 也行），然后
git init
git add .
git commit -m "TrackerSweep: iOS 反跟踪扫描"
git branch -M main
git remote add origin https://github.com/<你的用户名>/tracker-sweep.git
git push -u origin main

# 2) 打开仓库 → Actions → "build-ipa" → 等 3~6 分钟
# 3) 页面底部 Artifacts → 下载 TrackerSweep-unsigned-ipa → 解压得到 .ipa
```

公开仓库 **Actions 免费不限时长**；私有仓库每月 2000 分钟（macOS runner 按 10 倍计费 = 200 分钟实际用量，这个项目一次约 3 分钟，够用几百次）。

---

## 路线 B：租一台云 Mac（要自己调参数/改代码时）

| 服务 | 免费额度 | 适合 |
|---|---|---|
| MacStadium | 试用 | 长期 |
| Scaleway Apple silicon | 按小时（约 ¥1.5/h） | 短期调代码 |
| AWS EC2 mac2.metal | 按小时（贵） | 企业 |
| 淘宝"云 Mac 远程" | 按天（约 ¥20~40/天） | 最省事的国内路子 |

上机后一条命令：

```bash
scp -r tracker-sweep user@mac:~/ && ssh user@mac
cd ~/tracker-sweep && bash scripts/build-ipa.sh
```

---

## 路线 C：借一台 Mac（有朋友有 Mac 就行）

```bash
brew install --cask xcode
sudo xcodebuild -license accept
cd tracker-sweep
xcodegen generate      # 可选：仓库里已经带了手写的 .xcodeproj，不用这步也能开
open TrackerSweep.xcodeproj
# Xcode → Signing & Capabilities → Team 选你的 Apple ID → 选真机 → ⌘R
```

免费 Apple ID 的限制：**7 天到期**，到期用同样方式重签一次；不能后台常驻超过系统限制；不能推送。

---

## 装到 iPhone 上（拿到 ipa 之后）

### 方式 1：Sideloadly（Windows 就能做，最贴合你现在的环境）

1. 下载 Sideloadly（sideloadly.io）和 iTunes 驱动（或 Microsoft Store 版 iTunes）
2. iPhone 用数据线连电脑 → 信任这台电脑
3. Sideloadly 里选 `TrackerSweep-unsigned.ipa`，Apple ID 填你的，Start
4. 手机上：设置 → 通用 → VPN与设备管理 → 信任你的开发者证书
5. 打开 App → 允许蓝牙 / 运动与健身 / 定位

> Sideloadly 用的是你自己的开发者证书，所以**不需要等别人签名**，7 天后重签即可。

### 方式 2：AltStore（无线重签，7 天自动续）

装 AltServer（Windows 版）→ 手机装 AltStore → 把 ipa 拖进 AltStore。之后每 7 天在同一个 Wi-Fi 下自动重签，不用插线。

### 方式 3：TrollStore（iOS 14.0–17.0 部分版本，永久签名）

如果设备版本在支持范围内，把 ipa 丢进 TrollStore 安装，**永不过期**。判断方法：装 TrollStore 的 "TrollHelper" 看它支不支持你的版本。

---

## 编译之前先跑一次结构自检

我写了 `tools/check_pbxproj.py`，不需要 Xcode，纯 Python 就能验证工程文件是不是坏的：

```bash
python tools/check_pbxproj.py
```

输出（我在这台机器上已经跑过）：

```
✓ 括号平衡 ({}=32)
✓ 无悬空引用（22 个对象全部有定义）
✓ 10 个 section 齐全
✓ rootObject 存在
✓ 3 个 Swift 文件全部进 Sources
✓ scheme BlueprintIdentifier 与 target 一致
结论：结构完整，Xcode 可以打开
```

CI 里第一步也会跑它，**结构坏了会先停下**，不会浪费一次 macOS 构建。

---

## 常见编译错误 → 对应对策

| 报错 | 原因 | 改法 |
|---|---|---|
| `Cannot find 'ContentUnavailableView' in scope` | 该 API 是 iOS 17+，工程 target 是 16 | 已改成自绘 VStack（仓库里已修） |
| `Signing for "TrackerSweep" requires a development team` | 没选 Team | Xcode → Signing → Team；CI 里用 `CODE_SIGNING_ALLOWED=NO` 绕开 |
| `No such module 'CoreBluetooth'` | 用的模拟器 SDK 或 SDK 路径不对 | `-sdk iphoneos`（真机 SDK），不要用 `iphonesimulator` |
| `Provisioning profile doesn't include the com.apple.developer...` | 免费证书不支持某些能力 | Info.plist 里的 `wifi-info` 删掉即可（不影响主功能） |
| `The operation couldn't be completed. (OSStatus error -34018.)` | 真机跑但签名不完整 | 用 Sideloadly 重签，别用未签名的包直接装 |

---

## 产物长什么样

```
dist/
├── TrackerSweep-unsigned.ipa    ← Sideloadly / AltStore 用这个
├── build.log                    ← 编译日志（出错先看这里）
└── TrackerSweep.ipa             ← 只有给了 TEAM_ID 才有（已签名，可直接装）
```
