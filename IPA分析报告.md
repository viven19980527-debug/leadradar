# LeadRadar IPA 逆向分析报告

分析对象：`C:\Users\Viven\Desktop\LeadRadar-v2.2-signed.ipa`（831 KB）
分析时间：2026-11-04
结论：**这就是我们自己做的获客工具 LeadRadar v2.2**，功能属实，但从模板继承了 7 项无关权限和错误的应用名，已修（v2.3）。

---

## 一、包结构

```
Payload/LeadRadar.app/
├── LeadRadar            732 KB   arm64 可执行文件
├── Info.plist                   配置
├── Assets.car                   图标资源
├── AppIcon60x60@2x.png          图标（继承自模板）
├── embedded.mobileprovision     AdHoc 描述文件
├── PkgInfo
└── _CodeSignature/              签名
总大小 829 KB
```

极小的体积说明：**纯 SwiftUI 应用，3 个源文件，没有任何第三方 SDK**（无统计、无广告、无崩溃上报）。

---

## 二、它到底怎么获客（数据流）

从二进制里提取出的全部网络端点，共 25 个，全部属于 B站/微博/抖音/快手/小红书 + Apple 证书服务：

```
B站（原生 HTTP，免登录）
  https://api.bilibili.com/x/web-interface/nav          取 wbi 签名密钥
  https://api.bilibili.com/x/web-interface/wbi/search/type   搜视频
  https://api.bilibili.com/x/v2/reply/wbi/main          一级评论
  https://api.bilibili.com/x/v2/reply/reply             子评论（翻页）
  https://space.bilibili.com/                           作者主页
  https://www.bilibili.com/video/                       来源视频

微博（内置浏览器）
  https://m.weibo.cn/search?containerid=100103type%3D1%26q%3D
  https://passport.weibo.cn/signin/login                登录页

抖音    https://www.douyin.com/search/  +  https://www.douyin.com/
快手    https://www.kuaishou.com/search/video?searchKey=  +  https://www.kuaishou.com/
小红书  https://www.xiaohongshu.com/search_result?keyword=  +  /explore
```

业务指纹确认：

| 指纹 | 存在 | 含义 |
|---|---|---|
| `mixin` | ✓ | wbi 签名混排表（B站签名算法） |
| `comment-item` | ✓ | DOM 兑底抓取选择器 |
| `bilibili / weibo / douyin / kuaishou / xiaohongshu` | ✓ | 五平台适配器 |
| `TrackerSweep / BLE / CoreBluetooth / magnetometer / jailbreak` | ✗ | 模板残留代码已清干净，**没有偷跑蓝牙、没有越狱检测** |

结论：**这是一个纯"抓公开评论 → 打分 → 出线索"的工具，没有隐藏行为。**

---

## 三、发现的问题（已全部修复）

### 问题 1：应用名是「反跟踪扫描」（继承自模板）

```xml
<key>CFBundleDisplayName</key>
<string>反跟踪扫描</string>   ← 装到桌面显示这个名字
```

### 问题 2：版本号是 3.8 / Build 38

```xml
<key>CFBundleShortVersionString</key>
<string>3.8</string>
<key>CFBundleVersion</key>
<string>38</string>
```

### 问题 3：申请了 7 项它根本用不到的权限 ← 最严重

```xml
NFCReaderUsageDescription                 读取 NFC 标签 UID 并发送 ISO7816 指令
NSBluetoothAlwaysUsageDescription         扫描周边蓝牙广播…
NSBluetoothPeripheralUsageDescription     蓝牙外设模式…
NSMotionUsageDescription                  读取磁力计…
NSLocationWhenInUseUsageDescription       读取 Wi-Fi 信息…
NSLocalNetworkUsageDescription            检查本地网络连通性…
NSMicrophoneUsageDescription              检测 15-24kHz 超声波信标…
UIBackgroundModes: [bluetooth-central, audio]
NSBonjourServices: [_http._tcp, _rtsp._tcp, _hap._tcp, _ssh._tcp …12 项]
NFC AIDs: [A0000002471001, A0000000031010 …10 项]
```

这些全是上一个项目（反跟踪扫描仪）的配置。后果：

- 打开 App 可能弹「是否允许访问蓝牙/麦克风/位置」——**用户会觉得这软件在偷东西**
- `audio` + `bluetooth-central` 后台模式会让系统认为你在后台录音/扫蓝牙 → 耗电异常、容易被系统杀
- 12 项 Bonjour 服务会触发本地网络权限弹窗

### 问题 4：ATS 允许任意明文 HTTP

```xml
NSAppTransportSecurity: { NSAllowsArbitraryLoads: true }
```

抓包代理可以轻松中间人。自用无影响，但属于不必要的口子。

---

## 四、修复后的 v2.3

Info.plist 从 3,465 字节精简到 928 字节：

```xml
<key>CFBundleDisplayName</key><string>获客雷达</string>     ← 桌面显示正确
<key>CFBundleShortVersionString</key><string>1.0</string>   ← 版本正确
<key>CFBundleVersion</key><string>1</string>
```

删除项：

```
✗ 7 项权限用途描述（NFC / 蓝牙×2 / 运动 / 定位 / 本地网络 / 麦克风）
✗ UIBackgroundModes（bluetooth-central, audio）
✗ NSBonjourServices（12 项）
✗ NFC AID 列表（10 项）
✗ NSAppTransportSecurity（不再允许明文 HTTP）
```

保留项：

```
✓ CFBundleIdentifier  com.lab.leadradar
✓ MinimumOSVersion    16.0
✓ UIDeviceFamily      [1] 仅 iPhone
✓ UIRequiredDeviceCapabilities  [arm64]
✓ UILaunchScreen / 竖屏
```

新版：`C:\Users\Viven\Desktop\LeadRadar-v2.3-signed.ipa`（830 KB，已装）

---

## 五、代码质量评估

| 维度 | 评价 |
|---|---|
| 体积 | 830 KB，无依赖，启动快 |
| 网络行为 | 只连 5 个平台 + Apple 证书，无第三方上报 |
| 本地存储 | 只有 UserDefaults（行业/关键词/平台开关/目标条数），不上传 |
| 隐私 | 抓的是**公开评论**；手机号/微信只在本地正则提取，不外传 |
| 风险 | 抖音/快手/小红书 依赖内置浏览器登录态，风控强时抓不到 |

## 六、还剩两个小瑕疵（不影响使用）

1. **图标是模板的**（`AppIcon60x60@2x.png`，反跟踪扫描仪那套）。要做自己的图标，给我一张 1024×1024 图我替换。
2. **Build 号固定为 1**，以后要覆盖安装新版本要注意改成递增，否则 iOS 可能不替换。

---

## 七、一句话总结

> 这个 IPA 就是我给你做的「获客雷达」v2.2。功能真实：B站原生抓评论，另外四家用内置浏览器抓。
> 但它是从「反跟踪扫描仪」模板改的，**带着 7 项无关权限和一个错误的应用名**——这种包一看就很可疑。
> v2.3 已把这些全部清掉，现在是一个干净的、只做获客的 App。
