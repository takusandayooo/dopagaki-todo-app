#!/usr/bin/env python3
"""Check staged repository files; report locations, never secret values.

This is a lightweight pre-upload check, not an exhaustive secret scanner.
Binary media needs a separate visual/metadata review.
"""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN_PARTS = {".build", ".swiftpm", "DerivedData", "xcuserdata", "__pycache__", "Photos"}
FORBIDDEN_SUFFIXES = {".p8", ".p12", ".pfx", ".pem", ".key", ".cer", ".mobileprovision",
                      ".provisionprofile", ".ipa", ".xcuserstate", ".log"}
FORBIDDEN_NAMES = {".DS_Store", "state-v1.json", "screen-time-v1.json", "widget-progress-v1.json", "watch-progress-v1.json", "ExportOptions.plist",
                   "testflight-preparation.json"}
RULES = {
    "private-key": r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----",
    "github-token": r"(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,})",
    "api-token": r"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{24,}",
    "aws-access-key": r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b",
    "personal-home-path": r"/(?:Users|home)/[A-Za-z0-9_.-]+/",
    "device-identifier": r"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b",
    "email-address": r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b",
}


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, stderr=subprocess.PIPE)


def check_file(name, data):
    problems = []
    path = Path(name)
    if (set(path.parts) & FORBIDDEN_PARTS or path.suffix.lower() in FORBIDDEN_SUFFIXES
            or path.name in FORBIDDEN_NAMES or path.name.endswith((".local.json", ".local.xcconfig"))
            or (path.name.startswith(".env") and path.name != ".env.example")
            or any(part.endswith((".xcarchive", ".xcresult", ".xcappdata")) for part in path.parts)):
        problems.append("excluded-local-file")
    try:
        content = data.decode("utf-8")
    except UnicodeDecodeError:
        return problems, False
    for label, pattern in RULES.items():
        for match in re.finditer(pattern, content):
            if label == "email-address" and match.group().endswith("@example.com"):
                continue
            line = content.count("\n", 0, match.start()) + 1
            problems.append(f"{label} (line {line})")
    if path.suffix == ".pbxproj":
        for match in re.finditer(r'DEVELOPMENT_TEAM\s*=\s*"?([A-Z0-9]{10})', content):
            problems.append("configured-development-team")
    return problems, True


def main():
    try:
        files = git("ls-files", "--cached", "-z").decode().split("\0")
    except subprocess.CalledProcessError:
        print("Initialize Git and stage the intended upload files first.", file=sys.stderr)
        return 2
    files = [name for name in files if name]
    if not files:
        print("No staged/tracked files to review.", file=sys.stderr)
        return 2
    failures = []
    binary_count = 0
    modes = git("ls-files", "--stage", "-z").decode().split("\0")
    for entry in modes:
        if entry and not entry.startswith(("100644 ", "100755 ")):
            failures.append((entry.split("\t", 1)[-1], "symlink/submodule/unmerged entry requires review"))
    for name in files:
        problems, is_text = check_file(name, git("show", ":" + name))
        binary_count += not is_text
        failures.extend((name, problem) for problem in problems)
    for name, problem in failures:
        print(f"REVIEW: {name}: {problem}")
    print(f"Checked {len(files)} staged files; {binary_count} binary files need manual media review.")
    print("FAIL: resolve findings before upload." if failures else "PASS: no matches in this staged-file check; manual review still required.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
