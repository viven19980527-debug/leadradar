# -*- coding: utf-8 -*-
"""分析 LeadRadar IPA：结构 / 权限 / 权限描述 / 网络端点 / 残留模板组件"""
import os, plistlib, re, zipfile, subprocess, json

IPA = r"C:\Users\Viven\Desktop\LeadRadar-v2.2-signed.ipa"
TMP = os.path.join(os.environ["TEMP"], "ldr_analysis")

if os.path.exists(TMP):
    import shutil; shutil.rmtree(TMP, ignore_errors=True)
os.makedirs(TMP, exist_ok=True)
with zipfile.ZipFile(IPA) as z:
    z.extractall(TMP)

app = None
for root, dirs, files in os.walk(os.path.join(TMP, "Payload")):
    for d in dirs:
        if d.endswith(".app"):
            app = os.path.join(root, d); break
    if app: break

print("=== 1. 包结构 ===")
print(" app:", os.path.basename(app))
total = 0
for root, dirs, files in os.walk(app):
    for f in files:
        total += os.path.getsize(os.path.join(root, f))
print(f" 总大小: {total/1024:.0f} KB")
print(" 顶层:", sorted(os.listdir(app))[:20])

print("\n=== 2. Info.plist 权限与用途描述 ===")
pl = plistlib.loads(open(os.path.join(app, "Info.plist"), "rb").read())
keys = ["CFBundleIdentifier", "CFBundleDisplayName", "CFBundleName",
        "CFBundleShortVersionString", "CFBundleVersion", "MinimumOSVersion",
        "UIDeviceFamily", "UIRequiredDeviceCapabilities"]
for k in keys:
    if k in pl:
        print(f" {k}: {pl[k]}")

print("\n 权限描述（NS*UsageDescription）:")
found = False
for k, v in pl.items():
    if k.endswith("UsageDescription"):
        print(f"   {k}: {v}")
        found = True
if not found:
    print("   （无）")

print("\n ATS / 网络:")
ats = pl.get("NSAppTransportSecurity", {})
print("   NSAppTransportSecurity:", ats if ats else "（无，默认只允许 HTTPS）")

print("\n 后台模式:")
print("   UIBackgroundModes:", pl.get("UIBackgroundModes", "（无）"))

print("\n=== 3. 二进制里的网络端点 ===")
exe = os.path.join(app, pl.get("CFBundleExecutable", "LeadRadar"))
data = open(exe, "rb").read()
print(f" 可执行大小: {len(data)/1024:.0f} KB")

urls = set(re.findall(rb"https?://[A-Za-z0-9\.\-/_?=&%{}\[\]:,]+", data))
clean = sorted(u.decode(errors="ignore") for u in urls if len(u) > 12)
for u in clean[:40]:
    print("  ", u)
print(f" 端点总数: {len(clean)}")

print("\n=== 4. 平台与选择器（业务逻辑指纹）===")
for kw in [b"bilibili", b"weibo", b"douyin", b"kuaishou", b"xiaohongshu",
           b"comment-item", b"wbi_img", b"w_rid", b"mixin", b"midea"]:
    print(f"  {kw.decode():<14} {'✓' if kw in data else '—'}")

print("\n=== 5. 残留模板组件检查 ===")
for kw in [b"TrackerSweep", b"BLE", b"CoreBluetooth", b"NFCReaderSession",
           b"magnetometer", b"jailbreak"]:
    print(f"  {kw.decode():<18} {'有' if kw in data else '无'}")

print("\n=== 6. Swift 模块/类型（部分）===")
syms = set(re.findall(rb"_?\$s[A-Za-z0-9_]{10,}", data))
print(f" 符号数: {len(syms)}")
names = set()
for s in list(syms)[:4000]:
    t = s.decode(errors="ignore")
    m = re.findall(r"\d+([A-Za-z]{4,20})", t)
    for x in m:
        if x[0].isupper() and len(x) > 4:
            names.add(x)
print(" 类型名样例:", sorted(names)[:25])
