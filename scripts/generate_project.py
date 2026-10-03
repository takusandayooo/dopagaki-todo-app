#!/usr/bin/env python3
"""Generate the native Xcode project without third-party project generators."""
from pathlib import Path
import hashlib
import plistlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def ident(key):
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()


def add(key, isa, **fields):
    uid = ident(key)
    objects[uid] = {"isa": isa, **fields}
    return uid


def config_list(key, settings):
    configs = []
    for mode in ["Debug", "Release"]:
        values = dict(settings)
        values.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O",
                       "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if mode == "Debug" else ""})
        configs.append(add(f"{key}.{mode}", "XCBuildConfiguration", name=mode, buildSettings=values))
    return add(f"{key}.configs", "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


def plist(path, data):
    path = ROOT / path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(plistlib.dumps(data, sort_keys=False))


def generate():
    shared = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "Shared").rglob("*.swift"))
    specs = [
        ("Dopagaki", "dev.dopagaki.todo", "com.apple.product-type.application", "app", sorted(str(p.relative_to(ROOT)) for p in (ROOT / "App").rglob("*.swift")) + shared, "App/Info.plist", None),
        ("ActivityMonitor", "dev.dopagaki.todo.ActivityMonitor", "com.apple.product-type.app-extension", "appex", ["Extensions/ActivityMonitor/ActivityMonitor.swift"] + shared, "Extensions/ActivityMonitor/Info.plist", "com.apple.deviceactivity.monitor-extension"),
        ("ShieldConfiguration", "dev.dopagaki.todo.ShieldConfiguration", "com.apple.product-type.app-extension", "appex", ["Extensions/ShieldConfiguration/ShieldConfigurationExtension.swift"], "Extensions/ShieldConfiguration/Info.plist", "com.apple.ManagedSettingsUI.shield-configuration-service"),
        ("ProgressWidget", "dev.dopagaki.todo.ProgressWidget", "com.apple.product-type.app-extension", "appex", ["Extensions/ProgressWidget/ProgressWidget.swift", "Shared/WidgetSnapshotRepository.swift"], "Extensions/ProgressWidget/Info.plist", "com.apple.widgetkit-extension"),
        ("ShieldAction", "dev.dopagaki.todo.ShieldAction", "com.apple.product-type.app-extension", "appex", ["Extensions/ShieldAction/ShieldActionExtension.swift"], "Extensions/ShieldAction/Info.plist", "com.apple.ManagedSettings.shield-action-service"),
    ]
    files = []
    for path in sorted(set(p for spec in specs for p in spec[4])):
        files.append(add("file." + path, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=path, sourceTree="SOURCE_ROOT"))
    for path in ["SPEC.md", "README.md"]:
        files.append(add("file." + path, "PBXFileReference", lastKnownFileType="net.daringfireball.markdown", path=path, sourceTree="SOURCE_ROOT"))
    catalog = "App/Assets.xcassets"
    files.append(add("file." + catalog, "PBXFileReference", lastKnownFileType="folder.assetcatalog", path=catalog, sourceTree="SOURCE_ROOT"))
    sounds = "App/Resources/RewardSounds"
    files.append(add("file." + sounds, "PBXFileReference", lastKnownFileType="folder", path=sounds, sourceTree="SOURCE_ROOT"))
    privacy = "App/PrivacyInfo.xcprivacy"
    files.append(add("file." + privacy, "PBXFileReference", lastKnownFileType="text.xml", path=privacy, sourceTree="SOURCE_ROOT"))
    package = add("package.core", "XCLocalSwiftPackageReference", relativePath=".")
    project = ident("project")
    products, targets = [], []
    for name, bundle, product_type, suffix, sources, info_path, extension_point in specs:
        product = add("product." + name, "PBXFileReference", explicitFileType="wrapper.application" if suffix == "app" else "wrapper.app-extension", path=f"{name}.{suffix}", sourceTree="BUILT_PRODUCTS_DIR", includeInIndex=0)
        products.append(product)
        builds = [add(f"build.{name}.{p}", "PBXBuildFile", fileRef=ident("file." + p)) for p in sources]
        source_phase = add("sources." + name, "PBXSourcesBuildPhase", buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)
        package_deps, framework_builds = [], []
        if name in ["Dopagaki", "ActivityMonitor", "ProgressWidget"]:
            dep = add("dependency.core." + name, "XCSwiftPackageProductDependency", package=package, productName="DopagakiCore")
            package_deps.append(dep)
            framework_builds.append(add("build.core." + name, "PBXBuildFile", productRef=dep))
        frameworks = add("frameworks." + name, "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=framework_builds, runOnlyForDeploymentPostprocessing=0)
        resource_files = [add("build.assets." + name, "PBXBuildFile", fileRef=ident("file." + catalog))] if name == "Dopagaki" else []
        if name == "Dopagaki":
            resource_files.append(add("build.Dopagaki." + sounds, "PBXBuildFile", fileRef=ident("file." + sounds)))
            resource_files.append(add("build.Dopagaki." + privacy, "PBXBuildFile", fileRef=ident("file." + privacy)))
        resources = add("resources." + name, "PBXResourcesBuildPhase", buildActionMask=2147483647, files=resource_files, runOnlyForDeploymentPostprocessing=0)
        entitlements_path = "App/Dopagaki.entitlements" if name == "Dopagaki" else f"Extensions/{name}/{name}.entitlements"
        entitlements = {"com.apple.security.application-groups": ["$(DOPA_APP_GROUP)"]}
        if name != "ProgressWidget":
            entitlements["com.apple.developer.family-controls"] = True
        plist(entitlements_path, entitlements)
        info = {"CFBundleDevelopmentRegion": "ja", "CFBundleDisplayName": "ドパギキ" if name == "Dopagaki" else name,
                "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
                "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": "$(PRODUCT_NAME)",
                "CFBundlePackageType": "APPL" if name == "Dopagaki" else "XPC!", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1", "DopaAppGroup": "$(DOPA_APP_GROUP)", "DopaURLScheme": "$(DOPA_URL_SCHEME)"}
        if extension_point:
            principal = "ActivityMonitor" if name == "ActivityMonitor" else name + "Extension"
            info["NSExtension"] = {"NSExtensionPointIdentifier": extension_point}
            if name != "ProgressWidget":
                info["NSExtension"]["NSExtensionPrincipalClass"] = f"$(PRODUCT_MODULE_NAME).{principal}"
        else:
            info.update({"LSRequiresIPhoneOS": True, "UILaunchScreen": {}, "UIUserInterfaceStyle": "Dark",
                         "ITSAppUsesNonExemptEncryption": False,
                         "CFBundleURLTypes": [{"CFBundleURLName": "dev.dopagaki.todo.navigation", "CFBundleURLSchemes": ["$(DOPA_URL_SCHEME)"]}],
                         "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
                         "NSMicrophoneUsageDescription": "取り組んだ内容を、話してメモに残すためにマイクを使用します。",
                         "NSSpeechRecognitionUsageDescription": "話した内容を文字に変換します。端末内認識が使えない場合はAppleの音声認識サービスを使用します。"})
        plist(info_path, info)
        settings = {"PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": bundle,
                    "INFOPLIST_FILE": info_path, "GENERATE_INFOPLIST_FILE": "NO",
                    "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "", "CODE_SIGN_ENTITLEMENTS": entitlements_path,
                    "DOPA_APP_GROUP": "group.dev.dopagaki.todo", "DOPA_URL_SCHEME": "dopagaki", "SWIFT_VERSION": "5.0", "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
                    "TARGETED_DEVICE_FAMILY": "1", "SDKROOT": "iphoneos", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
                    "ENABLE_PREVIEWS": "YES", "SWIFT_EMIT_LOC_STRINGS": "YES",
                    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks" if name == "Dopagaki" else "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"}
        if extension_point:
            settings.update({"APPLICATION_EXTENSION_API_ONLY": "YES", "SKIP_INSTALL": "YES"})
        else:
            settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
        config = config_list("config." + name, settings)
        target = add("target." + name, "PBXNativeTarget", name=name, productName=name, productType=product_type,
                     productReference=product, buildConfigurationList=config, buildPhases=[source_phase, frameworks, resources],
                     buildRules=[], dependencies=[], packageProductDependencies=package_deps)
        targets.append(target)
    embed_files, dependencies = [], []
    for name, *_ in specs[1:]:
        embed_files.append(add("embed." + name, "PBXBuildFile", fileRef=ident("product." + name), settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]}))
        proxy = add("proxy." + name, "PBXContainerItemProxy", containerPortal=project, proxyType=1, remoteGlobalIDString=ident("target." + name), remoteInfo=name)
        dependencies.append(add("targetdep." + name, "PBXTargetDependency", target=ident("target." + name), targetProxy=proxy))
    embed_phase = add("embed.phase", "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=13, files=embed_files, name="Embed App Extensions", runOnlyForDeploymentPostprocessing=0)
    objects[targets[0]]["dependencies"] = dependencies
    objects[targets[0]]["buildPhases"].append(embed_phase)
    product_group = add("products", "PBXGroup", children=products, name="Products", sourceTree="<group>")
    main_group = add("main", "PBXGroup", children=files + [product_group], sourceTree="<group>")
    config = config_list("project.config", {"CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "ENABLE_TESTABILITY": "YES", "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SWIFT_VERSION": "5.0", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym"})
    add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1600", "TargetAttributes": {t: {"CreatedOnToolsVersion": "16.0", "SystemCapabilities": {"com.apple.FamilyControls": {"enabled": 0 if t == ident("target.ProgressWidget") else 1}, "com.apple.ApplicationGroups.iOS": {"enabled": 1}}} for t in targets}}, buildConfigurationList=config, compatibilityVersion="Xcode 14.0", developmentRegion="ja", knownRegions=["ja", "en", "Base"], mainGroup=main_group, productRefGroup=product_group, projectDirPath="", projectRoot="", targets=targets, packageReferences=[package])
    project_dir = ROOT / "Dopagaki.xcodeproj"
    project_dir.mkdir(exist_ok=True)
    # JSON-form OpenStep property lists are accepted by plutil; convert to ASCII below.
    def quote(value):
        if isinstance(value, dict):
            return "{\n" + "\n".join(f"{quote(k)} = {quote(v)};" for k, v in value.items()) + "\n}"
        if isinstance(value, list):
            return "(\n" + "\n".join(quote(x) + "," for x in value) + "\n)"
        if isinstance(value, int):
            return str(value)
        return json.dumps(value, ensure_ascii=False)
    data = {"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project}
    (project_dir / "project.pbxproj").write_text("// !$*UTF8*$!\n" + quote(data) + "\n")
    scheme = project_dir / "xcshareddata/xcschemes/Dopagaki.xcscheme"
    scheme.parent.mkdir(parents=True, exist_ok=True)
    scheme.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets[0]}" BuildableName="Dopagaki.app" BlueprintName="Dopagaki" ReferencedContainer="container:Dopagaki.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets[0]}" BuildableName="Dopagaki.app" BlueprintName="Dopagaki" ReferencedContainer="container:Dopagaki.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets[0]}" BuildableName="Dopagaki.app" BlueprintName="Dopagaki" ReferencedContainer="container:Dopagaki.xcodeproj"/></BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
    print(f"Generated {project_dir.name}: {len(targets)} targets, {len(objects)} project objects")


if __name__ == "__main__":
    generate()
