#!/usr/bin/env python3
"""生成 DeepChat.xcodeproj/project.pbxproj 与共享 Scheme。

手工维护 pbxproj 容易出错，所以用脚本扫描源码目录自动生成，
后续新增 Swift 文件后重新运行本脚本即可。
"""
import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_NAME = "DeepChat"
TARGET_NAME = "DeepChat"
BUNDLE_ID = "com.deepchat.app"
DEPLOYMENT_TARGET = "17.0"
MARKETING_VERSION = "1.0.0"
BUILD_VERSION = "1"
SWIFT_VERSION = "5.0"

SRC_DIR = os.path.join(ROOT, PROJECT_NAME)
XCODEPROJ = os.path.join(ROOT, PROJECT_NAME + ".xcodeproj")


def oid(key: str) -> str:
    """生成稳定的 24 位十六进制对象 ID"""
    return hashlib.md5(key.encode("utf-8")).hexdigest()[:24].upper()


def collect_swift():
    groups = {}
    for dirpath, dirnames, filenames in os.walk(SRC_DIR):
        dirnames.sort()
        rel_dir = os.path.relpath(dirpath, SRC_DIR)
        swift = sorted(f for f in filenames if f.endswith(".swift"))
        if not swift:
            continue
        groups[rel_dir] = swift
    return groups


def quote(value: str) -> str:
    if value == "":
        return '""'
    safe = all(c.isalnum() or c in "._$/-" for c in value)
    if safe:
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build():
    groups = collect_swift()
    top_files = groups.get(".", [])

    # ---- 对象 ID ----
    ids = {
        "project": oid("project"),
        "target": oid("target"),
        "product": oid("product"),
        "mainGroup": oid("mainGroup"),
        "sourceGroup": oid("group:" + PROJECT_NAME),
        "productsGroup": oid("productsGroup"),
        "sourcesPhase": oid("sourcesPhase"),
        "frameworksPhase": oid("frameworksPhase"),
        "resourcesPhase": oid("resourcesPhase"),
        "projectConfigList": oid("projectConfigList"),
        "targetConfigList": oid("targetConfigList"),
        "projectDebug": oid("projectDebug"),
        "projectRelease": oid("projectRelease"),
        "targetDebug": oid("targetDebug"),
        "targetRelease": oid("targetRelease"),
        "assetsRef": oid("file:Assets.xcassets"),
        "assetsBuild": oid("build:Assets.xcassets"),
        "plistRef": oid("file:Info.plist"),
    }

    file_refs = {}   # relpath -> id
    build_files = {}  # relpath -> id

    for rel_dir, files in groups.items():
        for name in files:
            rel = name if rel_dir == "." else os.path.join(rel_dir, name)
            rel = rel.replace("\\", "/")
            file_refs[rel] = oid("file:" + rel)
            build_files[rel] = oid("build:" + rel)

    subgroup_ids = {}
    for rel_dir in groups:
        if rel_dir == ".":
            continue
        subgroup_ids[rel_dir] = oid("group:" + rel_dir)

    L = []
    w = L.append

    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {")
    w("\t};")
    w("\tobjectVersion = 56;")
    w("\tobjects = {")
    w("")

    # ---------- PBXBuildFile ----------
    w("/* Begin PBXBuildFile section */")
    for rel in sorted(build_files):
        fid = file_refs[rel]
        name = os.path.basename(rel)
        w("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
          % (build_files[rel], name, fid, name))
    w("\t\t%s /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = %s /* Assets.xcassets */; };"
      % (ids["assetsBuild"], ids["assetsRef"]))
    w("/* End PBXBuildFile section */")
    w("")

    # ---------- PBXFileReference ----------
    w("/* Begin PBXFileReference section */")
    for rel in sorted(file_refs):
        name = os.path.basename(rel)
        w("\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = %s; sourceTree = \"<group>\"; };"
          % (file_refs[rel], name, quote(name)))
    w("\t\t%s /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; };"
      % ids["assetsRef"])
    w("\t\t%s /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; };"
      % ids["plistRef"])
    w("\t\t%s /* %s.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = %s.app; sourceTree = BUILT_PRODUCTS_DIR; };"
      % (ids["product"], TARGET_NAME, TARGET_NAME))
    w("/* End PBXFileReference section */")
    w("")

    # ---------- PBXFrameworksBuildPhase ----------
    w("/* Begin PBXFrameworksBuildPhase section */")
    w("\t\t%s /* Frameworks */ = {" % ids["frameworksPhase"])
    w("\t\t\tisa = PBXFrameworksBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXFrameworksBuildPhase section */")
    w("")

    # ---------- PBXGroup ----------
    w("/* Begin PBXGroup section */")
    # 项目根组：只放源码组和 Products
    w("\t\t%s = {" % ids["mainGroup"])
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w("\t\t\t\t%s /* %s */," % (ids["sourceGroup"], PROJECT_NAME))
    w("\t\t\t\t%s /* Products */," % ids["productsGroup"])
    w("\t\t\t);")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

    # 源码组：path = DeepChat，包含源码文件、子目录、资源
    source_children = []
    for name in top_files:
        source_children.append((file_refs[name], os.path.basename(name)))
    for rel_dir in sorted(subgroup_ids):
        if "/" in rel_dir:
            continue
        source_children.append((subgroup_ids[rel_dir], rel_dir))
    source_children.append((ids["assetsRef"], "Assets.xcassets"))
    source_children.append((ids["plistRef"], "Info.plist"))

    w("\t\t%s /* %s */ = {" % (ids["sourceGroup"], PROJECT_NAME))
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for cid, cname in source_children:
        w("\t\t\t\t%s /* %s */," % (cid, cname))
    w("\t\t\t);")
    w("\t\t\tpath = %s;" % PROJECT_NAME)
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

    # 子分组（支持多级）
    for rel_dir in sorted(subgroup_ids):
        depth = rel_dir.count("/") + 1
        children = []
        for name in groups[rel_dir]:
            rel = os.path.join(rel_dir, name).replace("\\", "/")
            children.append((file_refs[rel], name))
        prefix = rel_dir + "/"
        for other in sorted(subgroup_ids):
            if other.startswith(prefix) and "/" not in other[len(prefix):]:
                children.append((subgroup_ids[other], other.split("/")[-1]))
        w("\t\t%s /* %s */ = {" % (subgroup_ids[rel_dir], rel_dir.split("/")[-1]))
        w("\t\t\tisa = PBXGroup;")
        w("\t\t\tchildren = (")
        for cid, cname in children:
            w("\t\t\t\t%s /* %s */," % (cid, cname))
        w("\t\t\t);")
        w("\t\t\tpath = %s;" % quote(rel_dir.split("/")[-1]))
        w("\t\t\tsourceTree = \"<group>\";")
        w("\t\t};")

    w("\t\t%s /* Products */ = {" % ids["productsGroup"])
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w("\t\t\t\t%s /* %s.app */," % (ids["product"], TARGET_NAME))
    w("\t\t\t);")
    w("\t\t\tname = Products;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w("/* End PBXGroup section */")
    w("")

    # ---------- PBXNativeTarget ----------
    w("/* Begin PBXNativeTarget section */")
    w("\t\t%s /* %s */ = {" % (ids["target"], TARGET_NAME))
    w("\t\t\tisa = PBXNativeTarget;")
    w("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"%s\" */;"
      % (ids["targetConfigList"], TARGET_NAME))
    w("\t\t\tbuildPhases = (")
    w("\t\t\t\t%s /* Sources */," % ids["sourcesPhase"])
    w("\t\t\t\t%s /* Frameworks */," % ids["frameworksPhase"])
    w("\t\t\t\t%s /* Resources */," % ids["resourcesPhase"])
    w("\t\t\t);")
    w("\t\t\tbuildRules = (")
    w("\t\t\t);")
    w("\t\t\tdependencies = (")
    w("\t\t\t);")
    w("\t\t\tname = %s;" % TARGET_NAME)
    w("\t\t\tproductName = %s;" % TARGET_NAME)
    w("\t\t\tproductReference = %s /* %s.app */;" % (ids["product"], TARGET_NAME))
    w("\t\t\tproductType = \"com.apple.product-type.application\";")
    w("\t\t};")
    w("/* End PBXNativeTarget section */")
    w("")

    # ---------- PBXProject ----------
    w("/* Begin PBXProject section */")
    w("\t\t%s /* Project object */ = {" % ids["project"])
    w("\t\t\tisa = PBXProject;")
    w("\t\t\tattributes = {")
    w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    w("\t\t\t\tLastSwiftUpdateCheck = 1500;")
    w("\t\t\t\tLastUpgradeCheck = 1500;")
    w("\t\t\t\tTargetAttributes = {")
    w("\t\t\t\t\t%s = {" % ids["target"])
    w("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    w("\t\t\t\t\t};")
    w("\t\t\t\t};")
    w("\t\t\t};")
    w("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject \"%s\" */;"
      % (ids["projectConfigList"], PROJECT_NAME))
    w("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    w("\t\t\tdevelopmentRegion = en;")
    w("\t\t\thasScannedForEncodings = 0;")
    w("\t\t\tknownRegions = (")
    w("\t\t\t\ten,")
    w("\t\t\t\tBase,")
    w("\t\t\t\t\"zh-Hans\",")
    w("\t\t\t);")
    w("\t\t\tmainGroup = %s;" % ids["mainGroup"])
    w("\t\t\tproductRefGroup = %s /* Products */;" % ids["productsGroup"])
    w("\t\t\tprojectDirPath = \"\";")
    w("\t\t\tprojectRoot = \"\";")
    w("\t\t\ttargets = (")
    w("\t\t\t\t%s /* %s */," % (ids["target"], TARGET_NAME))
    w("\t\t\t);")
    w("\t\t};")
    w("/* End PBXProject section */")
    w("")

    # ---------- PBXResourcesBuildPhase ----------
    w("/* Begin PBXResourcesBuildPhase section */")
    w("\t\t%s /* Resources */ = {" % ids["resourcesPhase"])
    w("\t\t\tisa = PBXResourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    w("\t\t\t\t%s /* Assets.xcassets in Resources */," % ids["assetsBuild"])
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXResourcesBuildPhase section */")
    w("")

    # ---------- PBXSourcesBuildPhase ----------
    w("/* Begin PBXSourcesBuildPhase section */")
    w("\t\t%s /* Sources */ = {" % ids["sourcesPhase"])
    w("\t\t\tisa = PBXSourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for rel in sorted(build_files):
        w("\t\t\t\t%s /* %s in Sources */," % (build_files[rel], os.path.basename(rel)))
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXSourcesBuildPhase section */")
    w("")

    # ---------- XCBuildConfiguration ----------
    project_common = [
        "ALWAYS_SEARCH_USER_PATHS = NO;",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;",
        "CLANG_ANALYZER_NONNULL = YES;",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;",
        "CLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";",
        "CLANG_ENABLE_MODULES = YES;",
        "CLANG_ENABLE_OBJC_ARC = YES;",
        "CLANG_ENABLE_OBJC_WEAK = YES;",
        "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;",
        "CLANG_WARN_BOOL_CONVERSION = YES;",
        "CLANG_WARN_COMMA = YES;",
        "CLANG_WARN_CONSTANT_CONVERSION = YES;",
        "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;",
        "CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;",
        "CLANG_WARN_DOCUMENTATION_COMMENTS = YES;",
        "CLANG_WARN_EMPTY_BODY = YES;",
        "CLANG_WARN_ENUM_CONVERSION = YES;",
        "CLANG_WARN_INFINITE_RECURSION = YES;",
        "CLANG_WARN_INT_CONVERSION = YES;",
        "CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;",
        "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;",
        "CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;",
        "CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;",
        "CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;",
        "CLANG_WARN_STRICT_PROTOTYPES = YES;",
        "CLANG_WARN_SUSPICIOUS_MOVE = YES;",
        "CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;",
        "CLANG_WARN_UNREACHABLE_CODE = YES;",
        "CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;",
        "COPY_PHASE_STRIP = NO;",
        "ENABLE_STRICT_OBJC_MSGSEND = YES;",
        "ENABLE_USER_SCRIPT_SANDBOXING = YES;",
        "GCC_C_LANGUAGE_STANDARD = gnu17;",
        "GCC_NO_COMMON_BLOCKS = YES;",
        "GCC_WARN_64_TO_32_BIT_CONVERSION = YES;",
        "GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;",
        "GCC_WARN_UNDECLARED_SELECTOR = YES;",
        "GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;",
        "GCC_WARN_UNUSED_FUNCTION = YES;",
        "GCC_WARN_UNUSED_VARIABLE = YES;",
        "IPHONEOS_DEPLOYMENT_TARGET = %s;" % DEPLOYMENT_TARGET,
        "LOCALIZATION_PREFERS_STRING_CATALOGS = YES;",
        "MTL_FAST_MATH = YES;",
        "SDKROOT = iphoneos;",
        "SWIFT_EMIT_LOC_STRINGS = YES;",
    ]

    project_debug_extra = [
        "DEBUG_INFORMATION_FORMAT = dwarf;",
        "ENABLE_TESTABILITY = YES;",
        "GCC_DYNAMIC_NO_PIC = NO;",
        "GCC_OPTIMIZATION_LEVEL = 0;",
        "GCC_PREPROCESSOR_DEFINITIONS = (",
        "\t\t\t\t\t\"DEBUG=1\",",
        "\t\t\t\t\t\"$(inherited)\",",
        "\t\t\t\t);",
        "MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;",
        "ONLY_ACTIVE_ARCH = YES;",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\";",
        "SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";",
    ]

    project_release_extra = [
        "DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";",
        "ENABLE_NS_ASSERTIONS = NO;",
        "MTL_ENABLE_DEBUG_INFO = NO;",
        "SWIFT_COMPILATION_MODE = wholemodule;",
        "SWIFT_OPTIMIZATION_LEVEL = \"-O\";",
        "VALIDATE_PRODUCT = YES;",
    ]

    target_common = [
        "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;",
        "CODE_SIGN_STYLE = Automatic;",
        "CURRENT_PROJECT_VERSION = %s;" % BUILD_VERSION,
        "DEVELOPMENT_TEAM = \"\";",
        "ENABLE_PREVIEWS = YES;",
        "GENERATE_INFOPLIST_FILE = NO;",
        "INFOPLIST_FILE = %s/Info.plist;" % PROJECT_NAME,
        "LD_RUNPATH_SEARCH_PATHS = (",
        "\t\t\t\t\t\"$(inherited)\",",
        "\t\t\t\t\t\"@executable_path/Frameworks\",",
        "\t\t\t\t);",
        "MARKETING_VERSION = %s;" % MARKETING_VERSION,
        "PRODUCT_BUNDLE_IDENTIFIER = %s;" % BUNDLE_ID,
        "PRODUCT_NAME = \"$(TARGET_NAME)\";",
        "SWIFT_VERSION = %s;" % SWIFT_VERSION,
        "TARGETED_DEVICE_FAMILY = \"1,2\";",
    ]

    def config_block(cid: str, name: str, settings, comment):
        w("\t\t%s /* %s */ = {" % (cid, name))
        w("\t\t\tisa = XCBuildConfiguration;")
        w("\t\t\tbuildSettings = {")
        for line in settings:
            if line.startswith("\t") or line.endswith(");"):
                w(line)
            else:
                w("\t\t\t\t" + line)
        w("\t\t\t};")
        w("\t\t\tname = %s;" % name)
        w("\t\t};")

    w("/* Begin XCBuildConfiguration section */")
    config_block(ids["projectDebug"], "Debug", project_common + project_debug_extra, None)
    config_block(ids["projectRelease"], "Release", project_common + project_release_extra, None)
    config_block(ids["targetDebug"], "Debug", target_common, None)
    config_block(ids["targetRelease"], "Release", target_common, None)
    w("/* End XCBuildConfiguration section */")
    w("")

    # ---------- XCConfigurationList ----------
    w("/* Begin XCConfigurationList section */")
    w("\t\t%s /* Build configuration list for PBXProject \"%s\" */ = {"
      % (ids["projectConfigList"], PROJECT_NAME))
    w("\t\t\tisa = XCConfigurationList;")
    w("\t\t\tbuildConfigurations = (")
    w("\t\t\t\t%s /* Debug */," % ids["projectDebug"])
    w("\t\t\t\t%s /* Release */," % ids["projectRelease"])
    w("\t\t\t);")
    w("\t\t\tdefaultConfigurationIsVisible = 0;")
    w("\t\t\tdefaultConfigurationName = Release;")
    w("\t\t};")
    w("\t\t%s /* Build configuration list for PBXNativeTarget \"%s\" */ = {"
      % (ids["targetConfigList"], TARGET_NAME))
    w("\t\t\tisa = XCConfigurationList;")
    w("\t\t\tbuildConfigurations = (")
    w("\t\t\t\t%s /* Debug */," % ids["targetDebug"])
    w("\t\t\t\t%s /* Release */," % ids["targetRelease"])
    w("\t\t\t);")
    w("\t\t\tdefaultConfigurationIsVisible = 0;")
    w("\t\t\tdefaultConfigurationName = Release;")
    w("\t\t};")
    w("/* End XCConfigurationList section */")

    w("\t};")
    w("\trootObject = %s /* Project object */;" % ids["project"])
    w("}")
    w("")

    content = "\n".join(L)

    os.makedirs(XCODEPROJ, exist_ok=True)
    with open(os.path.join(XCODEPROJ, "project.pbxproj"), "w", encoding="utf-8", newline="\n") as f:
        f.write(content)

    write_scheme(ids)
    print("project.pbxproj 生成完成：%d 个 Swift 文件" % sum(len(v) for v in groups.values()))
    return ids, file_refs, groups


def write_scheme(ids):
    scheme_dir = os.path.join(XCODEPROJ, "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir, exist_ok=True)
    xml = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target}"
               BuildableName = "{name}.app"
               BlueprintName = "{name}"
               ReferencedContainer = "container:{project}.xcodeproj">
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
            BlueprintIdentifier = "{target}"
            BuildableName = "{name}.app"
            BlueprintName = "{name}"
            ReferencedContainer = "container:{project}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target}"
            BuildableName = "{name}.app"
            BlueprintName = "{name}"
            ReferencedContainer = "container:{project}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
""".replace("{target}", ids["target"]) \
   .replace("{name}", TARGET_NAME) \
   .replace("{project}", PROJECT_NAME)

    with open(os.path.join(scheme_dir, PROJECT_NAME + ".xcscheme"), "w", encoding="utf-8", newline="\n") as f:
        f.write(xml)


def validate(pbxproj_path):
    """检查所有被引用的对象 ID 都有定义"""
    with open(pbxproj_path, "r", encoding="utf-8") as f:
        text = f.read()

    defined = set()
    for line in text.splitlines():
        stripped = line.strip()
        if " = {" in stripped and len(stripped.split()[0]) == 24:
            defined.add(stripped.split()[0])

    import re
    refs = set(re.findall(r"\b([0-9A-F]{24})\b", text))
    missing = sorted(r for r in refs if r not in defined)
    if missing:
        print("存在未定义的对象引用：", missing, file=sys.stderr)
        return False
    print("校验通过：%d 个对象，%d 处引用" % (len(defined), len(refs)))
    return True


if __name__ == "__main__":
    ids, refs, groups = build()
    path = os.path.join(XCODEPROJ, "project.pbxproj")
    ok = validate(path)
    sys.exit(0 if ok else 1)
