#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_pbxproj.py — 在没有 Xcode 的情况下验证 project.pbxproj 的结构完整性

检查项：
  1. 括号/花括号平衡
  2. 所有被引用的 24 位对象 ID 都有定义（悬空引用会让 Xcode 直接打不开）
  3. 所有定义的 ID 都被引用（孤儿对象只是冗余，不算错，但会提示）
  4. 必需的 section 与 rootObject 是否存在
  5. 每个 Swift 源文件都进了 Sources 编译阶段
  6. scheme 里引用的 BlueprintIdentifier 与 target ID 一致
"""
import collections
import os
import re
import sys
import xml.etree.ElementTree as ET

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBX = os.path.join(ROOT, "LeadRadar.xcodeproj", "project.pbxproj")
SCHEME = os.path.join(ROOT, "LeadRadar.xcodeproj", "xcshareddata",
                      "xcschemes", "LeadRadar.xcscheme")

ok = True


def fail(msg):
    global ok
    ok = False
    print("  ✗", msg)


def good(msg):
    print("  ✓", msg)


src = open(PBX, encoding="utf-8").read()

# 1. 平衡
if src.count("{") != src.count("}") or src.count("(") != src.count(")"):
    fail("括号不平衡: {}=%d/%d ()=%d/%d" % (src.count("{"), src.count("}"),
                                             src.count("("), src.count(")")))
else:
    good("括号平衡 ({}=%d)" % src.count("{"))

# 2. 定义 vs 引用
defs = set(re.findall(r"^\s*([0-9A-F]{24})\s*(?:/\*.*?\*/)?\s*=\s*\{", src, re.M))
refs = set(re.findall(r"\b([0-9A-F]{24})\b", src))

dangling = refs - defs
if dangling:
    fail("悬空引用（未定义的对象）: %s" % sorted(dangling))
else:
    good("无悬空引用（%d 个对象全部有定义）" % len(defs))

orphan = defs - refs
if orphan:
    print("  · 提示：%d 个对象未被引用（Xcode 会忽略，不影响打开）" % len(orphan))


# 2b. 对象 ID 重复定义（会让某个文件被"顶掉"，症状是 cannot find X in scope）
scan_src = re.sub(r"TargetAttributes = \{.*?\n\t\t\t\};", "", src, flags=re.S)
ids = re.findall(r"^\s*([0-9A-F]{24})\s*(?:/\*.*?\*/)?\s*=\s*\{", scan_src, re.M)
dups = [k for k, v in collections.Counter(ids).items() if v > 1]
if dups:
    fail("对象 ID 重复定义（会导致源文件被覆盖/不参与编译）: %s" % dups)
else:
    good("对象 ID 无重复（%d 个）" % len(ids))

# 3. 必需 section
need = ["PBXBuildFile", "PBXFileReference", "PBXFrameworksBuildPhase", "PBXGroup",
        "PBXNativeTarget", "PBXProject", "PBXResourcesBuildPhase",
        "PBXSourcesBuildPhase", "XCBuildConfiguration", "XCConfigurationList"]
miss = [n for n in need if ("/* Begin %s section */" % n) not in src]
if miss:
    fail("缺 section: %s" % miss)
else:
    good("10 个 section 齐全")

if "rootObject" not in src:
    fail("缺 rootObject")
else:
    good("rootObject 存在")

# 4. 源文件进编译
swifts = [f for f in os.listdir(os.path.join(ROOT, "LeadRadar"))
          if f.endswith(".swift")]
for f in swifts:
    if ("%s in Sources" % f) not in src:
        fail("%s 没进 Sources 编译阶段" % f)
else:
    if swifts:
        good("%d 个 Swift 文件全部进 Sources" % len(swifts))

# 5. scheme 一致
if os.path.exists(SCHEME):
    try:
        tree = ET.parse(SCHEME)
        bp = [e.get("BlueprintIdentifier") for e in tree.iter("BuildableReference")]
        target_ids = {i for i in defs
                      if re.search(r"%s\s*(?:/\*.*?\*/)?\s*=\s*\{\s*\n\s*isa = PBXNativeTarget" % i, src)}
        if bp and target_ids and bp[0] in target_ids:
            good("scheme BlueprintIdentifier 与 target 一致 (%s)" % bp[0])
        else:
            fail("scheme 指向的 target ID 不存在：%s vs %s" % (bp, target_ids))
    except Exception as e:
        fail("scheme XML 解析失败: %s" % e)
else:
    fail("缺 scheme 文件")

print()
print("结论：" + ("结构完整，Xcode 可以打开" if ok else "存在问题，需要修"))
sys.exit(0 if ok else 1)
