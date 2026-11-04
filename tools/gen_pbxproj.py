#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_pbxproj.py — 在没有 Mac 的机器上生成一份 Xcode 能直接打开的工程文件

为什么需要它：XcodeGen 是 Swift 程序，Windows 上跑不了。
但 .xcodeproj/project.pbxproj 只是 OpenStep 格式的纯文本，
完全可以手工生成 —— 只要 24 位十六进制对象 ID 前后一致就行。

用法：
    python tools/gen_pbxproj.py
生成：
    TrackerSweep.xcodeproj/project.pbxproj
    TrackerSweep.xcodeproj/xcshareddata/xcschemes/TrackerSweep.xcscheme
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ = "LeadRadar"
FILES = ["LDRadar.swift", "LDProtocol.swift", "LDEnrich.swift", "LDHoumenJS.swift", "LDWeb.swift", "LDViews.swift"]
PLIST = "Info.plist"
ASSET = "Assets.xcassets"
BUNDLE_ID = "com.lab.leadradar"
DEPLOY = "16.0"

# ---- 生成稳定的 24 位 ID（字符集只用大写十六进制） ----
def oid(n):
    return "AA" + format(n, "022X")          # 2 + 22 = 24


IDS = {
    "project":      oid(0x01),
    "main_group":   oid(0x02),
    "products":     oid(0x03),
    "app_group":    oid(0x04),
    "target":       oid(0x05),
    "product_ref":  oid(0x06),
    "sources":      oid(0x30),
    "frameworks":   oid(0x31),
    "resources":    oid(0x32),
    "proj_cfglist": oid(0x40),
    "proj_debug":   oid(0x41),
    "proj_release": oid(0x42),
    "tgt_cfglist":  oid(0x43),
    "tgt_debug":    oid(0x44),
    "tgt_release":  oid(0x45),
}
file_ref = {}
build_file = {}
for i, f in enumerate(FILES):
    file_ref[f] = oid(0x100 + i)
    build_file[f] = oid(0x200 + i)
file_ref[PLIST] = oid(0xE1)
file_ref[ASSET] = oid(0xE0)
build_file[ASSET] = oid(0xF0)

# ---- 片段 ----
HEADER = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n"

build_files = ""
for f in FILES:
    build_files += ("\t\t{b} /* {f} in Sources */ = {{isa = PBXBuildFile; "
                    "fileRef = {r} /* {f} */; }};\n").format(b=build_file[f], r=file_ref[f], f=f)
build_files += ("\t\t{b} /* {a} in Resources */ = {{isa = PBXBuildFile; "
                "fileRef = {r} /* {a} */; }};\n").format(b=build_file[ASSET], r=file_ref[ASSET], a=ASSET)

file_refs = ""
for f in FILES:
    file_refs += ("\t\t{r} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = "
                  "sourcecode.swift; path = {f}; sourceTree = \"<group>\"; }};\n").format(r=file_ref[f], f=f)
file_refs += ("\t\t{r} /* {p} */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; "
              "path = {p}; sourceTree = \"<group>\"; }};\n").format(r=file_ref[PLIST], p=PLIST)
file_refs += ("\t\t{r} /* {a} */ = {{isa = PBXFileReference; lastKnownFileType = "
              "folder.assetcatalog; path = {a}; sourceTree = \"<group>\"; }};\n").format(
                  r=file_ref[ASSET], a=ASSET)
file_refs += ("\t\t{p} /* {n}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; "
              "includeInIndex = 0; path = {n}.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n").format(
                  p=IDS["product_ref"], n=PROJ)

group_children = "\n".join(
    ["\t\t\t\t{r} /* {f} */,".format(r=file_ref[f], f=f) for f in FILES] +
    ["\t\t\t\t{r} /* {p} */,".format(r=file_ref[PLIST], p=PLIST)] +
    ["\t\t\t\t{r} /* {a} */,".format(r=file_ref[ASSET], a=ASSET)]
)
source_children = "\n".join(
    ["\t\t\t\t{b} /* {f} in Sources */,".format(b=build_file[f], f=f) for f in FILES]
)
resource_children = "\t\t\t\t{b} /* {a} in Resources */,".format(b=build_file[ASSET], a=ASSET)

COMMON = """\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {dep};
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_VERSION = 5.0;
""".format(dep=DEPLOY)

DEBUG = """\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
"""

RELEASE = """\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t\tVALIDATE_PRODUCT = YES;
"""

TARGET_COMMON = """\t\t\t\tCODE_SIGN_ENTITLEMENTS = LeadRadar/TrackerSweep.entitlements;
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = {proj}/Info.plist;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {bid};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
""".format(proj=PROJ, bid=BUNDLE_ID)

pbx = HEADER
pbx += "\n/* Begin PBXBuildFile section */\n" + build_files + "/* End PBXBuildFile section */\n"
pbx += "\n/* Begin PBXFileReference section */\n" + file_refs + "/* End PBXFileReference section */\n"

pbx += """
/* Begin PBXFrameworksBuildPhase section */
\t\t{fw} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */
""".format(fw=IDS["frameworks"])

pbx += """
/* Begin PBXGroup section */
\t\t{mg} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{ag} /* {proj} */,
\t\t\t\t{pg} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{pg} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{pr} /* {proj}.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{ag} /* {proj} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{children}
\t\t\t);
\t\t\tpath = {proj};
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */
""".format(mg=IDS["main_group"], pg=IDS["products"], ag=IDS["app_group"],
           pr=IDS["product_ref"], proj=PROJ, children=group_children)

pbx += """
/* Begin PBXNativeTarget section */
\t\t{tg} /* {proj} */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {tcl} /* Build configuration list for PBXNativeTarget "{proj}" */;
\t\t\tbuildPhases = (
\t\t\t\t{src} /* Sources */,
\t\t\t\t{fw} /* Frameworks */,
\t\t\t\t{res} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = {proj};
\t\t\tproductName = {proj};
\t\t\tproductReference = {pr} /* {proj}.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{pj} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{tg} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {pcl} /* Build configuration list for PBXProject "{proj}" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = zh-Hans;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\tzh-Hans,
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {mg};
\t\t\tproductRefGroup = {pg} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{tg} /* {proj} */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{res} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{rchildren}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{src} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{schildren}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */
""".format(proj=PROJ, tg=IDS["target"], tcl=IDS["tgt_cfglist"], src=IDS["sources"],
           fw=IDS["frameworks"], res=IDS["resources"], pr=IDS["product_ref"],
           pj=IDS["project"], pcl=IDS["proj_cfglist"], mg=IDS["main_group"],
           pg=IDS["products"], schildren=source_children, rchildren=resource_children)

pbx += """
/* Begin XCBuildConfiguration section */
\t\t{pd} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{common}{dbg}\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{prl} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{common}{rel}\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{td} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{tc}\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{trl} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{tc}\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{pcl} /* Build configuration list for PBXProject "{proj}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{pd} /* Debug */,
\t\t\t\t{prl} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{tcl} /* Build configuration list for PBXNativeTarget "{proj}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{td} /* Debug */,
\t\t\t\t{trl} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
""".format(proj=PROJ, pd=IDS["proj_debug"], prl=IDS["proj_release"],
           td=IDS["tgt_debug"], trl=IDS["tgt_release"],
           pcl=IDS["proj_cfglist"], tcl=IDS["tgt_cfglist"],
           common=COMMON, dbg=DEBUG, rel=RELEASE, tc=TARGET_COMMON)

pbx += "\t};\n\trootObject = " + IDS["project"] + " /* Project object */;\n}\n"

SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{tg}"
               BuildableName = "{proj}.app"
               BlueprintName = "{proj}"
               ReferencedContainer = "container:{proj}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{tg}"
            BuildableName = "{proj}.app"
            BlueprintName = "{proj}"
            ReferencedContainer = "container:{proj}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{tg}"
            BuildableName = "{proj}.app"
            BlueprintName = "{proj}"
            ReferencedContainer = "container:{proj}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
""".format(tg=IDS["target"], proj=PROJ)


def main():
    projdir = os.path.join(ROOT, PROJ + ".xcodeproj")
    os.makedirs(os.path.join(projdir, "xcshareddata", "xcschemes"), exist_ok=True)
    p = os.path.join(projdir, "project.pbxproj")
    with open(p, "w", encoding="utf-8", newline="\n") as f:
        f.write(pbx)
    s = os.path.join(projdir, "xcshareddata", "xcschemes", PROJ + ".xcscheme")
    with open(s, "w", encoding="utf-8", newline="\n") as f:
        f.write(SCHEME)
    print("written:", p, os.path.getsize(p), "bytes")
    print("written:", s, os.path.getsize(s), "bytes")


if __name__ == "__main__":
    main()
