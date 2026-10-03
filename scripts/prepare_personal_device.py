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
    root["targets"] = [app_id]
    root["projectDirPath"] = ""
    root["attributes"]["TargetAttributes"] = {app_id: {"DevelopmentTeam": args.team}}
    app = objects[app_id]
    app["dependencies"] = []
    app["buildPhases"] = [uid for uid in app["buildPhases"]
                          if objects[uid]["isa"] != "PBXCopyFilesBuildPhase"]
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
                         "INFOPLIST_FILE": str(ROOT / settings["INFOPLIST_FILE"]),
                         "CODE_SIGN_ENTITLEMENTS": ""})
        settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = (
            settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "") + " DOPA_PERSONAL_TEAM"
        ).strip()
    output.mkdir(parents=True, exist_ok=True)
    (output / "project.pbxproj").write_bytes(plistlib.dumps(project))
    schemes = output / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / "xcshareddata/xcschemes/Dopagaki.xcscheme", schemes)
    print(output)


if __name__ == "__main__":
    main()
