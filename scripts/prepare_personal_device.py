#!/usr/bin/env python3
"""Create a separate Personal Team project, preserving the full app project."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--team", required=True)
    parser.add_argument("--with-widgets", action="store_true", help="Include the widget and App Group; task data stays in the existing app container.")
    parser.add_argument("--app-group", default="group.dev.dopagaki.todo.personal")
    args = parser.parse_args()
    source = ROOT / "Dopagaki.xcodeproj"
    output = args.output.resolve() / "Dopagaki.xcodeproj"
    if output == source.resolve():
        parser.error("Use a separate output directory, not the original project.")
    project = json.loads(subprocess.check_output([
        "plutil", "-convert", "json", "-o", "-", str(source / "project.pbxproj")
    ]))
    objects = project["objects"]
    root = objects[project["rootObject"]]
    app_id = next(uid for uid in root["targets"] if objects[uid]["name"] == "Dopagaki")
    widget_id = next(uid for uid in root["targets"] if objects[uid]["name"] == "ProgressWidget")
    root["targets"] = [app_id, widget_id] if args.with_widgets else [app_id]
    root["projectDirPath"] = ""
    root["attributes"]["TargetAttributes"] = {uid: {"DevelopmentTeam": args.team} for uid in root["targets"]}
    app = objects[app_id]
    app["dependencies"] = [uid for uid in app["dependencies"] if args.with_widgets and objects[uid]["target"] == widget_id]
    for uid in app["buildPhases"]:
        phase = objects[uid]
        if phase["isa"] == "PBXCopyFilesBuildPhase":
            phase["files"] = [bid for bid in phase["files"] if args.with_widgets and objects[bid]["fileRef"] == objects[widget_id]["productReference"]]
    app["buildPhases"] = [uid for uid in app["buildPhases"] if objects[uid]["isa"] != "PBXCopyFilesBuildPhase" or args.with_widgets]
    for obj in objects.values():
        if obj["isa"] == "XCLocalSwiftPackageReference":
            obj["relativePath"] = str(ROOT)
        if obj["isa"] == "PBXFileReference" and obj.get("sourceTree") == "SOURCE_ROOT":
            obj["path"] = str(ROOT / obj["path"])
            obj["sourceTree"] = "<absolute>"
    for uid in objects[app["buildConfigurationList"]]["buildConfigurations"]:
        settings = objects[uid]["buildSettings"]
        settings.update({"DEVELOPMENT_TEAM": args.team,
                         "PRODUCT_BUNDLE_IDENTIFIER": "dev.dopagaki.todo.personal",
                         "DOPA_URL_SCHEME": "dopagaki-personal",
                         "INFOPLIST_FILE": str(ROOT / settings["INFOPLIST_FILE"]),
                         "CODE_SIGN_ENTITLEMENTS": ""})
        settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = (
            settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "") + " DOPA_PERSONAL_TEAM"
            + (" DOPA_WIDGETS" if args.with_widgets else "")
        ).strip()
    output.mkdir(parents=True, exist_ok=True)
    if args.with_widgets:
        entitlement_path = output.parent / "WidgetSharing.entitlements"
        entitlement_path.write_bytes(plistlib.dumps({"com.apple.security.application-groups": [args.app_group]}))
        for target_id in root["targets"]:
            target = objects[target_id]
            for uid in objects[target["buildConfigurationList"]]["buildConfigurations"]:
                settings = objects[uid]["buildSettings"]
                settings.update({"DEVELOPMENT_TEAM": args.team, "DOPA_APP_GROUP": args.app_group,
                                 "DOPA_URL_SCHEME": "dopagaki-personal",
                                 "CODE_SIGN_ENTITLEMENTS": str(entitlement_path)})
                if target_id == widget_id:
                    settings["INFOPLIST_FILE"] = str(ROOT / settings["INFOPLIST_FILE"])
                    settings["PRODUCT_BUNDLE_IDENTIFIER"] = "dev.dopagaki.todo.personal.ProgressWidget"
    (output / "project.pbxproj").write_bytes(plistlib.dumps(project))
    schemes = output / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / "xcshareddata/xcschemes/Dopagaki.xcscheme", schemes)
    print(output)


if __name__ == "__main__":
    main()
