#!/usr/bin/env python3
"""Check source syntax and target references. Does not claim an iOS SDK build."""
from pathlib import Path
import json
import plistlib
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sources = sorted(p for folder in ["App", "Shared", "Extensions", "Core", "WatchApp"] for p in (ROOT / folder).rglob("*.swift"))
subprocess.run(["swiftc", "-frontend", "-parse"] + [str(p) for p in sources], check=True)
for folder in ["App", "Extensions", "WatchApp"]:
    for path in (ROOT / folder).rglob("*.plist"):
        plistlib.loads(path.read_bytes())
    for path in (ROOT / folder).rglob("*.entitlements"):
        plistlib.loads(path.read_bytes())
    for path in (ROOT / folder).rglob("*.xcprivacy"):
        plistlib.loads(path.read_bytes())
project_path = ROOT / "Dopagaki.xcodeproj/project.pbxproj"
subprocess.run(["plutil", "-lint", str(project_path)], check=True)
converted = subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(project_path)])
project = json.loads(converted)
objects = project["objects"]
for uid, entry in objects.items():
    if entry["isa"] == "PBXFileReference" and entry.get("sourceTree") == "SOURCE_ROOT":
        path = ROOT / entry["path"]
        assert path.is_dir() if entry.get("lastKnownFileType") in ["folder.assetcatalog", "folder"] else path.is_file(), entry["path"]
    if entry["isa"] == "PBXBuildFile":
        assert entry.get("fileRef", entry.get("productRef")) in objects, uid
targets = [o for o in objects.values() if o["isa"] == "PBXNativeTarget"]
assert {t["name"] for t in targets} == {"Dopagaki", "ActivityMonitor", "ShieldConfiguration", "ShieldAction", "ProgressWidget", "DopagakiWatch", "WatchProgressWidget"}
for target in targets:
    for phase in target["buildPhases"]:
        assert phase in objects
    for dep in target["dependencies"]:
        assert dep in objects
    if target["name"] in ["ProgressWidget", "WatchProgressWidget"]:
        for config in objects[target["buildConfigurationList"]]["buildConfigurations"]:
            settings = objects[config]["buildSettings"]
            entitlements = plistlib.loads((ROOT / settings["CODE_SIGN_ENTITLEMENTS"]).read_bytes())
            assert "com.apple.developer.family-controls" not in entitlements
            assert entitlements["com.apple.security.application-groups"] == ["$(DOPA_APP_GROUP)"]
        info = plistlib.loads((ROOT / f"Extensions/{target['name']}/Info.plist").read_bytes())
        assert info["NSExtension"] == {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}
    if target["name"] in ["DopagakiWatch", "WatchProgressWidget"]:
        for config in objects[target["buildConfigurationList"]]["buildConfigurations"]:
            settings = objects[config]["buildSettings"]
            assert settings["WATCHOS_DEPLOYMENT_TARGET"] == "10.0"
            assert settings["SDKROOT"] == "watchos"
            entitlements = plistlib.loads((ROOT / settings["CODE_SIGN_ENTITLEMENTS"]).read_bytes())
            assert "com.apple.developer.family-controls" not in entitlements
            assert entitlements["com.apple.security.application-groups"] == ["$(DOPA_APP_GROUP)"]
        if target["name"] == "DopagakiWatch":
            info = plistlib.loads((ROOT / "WatchApp/Info.plist").read_bytes())
            assert info["WKApplication"] is True
            assert info["WKCompanionAppBundleIdentifier"] == "$(DOPA_PHONE_BUNDLE_ID)"
            assert info["WKRunsIndependentlyOfCompanionApp"] is False
    if target["name"] == "Dopagaki":
        resource_phase = next(objects[p] for p in target["buildPhases"] if objects[p]["isa"] == "PBXResourcesBuildPhase")
        resources = {objects[objects[b]["fileRef"]]["path"] for b in resource_phase["files"]}
        assert "App/Assets.xcassets" in resources, "Missing app asset catalog"
        assert "App/Resources/RewardSounds" in resources, "Missing star impact sounds"
        assert "App/PrivacyInfo.xcprivacy" in resources, "Missing app privacy manifest"
        privacy = plistlib.loads((ROOT / "App/PrivacyInfo.xcprivacy").read_bytes())
        assert privacy["NSPrivacyTracking"] is False
        assert privacy["NSPrivacyCollectedDataTypes"] == []
        assert privacy["NSPrivacyAccessedAPITypes"] == [{
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategorySystemBootTime",
            "NSPrivacyAccessedAPITypeReasons": ["35F9.1"],
        }], "Review required-reason declarations against the current APIs"
        for index in range(1, 4):
            assert (ROOT / f"App/Resources/RewardSounds/star-impact-{index}.wav").is_file()
        for config in objects[target["buildConfigurationList"]]["buildConfigurations"]:
            assert objects[config]["buildSettings"].get("ASSETCATALOG_COMPILER_APPICON_NAME") == "AppIcon"
        source_phase = next(objects[p] for p in target["buildPhases"] if objects[p]["isa"] == "PBXSourcesBuildPhase")
        included = {objects[objects[b]["fileRef"]]["path"] for b in source_phase["files"]}
        expected = {str(p.relative_to(ROOT)) for folder in ["App", "Shared"] for p in (ROOT / folder).rglob("*.swift")}
        assert included == expected, f"Regenerate project: missing={expected - included}, stale={included - expected}"
watch = next(t for t in targets if t["name"] == "DopagakiWatch")
app = next(t for t in targets if t["name"] == "Dopagaki")
watch_phase = next(objects[p] for p in app["buildPhases"] if objects[p].get("dstSubfolderSpec") in [16, "16"])
assert watch_phase["dstPath"] == "$(CONTENTS_FOLDER_PATH)/Watch"
assert {objects[b]["fileRef"] for b in watch_phase["files"]} == {watch["productReference"]}
watch_widget = next(t for t in targets if t["name"] == "WatchProgressWidget")
watch_extensions = next(objects[p] for p in watch["buildPhases"] if objects[p]["isa"] == "PBXCopyFilesBuildPhase")
assert {objects[b]["fileRef"] for b in watch_extensions["files"]} == {watch_widget["productReference"]}
for path in list((ROOT / "App/Assets.xcassets").rglob("Contents.json")) + list((ROOT / "WatchApp/Assets.xcassets").rglob("Contents.json")):
    for image in json.loads(path.read_text()).get("images", []):
        if "filename" in image:
            assert (path.parent / image["filename"]).is_file(), image["filename"]
ET.parse(ROOT / "Dopagaki.xcodeproj/xcshareddata/xcschemes/Dopagaki.xcscheme")
ET.parse(ROOT / "Dopagaki.xcodeproj/xcshareddata/xcschemes/DopagakiWatch.xcscheme")
print(f"PASS: {len(sources)} Swift source syntax, 7 native targets, plists, references, scheme")
print("iOS type-check/build and device behavior require Xcode; they were not run here.")
