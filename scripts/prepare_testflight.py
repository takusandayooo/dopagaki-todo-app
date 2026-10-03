#!/usr/bin/env python3
"""Prepare an independent four-target TestFlight project without signing or uploading."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROJECT_NAME = "Dopagaki.xcodeproj"
TARGET_NAMES = ("Dopagaki", "ActivityMonitor", "ShieldConfiguration", "ShieldAction")
COPY_PATHS = (
    PROJECT_NAME, "App", "Core", "CoreTests", "Extensions", "Shared",
    "PersistenceTests", "Verification", "scripts", "Distribution", "Package.swift", "README.md", "SPEC.md",
)
IGNORED_NAMES = {".DS_Store", ".git", ".build", ".swiftpm", "__pycache__", "xcuserdata", "DerivedData"}


class PreparationError(ValueError):
    pass


def team_id(value):
    if not re.fullmatch(r"[A-Z0-9]{10}", value):
        raise argparse.ArgumentTypeError("Team ID must contain exactly 10 uppercase letters or digits.")
    return value


def bundle_id(value):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9][A-Za-z0-9-]*)+", value):
        raise argparse.ArgumentTypeError("Use a reverse-DNS identifier without spaces, wildcards, or underscores.")
    return value


def app_group_id(value):
    value = bundle_id(value)
    if not value.startswith("group."):
        raise argparse.ArgumentTypeError("App Group must start with 'group.'.")
    return value


def build_number(value):
    if not re.fullmatch(r"[1-9][0-9]*", value):
        raise argparse.ArgumentTypeError("Build number must be a positive integer.")
    return value


def inside(path, directory):
    return path == directory or directory in path.parents


def destination_path(value):
    original = value.expanduser().absolute()
    if any(p.is_symlink() for p in (original, *original.parents)):
        raise PreparationError("Output and its parent directories must not be symbolic links.")
    output = original.resolve()
    if inside(output, ROOT) or inside(ROOT, output):
        raise PreparationError("Output must be outside the source workspace and must not be its ancestor.")
    check_empty(output)
    return output


def check_empty(output):
    if output.is_symlink():
        raise PreparationError("Refusing a symbolic-link output directory.")
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise PreparationError("Output already exists and is not an empty directory; nothing was overwritten.")


def local_path(directory, value):
    if not isinstance(value, str) or not value or "$" in value:
        raise PreparationError(f"Expected a local relative path, got {value!r}.")
    relative = Path(value)
    if relative.is_absolute() or ".." in relative.parts:
        raise PreparationError(f"Refusing a path outside the copied project: {value!r}.")
    path = directory / relative
    if not inside(path.resolve(), directory.resolve()):
        raise PreparationError(f"Path escapes the copied project: {value!r}.")
    return path


def load_project(directory):
    path = directory / PROJECT_NAME / "project.pbxproj"
    if not path.is_file():
        raise PreparationError("The normal Dopagaki.xcodeproj must already exist; this script never regenerates it.")
    data = subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)], stderr=subprocess.PIPE)
    return json.loads(data)


def target_records(project):
    objects = project["objects"]
    root = objects[project["rootObject"]]
    records = {objects[uid]["name"]: (uid, objects[uid]) for uid in root["targets"]}
    native_ids = {uid for uid, item in objects.items() if item.get("isa") == "PBXNativeTarget"}
    if set(records) != set(TARGET_NAMES) or len(root["targets"]) != 4 or native_ids != set(root["targets"]):
        raise PreparationError("Source must be the normal four-target app, not a Personal Team project.")
    for name, (_, target) in records.items():
        expected_type = "com.apple.product-type.application" if name == "Dopagaki" else "com.apple.product-type.app-extension"
        if target.get("productType") != expected_type:
            raise PreparationError(f"Unexpected product type for {name}.")
    return objects, root, records


def configurations(objects, target):
    values = [objects[uid] for uid in objects[target["buildConfigurationList"]]["buildConfigurations"]]
    if {item["name"] for item in values} != {"Debug", "Release"} or len(values) != 2:
        raise PreparationError("Every target must contain Debug and Release configurations.")
    return values


def ensure_source_is_local(project, directory=ROOT):
    objects, _, records = target_records(project)
    for name, (_, target) in records.items():
        for config in configurations(objects, target):
            settings = config["buildSettings"]
            flags = settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "")
            if "DOPA_PERSONAL_TEAM" in (flags if isinstance(flags, str) else " ".join(flags)):
                raise PreparationError(f"{name} contains the Personal Team compilation condition.")
            for key in ("INFOPLIST_FILE", "CODE_SIGN_ENTITLEMENTS"):
                if not local_path(directory, settings.get(key)).is_file():
                    raise PreparationError(f"Missing {name} {key} file.")
    for item in objects.values():
        if item.get("isa") == "XCLocalSwiftPackageReference" and item.get("relativePath") != ".":
            raise PreparationError("The Core package must be local to the source workspace.")
        if item.get("isa") == "PBXFileReference":
            tree = item.get("sourceTree")
            if tree == "SOURCE_ROOT":
                if not local_path(directory, item["path"]).exists():
                    raise PreparationError(f"Missing project reference: {item['path']}.")
            elif tree != "BUILT_PRODUCTS_DIR":
                raise PreparationError(f"Unsupported external project reference: {item.get('path')}.")


def copy_workspace(staging):
    for name in COPY_PATHS:
        source = ROOT / name
        if not source.exists():
            raise PreparationError(f"Required source path is missing: {name}.")
        if source.is_symlink():
            raise PreparationError(f"Refusing a symbolic-link source: {name}.")
        if source.is_dir():
            for current, dirs, files in os.walk(source, followlinks=False):
                dirs[:] = [entry for entry in dirs if entry not in IGNORED_NAMES]
                for entry in dirs + [entry for entry in files if entry not in IGNORED_NAMES]:
                    if (Path(current) / entry).is_symlink():
                        raise PreparationError(f"Refusing a symbolic link in the source copy: {Path(current) / entry}.")
            shutil.copytree(source, staging / name, ignore=shutil.ignore_patterns(*IGNORED_NAMES))
        else:
            shutil.copy2(source, staging / name)


def configure(project, directory, args):
    objects, root, records = target_records(project)
    attributes = root.setdefault("attributes", {}).setdefault("TargetAttributes", {})
    for name in TARGET_NAMES:
        uid, target = records[name]
        attributes.setdefault(uid, {})["DevelopmentTeam"] = args.team
        for config in configurations(objects, target):
            settings = config["buildSettings"]
            settings.update({
                "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": args.team,
                "PRODUCT_BUNDLE_IDENTIFIER": args.bundle_id if name == "Dopagaki" else f"{args.bundle_id}.{name}",
                "DOPA_APP_GROUP": args.app_group, "CURRENT_PROJECT_VERSION": args.build_number,
                "VERSIONING_SYSTEM": "apple-generic", "GENERATE_INFOPLIST_FILE": "NO",
            })
            # An old manual profile/identity must not override the new automatic-signing team.
            for key in list(settings):
                if key.split("[", 1)[0] in {"PROVISIONING_PROFILE", "PROVISIONING_PROFILE_SPECIFIER", "CODE_SIGN_IDENTITY"}:
                    del settings[key]
            info_path = local_path(directory, settings["INFOPLIST_FILE"])
            info = plistlib.loads(info_path.read_bytes())
            info.update({"CFBundleVersion": args.build_number, "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "DopaAppGroup": "$(DOPA_APP_GROUP)"})
            info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
            entitlement_path = local_path(directory, settings["CODE_SIGN_ENTITLEMENTS"])
            entitlements = plistlib.loads(entitlement_path.read_bytes())
            if entitlements.get("com.apple.developer.family-controls") is not True:
                raise PreparationError(f"{name} is missing its Family Controls entitlement.")
            entitlements["com.apple.security.application-groups"] = ["$(DOPA_APP_GROUP)"]
            entitlement_path.write_bytes(plistlib.dumps(entitlements, sort_keys=False))
    for config in configurations(objects, root):
        config["buildSettings"].update({"DEVELOPMENT_TEAM": args.team, "DOPA_APP_GROUP": args.app_group, "CURRENT_PROJECT_VERSION": args.build_number})
    root["projectDirPath"] = ""
    root["projectRoot"] = ""
    (directory / PROJECT_NAME / "project.pbxproj").write_bytes(plistlib.dumps(project, sort_keys=False))


def resolved(value, settings):
    for name in ("DOPA_APP_GROUP", "PRODUCT_BUNDLE_IDENTIFIER"):
        if isinstance(value, str):
            value = value.replace(f"$({name})", settings[name])
    return value


def validate(project, directory, args):
    ensure_source_is_local(project, directory)
    objects, root, records = target_records(project)
    summaries = []
    for name in TARGET_NAMES:
        uid, target = records[name]
        expected_bundle = args.bundle_id if name == "Dopagaki" else f"{args.bundle_id}.{name}"
        if root["attributes"]["TargetAttributes"][uid]["DevelopmentTeam"] != args.team:
            raise PreparationError(f"{name} has an inconsistent target team.")
        for config in configurations(objects, target):
            settings = config["buildSettings"]
            required = {"CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": args.team, "PRODUCT_BUNDLE_IDENTIFIER": expected_bundle,
                        "DOPA_APP_GROUP": args.app_group, "CURRENT_PROJECT_VERSION": args.build_number, "GENERATE_INFOPLIST_FILE": "NO"}
            if any(settings.get(key) != value for key, value in required.items()):
                raise PreparationError(f"{name}/{config['name']} has inconsistent distribution settings.")
            info = plistlib.loads(local_path(directory, settings["INFOPLIST_FILE"]).read_bytes())
            if info["CFBundleVersion"] != args.build_number or resolved(info["CFBundleIdentifier"], settings) != expected_bundle or resolved(info["DopaAppGroup"], settings) != args.app_group:
                raise PreparationError(f"{name}/{config['name']} has inconsistent Info.plist values.")
            entitlements = plistlib.loads(local_path(directory, settings["CODE_SIGN_ENTITLEMENTS"]).read_bytes())
            groups = [resolved(value, settings) for value in entitlements.get("com.apple.security.application-groups", [])]
            if groups != [args.app_group] or entitlements.get("com.apple.developer.family-controls") is not True:
                raise PreparationError(f"{name}/{config['name']} has inconsistent Screen Time entitlements.")
        summaries.append({"name": name, "bundle_id": expected_bundle, "team": args.team, "app_group": args.app_group,
                          "build_number": args.build_number, "configurations": ["Debug", "Release"], "family_controls": True})
    app = records["Dopagaki"][1]
    extensions = {records[name][0] for name in TARGET_NAMES[1:]}
    dependencies = {objects[uid]["target"] for uid in app["dependencies"]}
    embedded = {objects[objects[uid]["fileRef"]]["path"] for phase in app["buildPhases"]
                if objects[phase]["isa"] == "PBXCopyFilesBuildPhase" for uid in objects[phase]["files"]}
    if dependencies != extensions or embedded != {f"{name}.appex" for name in TARGET_NAMES[1:]}:
        raise PreparationError("All three Screen Time extensions must remain dependencies and embedded products.")
    for item in objects.values():
        if item.get("isa") == "PBXFileReference" and item.get("sourceTree") == "SOURCE_ROOT":
            if not local_path(directory, item["path"]).exists():
                raise PreparationError(f"The independent copy is missing {item['path']}.")
    scheme = ET.parse(directory / PROJECT_NAME / "xcshareddata/xcschemes/Dopagaki.xcscheme")
    if scheme.find("ArchiveAction").get("buildConfiguration") != "Release":
        raise PreparationError("The shared scheme must archive the Release configuration.")
    return summaries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--team", type=team_id, required=True, help="Apple Developer Program Team ID (10 characters).")
    parser.add_argument("--bundle-id", type=bundle_id, default="dev.dopagaki.todo")
    parser.add_argument("--app-group", type=app_group_id, default="group.dev.dopagaki.todo")
    parser.add_argument("--build-number", type=build_number, required=True)
    parser.add_argument("--output", type=Path, required=True, help="An empty/new directory outside the source workspace.")
    args = parser.parse_args()
    staging = None
    try:
        output = destination_path(args.output)
        project = load_project(ROOT)
        ensure_source_is_local(project)
        output.parent.mkdir(parents=True, exist_ok=True)
        staging = Path(tempfile.mkdtemp(prefix=f".{output.name}-preparing-", dir=output.parent))
        copy_workspace(staging)
        configure(project, staging, args)
        summaries = validate(load_project(staging), staging, args)
        summary = {
            "schema_version": 1, "prepared_at": datetime.now(timezone.utc).isoformat(),
            "source_workspace": str(ROOT), "output_workspace": str(output), "project": str(output / PROJECT_NAME),
            "team": args.team, "bundle_id": args.bundle_id, "app_group": args.app_group, "build_number": args.build_number,
            "targets": summaries, "copied_paths": list(COPY_PATHS), "configuration_validated": True,
            "signing_performed": False, "upload_performed": False,
            "family_controls_distribution_approval": "Not checked: Apple approval is required for the app and all three extensions.",
        }
        encoded = json.dumps(summary, ensure_ascii=False, indent=2) + "\n"
        (staging / "testflight-preparation.json").write_text(encoded, encoding="utf-8")
        # Publish only the completed, verified copy. A racing nonempty destination also makes rename fail.
        check_empty(output)
        os.rename(staging, output)
        staging = None
        print(encoded, end="")
    except (PreparationError, OSError, subprocess.CalledProcessError, KeyError, TypeError, json.JSONDecodeError, plistlib.InvalidFileException, ET.ParseError) as error:
        parser.error(f"Preparation failed: {error}")
    finally:
        if staging is not None:
            shutil.rmtree(staging)


if __name__ == "__main__":
    main()
