# Codemagic 云端 Mac + Xcode 原生编译 —— 完整步骤

目标：**不买 Mac、不装 Xcode**，用 Codemagic 的云端 Mac 把 `TrackerSweep` 编成 `.ipa`，然后 sideload 装进 iPhone。

总耗时：第一次约 **15 分钟**（含注册），之后每次改动 **3~5 分钟**出包。

---

## 0. 前置

| 需要 | 说明 |
|---|---|
| GitHub 账号 | 存源码（Codemagic 从这里拉） |
| Codemagic 账号 | 用 GitHub 登录即可，免费额度 500 分钟/月，一次构建约 3~5 分钟 |
| Windows 电脑 + 数据线 | 最后装 App 用（Sideloadly） |
| Apple ID | **免费账号就够**（走未签名 + Sideloadly 自签，7 天有效） |

> 想要「装上就不过期 / 直接推 TestFlight」，需要**付费** Apple Developer（$99/年）。
> 没付费账号也能完整跑通，只是每 7 天重签一次。

---

## 1. 把源码推到 GitHub

仓库根目录必须是 `tracker-sweep/` 这一层（`codemagic.yaml`、`TrackerSweep.xcodeproj` 都在这一层）。

```powershell
cd E:\deepseeek\tracker-sweep
.\scripts\push-to-github.ps1 -Repo "https://github.com/<你的用户名>/tracker-sweep.git"
```

脚本会做：`git init` → 检查 `.gitignore` → 首次提交 → 设置 remote → 推送 `main`。
（不想用脚本就手动 `git init && git add . && git commit && git remote add origin … && git push -u origin main`。）

推完在 GitHub 网页上确认能看到这三个东西：

```
codemagic.yaml
TrackerSweep.xcodeproj/project.pbxproj
TrackerSweep/Views.swift
```

---

## 2. 在 Codemagic 里接入

1. 打开 <https://codemagic.io> → **Sign up with GitHub**
2. 授权后点 **Add application**
3. 选 **GitHub** → 选 `tracker-sweep` 仓库
4. Project type 选 **Other**（不要选 Flutter/React Native）
5. 它会自动读到 `codemagic.yaml` → 点 **Finish**

> 如果它提示 "no configuration file found"，说明 `codemagic.yaml` 不在仓库根目录 —— 回到第 1 步检查层级。

---

## 3. 跑第一次构建（未签名）

1. 进入应用 → 右上 **Start new build**
2. 选分支 `main`
3. Workflow 选 **iOS unsigned IPA (no Apple account needed)**
4. 点 **Start build**

构建过程会依次执行：

| 步骤 | 干什么 | 失败意味着 |
|---|---|---|
| 环境自检 | 打印 Xcode / iOS SDK 版本 | runner 镜像问题，重跑即可 |
| 工程结构自检 | `python3 tools/check_pbxproj.py` + `check_sources.py` | 工程文件坏了 → 把日志发我，我改生成器 |
| Xcode 编译 | `xcodebuild -sdk iphoneos CODE_SIGNING_ALLOWED=NO` | Swift 编译错 → 日志里会有 `error:` 行 |
| 打包 ipa | `Payload/` + `zip` | 一般不会失败 |

**成功标志**（日志末尾）：

```
dist/TrackerSweep-unsigned.ipa
<sha256>
```

---

## 4. 下载产物

构建页 → **Artifacts** → 下载 `TrackerSweep-unsigned.ipa`（约 200 KB~2 MB）。
也可在 **Build overview** 里从邮件链接下载（邮件收件人记得先在 `codemagic.yaml` 里改成你的邮箱，或直接删掉 `publishing.email` 那一段）。

---

## 5. 装进 iPhone（Windows 就能做）

1. 装 **Sideloadly**（sideloadly.io）和 **iTunes**（Microsoft Store 版即可，只要它的驱动）
2. iPhone 插线 → 手机点「信任」
3. Sideloadly：
   - IPA 选刚下载的那个
   - Apple ID 填你的
   - 点 **Start**，输密码（会走 Apple 的二次验证，正常）
4. 手机 → 设置 → 通用 → **VPN与设备管理** → 点你的 Apple ID → **信任**
5. 回到桌面打开「反跟踪扫描」→ 允许 **蓝牙** / **运动与健身** /（可选）**定位**

> 7 天后 App 打不开（证书过期）→ 用同一个 ipa 再走一遍 Sideloadly，或者上 AltStore 自动续签。

---

## 6. 可选：已签名 / TestFlight（需要付费账号）

### 6.1 在 Codemagic 配置 App Store Connect 集成

1. Apple Developer 后台 → **Users and Access** → **Integrations** → **App Store Connect API**
2. 生成一个 **Team Key**，记下 **Issuer ID** 和 **Key ID**，下载 `.p8`（只能下一次）
3. Codemagic → 右上 **Teams** → **Integrations** → **App Store Connect** → **Add key**
   - Name 填 **`ASC_KEY`**（必须和 `codemagic.yaml` 里的 `app_store_connect: ASC_KEY` 一致）
   - 粘贴 Issuer ID / Key ID / `.p8` 内容
4. Apple Developer 后台 → **Identifiers** → 新建 App ID：Bundle ID = `com.lab.trackersweep`

### 6.2 跑签名构建

- **iOS signed IPA (needs paid Apple Developer)** → 产出 `build/ios/ipa/TrackerSweep.ipa`，可直接 AirDrop/装
- **iOS TestFlight upload** → 编译后自动传 TestFlight，过一会儿在 App Store Connect 的 TestFlight 页就能看到构建

> 这两个工作流默认 `triggering.events: []`（只手动触发），避免每次 push 都烧付费构建额度。

---

## 7. 报错对照表

| Codemagic 日志里的报错 | 原因 | 改法 |
|---|---|---|
| `Cannot find 'TrackerModel' in scope` | 源文件没进 compile phase | 重跑 `python tools/gen_pbxproj.py` 再提交 |
| `error: Signing for "TrackerSweep" requires a development team` | 走到签名分支了 | 用 **ios-unsigned** 工作流；或配置 `ASC_KEY` 后用 signed 工作流 |
| `No profiles for 'com.lab.trackersweep' were found` | App ID 没建 / 集成没配 | 见 6.1 第 4 步 |
| `xcodebuild: error: Unable to find a destination` | 用了模拟器 SDK | 确认 `-sdk iphoneos`（仓库里已写死） |
| `Code signing is required for product type 'Application'` | `CODE_SIGNING_ALLOWED=NO` 没生效 | 检查是不是被 `-target` 换成 `-scheme` 了（scheme 会带上签名设置） |
| `Provisioning profile doesn't support the ... entitlement` | Info.plist 里的 `wifi-info` 需要付费账号能力 | 删掉 Info.plist 里那一行（不影响主功能） |
| `build timed out` | 免费实例排队 | 重跑；或错峰 |
| `No matching workflow` | `codemagic.yaml` 缩进坏了 | `python tools/check_ci.py` 本地先验 |

本地预检（Windows 就能跑，不消耗云端额度）：

```powershell
python tools\check_pbxproj.py
python tools\check_sources.py
python tools\check_ci.py
```

---

## 8. 额度与省钱

| 项 | 说明 |
|---|---|
| 免费额度 | 500 分钟/月（macOS 实例有倍率，实际可用分钟数会打折，看 Codemagic 后台的剩余量为准） |
| 单次构建 | 约 3~5 分钟（含排队） |
| 省额度技巧 | 只让 `ios-unsigned` 自动触发；signed/testflight 保持手动；本地先跑三个 `check_*.py` |
| 缓存 | 已在 `-derivedDataPath build` 下，Codemagic 默认会缓存 `~/.gradle`/CocoaPods，本项目无需额外配置 |

---

## 9. 文件对照

| 文件 | 作用 |
|---|---|
| `codemagic.yaml` | 三个工作流（unsigned / signed / testflight） |
| `.github/workflows/build-ipa.yml` | 备选方案：GitHub Actions 也能出同样的 ipa |
| `scripts/build-ipa.sh` | 本地 Mac 一键出包（与 CI 等价） |
| `scripts/push-to-github.ps1` | Windows 一键初始化并推送仓库 |
| `tools/check_pbxproj.py` | 验证 `.xcodeproj` 结构（不需要 Xcode） |
| `tools/check_sources.py` | 验证 Swift 源文件与页面完整性 |
| `tools/check_ci.py` | 验证 `codemagic.yaml` 与工程配置一致 |
