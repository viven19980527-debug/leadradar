# 有开发者账号、没有 Mac —— 签名与安装全流程

你有 **付费 Apple Developer（$99/年）**，没有 Mac。这份文档只讲这条路上的每一步，全部在你的 Windows 上完成，编译交给 Codemagic 的云端 Mac。

配置做好之后，日常是：**改代码 → `git push` → 打 tag → 3 分钟 → 手机上 TestFlight 收到新版本**。

---

## 0. 先理解三条分发路径的差别

| 路径 | 需要什么 | 装法 | 有效期 | 适合 |
|---|---|---|---|---|
| **TestFlight**（推荐） | 只需 App Store Connect App 记录 | 手机装 TestFlight App，点接受邀请 | 每个构建 **90 天** | 自己用 + 给朋友试 |
| **ad hoc** | 把设备 UDID 注册进开发者账号（每个账号 100 台/年） | 3uTools / OTA 链接直接装 | **1 年**（证书一年） | 长期装在自己几台设备上 |
| **未签名 + Sideloadly** | 不需要开发者账号 | Sideloadly 用你的 Apple ID 现签 | 7 天 | 应急/验证代码能编 |

**结论**：日常用 TestFlight；想彻底不过期、不依赖 TestFlight 审核节奏，就用 ad hoc + 注册 UDID。

---

## 1. 开发者账号侧（一次性，约 10 分钟）

### 1.1 建 App ID

<https://developer.apple.com/account> → **Certificates, Identifiers & Profiles** → **Identifiers** → **+**

- 选 **App IDs** → **App**
- Description：`TrackerSweep`
- Bundle ID：**Explicit** → `com.lab.trackersweep`
- Capabilities：**默认即可，什么都别勾**（本 App 只用蓝牙 + 运动传感器）
- 保存

> 若以后要读 Wi-Fi 名字，再回来勾 **Access WiFi Information**，同时工程里要加 entitlements。
> 现在不要勾，免得签名时描述文件与能力不匹配。

### 1.2 建 App Store Connect API Key（给 Codemagic 自动签名 + 上传用）

<https://appstoreconnect.apple.com> → **Users and Access** → **Integrations**（旧版叫 Keys）→ **App Store Connect API** → **Team Keys** → **+**

- Name：`codemagic`
- Access：**App Manager**（签名与上传都够用）
- 生成后记下：
  - **Issuer ID**（一串 UUID，全团队同一值）
  - **Key ID**（10 位，如 `2X9R4HXF34`）
  - **下载 `.p8` 文件** —— ⚠️ **只能下载一次**，立刻存好

### 1.3 建 App 记录（TestFlight 必需）

<https://appstoreconnect.apple.com> → **My Apps** → **+** → **New App**

| 字段 | 填什么 |
|---|---|
| Platform | iOS |
| Name | `反跟踪扫描`（App Store 上显示的名字，可改） |
| Primary Language | Chinese (Simplified) |
| Bundle ID | `com.lab.trackersweep`（下拉里选 1.1 建的那个） |
| SKU | `trackersweep001`（随便，唯一即可） |

> 不建这条记录，上传会报 `ITMS-90062 / No suitable application records were found`。

---

## 2. Codemagic 侧（一次性，约 5 分钟）

### 2.1 接入仓库

<https://codemagic.io> → **Sign up with GitHub** → **Add application** → 选 `tracker-sweep` → Project type 选 **Other** → 它会自动读到 `codemagic.yaml`。

### 2.2 配置 App Store Connect 集成（名字必须是 `ASC_KEY`）

Codemagic 右上头像 → **Teams** → **Integrations** → **App Store Connect** → **Add key**

| 字段 | 填什么 |
|---|---|
| **Name** | `ASC_KEY` ← **必须一字不差**，`codemagic.yaml` 里写的就是它 |
| Issuer ID | 1.2 的 Issuer ID |
| Key ID | 1.2 的 Key ID |
| API Private Key | 把 `.p8` 文件用记事本打开，**整段粘贴**（含 `-----BEGIN PRIVATE KEY-----` 到 `-----END PRIVATE KEY-----`） |

保存后回到应用页面。

### 2.3 确认签名配置已被识别

应用 → **Settings**（或构建页右上）→ **Code signing**，应该能看到 `ASC_KEY` 可用。
如果这里显示 "No integrations"，说明 2.2 的名字打错了。

---

## 3. 触发构建

### 3.1 TestFlight（主用）

```powershell
cd E:\deepseeek\tracker-sweep
git tag v1.0.0
git push origin v1.0.0
```

tag 命中 `v*` → Codemagic 自动跑 `ios-testflight`：自检 → 递增 build 号 → `xcode-project use-profiles`（自动申请证书 + 描述文件）→ 编译 → 上传 TestFlight。

**约 5~8 分钟**后：
- Codemagic 构建页显示 `Published to App Store Connect`
- App Store Connect → **TestFlight** 里出现新构建（苹果处理要 2~10 分钟，第一次更久）
- 手机装 **TestFlight** App → 用同一个 Apple ID 登录 → 出现「反跟踪扫描」→ 安装

> 第一次上传会要求填 **Export Compliance**（是否用加密）：选 **No**（只用系统 TLS）。

### 3.2 ad hoc（想 1 年不过期，用这个）

**Step 1：拿到设备 UDID（Windows 上三种办法，任选）**

| 办法 | 操作 |
|---|---|
| **Sideloadly**（最简单） | 打开 Sideloadly，插上 iPhone，窗口顶部会直接显示 UDID，右键复制 |
| 3uTools | 设备信息页 → 「UDID」→ 复制 |
| libimobiledevice | `idevice_id -l`（需先 `scoop install libimobiledevice`） |

**Step 2：注册设备**

<https://developer.apple.com/account> → **Devices** → **+** → Platform: iOS → 粘 UDID → Continue → Register

**Step 3：跑构建**

Codemagic → **Start new build** → 分支 `main` → Workflow 选 **iOS ad hoc IPA (direct install)** → Start

**Step 4：装到手机**

产物 `build/ios/ipa/TrackerSweep.ipa`，两种装法：

- **3uTools**：工具箱 → IPA 签名/安装 → 选这个 ipa → 安装（已 ad hoc 签名，不需要再签）
- **OTA 链接**（不用装任何软件）：把 ipa 和一个 `manifest.plist` 放到任意 HTTPS 静态托管（GitHub Pages 就行），手机 Safari 打开 `itms-services://?action=download-manifest&url=<manifest 的 https 地址>`

`manifest.plist` 模板：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key><string>software-package</string>
          <key>url</key><string>https://你的域名/TrackerSweep.ipa</string>
        </dict>
        <dict>
          <key>kind</key><string>display-image</string>
          <key>url</key><string>https://你的域名/icon-57.png</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key><string>com.lab.trackersweep</string>
        <key>bundle-version</key><string>1.0</string>
        <key>kind</key><string>software</string>
        <key>title</key><string>反跟踪扫描</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
```

> Codemagic 的 artifact 下载链接 **14 天后过期**，OTA 安装请把 ipa 传到你自己的静态托管，别直接用 artifact 链接。

---

## 4. 日常迭代流程

```powershell
# 改完代码
git add -A
git commit -m "调整跟随判定阈值"
git push                     # → 自动跑 ios-unsigned（验证能编，不消耗签名额度）
git tag v1.0.1
git push origin v1.0.1       # → 自动跑 ios-testflight（上传新版本）
```

`ios-unsigned` 每次 push 都跑，作用是**尽早发现编译错误**（不碰签名，最省时间）。
`ios-testflight` 只在打 tag 时跑，因为 TestFlight 上传会占用处理队列。

---

## 5. 报错对照（你这条路上最可能遇到的）

| 报错 | 原因 | 改法 |
|---|---|---|
| `No suitable application records were found` | 没建 App 记录（1.3） | appstoreconnect 里建 App |
| `No profiles for 'com.lab.trackersweep' were found` | 集成名字不对 / App ID 没建 | 检查 `ASC_KEY` 拼写、1.1 的 Bundle ID 完全一致 |
| `Authentication credentials are missing or invalid` | `.p8` 粘错 / Key ID 填错 | 重新生成 Key，注意 `.p8` 要整段含 BEGIN/END |
| `The bundle version must be higher than the previously uploaded version` | build 号没变 | 已加自动递增步骤；确认日志里 `CFBundleVersion -> xxx` |
| `ITMS-90022 / Missing required icon file` | 缺 AppIcon | 仓库已带 1024 图标 + Assets.car（`tools/gen_icon.py` 可重生成） |
| `Invalid Bundle. The bundle at ... does not support the minimum OS Version` | 部署目标高于设备 | 工程是 iOS 16.0；确认手机 ≥ 16 |
| `Provisioning profile doesn't include device UDID` | ad hoc 但设备没注册 | 做 3.2 Step 2，然后**重跑**构建（profile 会重新生成） |
| `Two-factor authentication required`（Sideloadly 路线） | 用了免费/个人账号 | 已在走 TestFlight 时不会遇到 |

---

## 6. 本地先验（不消耗云端额度）

```powershell
cd E:\deepseeek\tracker-sweep
python tools\check_pbxproj.py     # 工程结构
python tools\check_sources.py     # 源码完整性
python tools\check_ci.py          # codemagic.yaml / 签名配置 / 图标 / bundle id 一致性
```

当前状态（我在这台 Windows 上跑过）：

```
结论：结构完整，Xcode 可以打开
结论：全部通过
结论：全部通过，可以推上去构建
```

---

## 7. 账号相关的两个小提醒

- **ad hoc 每账号每年 100 台设备**，注册进去当年度不可删除（只能等下个年度重置）。别把不认识的 UDID 加进去。
- **TestFlight 每个 App 最多 100 个内部测试员 + 10000 个外部测试员**，内部测试员不需要审核，外部第一个构建要过 Beta App Review。
- 证书有效期 1 年。Codemagic 在 `use-profiles` 时会自动检查，过期会自动重新签发 —— 你不需要手动管证书。
