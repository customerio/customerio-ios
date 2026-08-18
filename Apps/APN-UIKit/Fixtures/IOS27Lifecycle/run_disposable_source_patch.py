#!/usr/bin/env python3
"""Apply lifecycle probes only inside a disposable checkout, then run a command."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tempfile
from typing import Any


SOURCE_COMMIT = "7b981d83759167c47767640ccaf9976b8d0085ba"
FIXTURE_DIRECTORY = Path(__file__).resolve().parent
LOCK_PATH = FIXTURE_DIRECTORY / "source-files.lock.json"
PATCH_PATH = FIXTURE_DIRECTORY / "ios27-lifecycle-source.patch"
OVERLAY_PATHS = (
    "Apps/Common/Source/Diagnostics",
    "Apps/APN-UIKit/Fixtures/IOS27Lifecycle",
    "Apps/APN-UIKit/APN UIKit/AppDelegate.swift",
    "Apps/APN-UIKit/APN UIKit/SceneDelegate.swift",
    "Apps/APN-UIKit/APN UIKit.xcodeproj/project.pbxproj",
    "Apps/APN-UIKit/BuildEnvironment.swift",
    "Apps/APN-UIKit/APN UIKitTests/LifecycleTraceEvidenceTests.swift",
    "Apps/APN-UIKit/APN UIKitTests/LifecycleTraceRecorderTests.swift",
    "Apps/CocoaPods-FCM/src/App.swift",
    "Apps/CocoaPods-FCM/src/AppDelegate.swift",
    "Apps/CocoaPods-FCM/BuildEnvironment.swift",
    "Apps/CocoaPods-FCM/test_ios27_lifecycle_instrumentation.py",
    "docs/dev-notes/ios27-lifecycle-contract-v1.lock.json",
    "scripts/ios27_lifecycle_contract.py",
)


class FixtureError(RuntimeError):
    pass


def _run(arguments: list[str], *, cwd: Path, environment: dict[str, str] | None = None) -> str:
    try:
        completed = subprocess.run(
            arguments,
            cwd=cwd,
            env=environment,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        output = getattr(error, "stdout", "")
        raise FixtureError(f"command failed: {' '.join(arguments)}\n{output}") from error
    return completed.stdout


def _load_lock(
    lock_path: Path = LOCK_PATH,
    patch_path: Path = PATCH_PATH,
) -> list[dict[str, str]]:
    if lock_path.is_symlink() or patch_path.is_symlink():
        raise FixtureError("fixture lock and patch must not be symlinks")
    try:
        payload: Any = json.loads(lock_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise FixtureError(f"cannot read fixture lock: {error}") from error
    if not isinstance(payload, dict) or set(payload) != {
        "schema", "source_commit", "algorithm", "patch_sha256", "files"
    }:
        raise FixtureError("fixture lock has an unexpected shape")
    if payload.get("schema") != "cio-lifecycle-source-patch-lock/3":
        raise FixtureError("fixture lock schema mismatch")
    if payload.get("source_commit") != SOURCE_COMMIT or payload.get("algorithm") != "sha256":
        raise FixtureError("fixture lock provenance mismatch")
    patch_digest = payload.get("patch_sha256")
    if not isinstance(patch_digest, str) or len(patch_digest) != 64 or any(
        character not in "0123456789abcdef" for character in patch_digest
    ):
        raise FixtureError("fixture lock patch digest is invalid")
    if not patch_path.is_file() or _sha256(patch_path) != patch_digest:
        raise FixtureError("repository-owned source patch digest mismatch")
    files = payload.get("files")
    if not isinstance(files, list) or len(files) != 4:
        raise FixtureError("fixture lock must contain exactly four source files")
    paths: list[str] = []
    for item in files:
        if not isinstance(item, dict) or set(item) != {"path", "sha256", "post_sha256"}:
            raise FixtureError("fixture lock entry has an unexpected shape")
        path, digest, post_digest = item.get("path"), item.get("sha256"), item.get("post_sha256")
        if not isinstance(path, str) or not isinstance(digest, str) or not isinstance(post_digest, str):
            raise FixtureError("fixture lock path and digest must be strings")
        pure = PurePosixPath(path)
        if pure.is_absolute() or ".." in pure.parts or not path.startswith("Sources/"):
            raise FixtureError(f"unsafe source path: {path}")
        if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
            raise FixtureError(f"invalid source digest: {path}")
        if len(post_digest) != 64 or any(character not in "0123456789abcdef" for character in post_digest):
            raise FixtureError(f"invalid patched source digest: {path}")
        paths.append(path)
    if len(set(paths)) != len(paths):
        raise FixtureError("fixture lock contains duplicate paths")
    return files


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _verify_sources(root: Path, entries: list[dict[str, str]]) -> None:
    for entry in entries:
        path = root.joinpath(*PurePosixPath(entry["path"]).parts)
        if path.is_symlink() or not path.is_file():
            raise FixtureError(f"source patch target is missing or a symlink: {entry['path']}")
        actual = _sha256(path)
        if actual != entry["sha256"]:
            raise FixtureError(
                f"source patch target drifted: {entry['path']} expected {entry['sha256']}, got {actual}"
            )


def _verify_patched_sources(root: Path, entries: list[dict[str, str]]) -> None:
    for entry in entries:
        path = root.joinpath(*PurePosixPath(entry["path"]).parts)
        if path.is_symlink() or not path.is_file() or _sha256(path) != entry["post_sha256"]:
            raise FixtureError(f"source patch output digest mismatch: {entry['path']}")


def _verify_patch_paths(checkout: Path, patch_path: Path, expected_paths: set[str]) -> None:
    output = _run(["git", "apply", "--numstat", str(patch_path)], cwd=checkout)
    patch_paths: set[str] = set()
    for line in output.splitlines():
        fields = line.split("\t", 2)
        if len(fields) != 3:
            raise FixtureError("source patch has an unexpected numstat shape")
        patch_paths.add(fields[2])
    if patch_paths != expected_paths:
        raise FixtureError(
            f"source patch declares unexpected paths: expected {sorted(expected_paths)}, "
            f"got {sorted(patch_paths)}"
        )


def _overlay(source_root: Path, checkout: Path) -> None:
    for relative in OVERLAY_PATHS:
        source = source_root / relative
        destination = checkout / relative
        if source.is_symlink():
            raise FixtureError(f"overlay path must not be a symlink: {relative}")
        if source.is_dir():
            if destination.exists():
                shutil.rmtree(destination)
            shutil.copytree(source, destination)
        elif source.is_file():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
        else:
            raise FixtureError(f"required overlay is missing: {relative}")


def _prepare(
    source_root: Path,
    checkout: Path,
    entries: list[dict[str, str]],
) -> None:
    head = _run(["git", "rev-parse", "HEAD"], cwd=source_root).strip()
    ancestor = subprocess.run(
        ["git", "merge-base", "--is-ancestor", SOURCE_COMMIT, head],
        cwd=source_root,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if ancestor.returncode != 0:
        raise FixtureError(f"source checkout must descend from canonical commit {SOURCE_COMMIT}")
    _verify_sources(source_root, entries)
    _run(
        ["git", "clone", "--shared", "--no-checkout", "--no-hardlinks", str(source_root), str(checkout)],
        cwd=source_root,
    )
    _run(["git", "checkout", "--detach", head], cwd=checkout)
    _overlay(source_root, checkout)
    _verify_sources(checkout, entries)
    _run(["git", "add", "-A"], cwd=checkout)
    expected_paths = {entry["path"] for entry in entries}
    _verify_patch_paths(checkout, PATCH_PATH, expected_paths)
    _run(["git", "apply", "--check", str(PATCH_PATH)], cwd=checkout)
    _run(["git", "apply", str(PATCH_PATH)], cwd=checkout)
    _verify_patched_sources(checkout, entries)
    changed_paths = set(_run(["git", "diff", "--name-only", "--no-renames", "--"], cwd=checkout).splitlines())
    changed_paths.update(
        _run(["git", "ls-files", "--others", "--exclude-standard"], cwd=checkout).splitlines()
    )
    if changed_paths != expected_paths:
        raise FixtureError(
            f"source patch changed unexpected paths: expected {sorted(expected_paths)}, got {sorted(changed_paths)}"
        )
    for relative in changed_paths:
        if (checkout / relative).is_symlink():
            raise FixtureError(f"source patch produced a symlink: {relative}")
    _verify_sources(source_root, entries)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--source-root", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    source_root = Path(arguments.source_root)
    if source_root.is_symlink() or not source_root.is_dir():
        print("error: source root must be an existing non-symlink directory", file=sys.stderr)
        return 1
    source_root = source_root.resolve()
    if PATCH_PATH.is_symlink() or not PATCH_PATH.is_file():
        print("error: repository-owned patch must be an existing non-symlink file", file=sys.stderr)
        return 1
    command = arguments.command
    if command[:1] != ["--"] or len(command) == 1:
        print("error: provide a command after an explicit -- separator", file=sys.stderr)
        return 1
    command = command[1:]

    try:
        entries = _load_lock()
        try:
            with tempfile.TemporaryDirectory(prefix="cio-ios27-lifecycle-") as temporary:
                checkout = Path(temporary) / "customerio-ios"
                _prepare(source_root, checkout, entries)
                environment = dict(os.environ)
                environment["CIO_LIFECYCLE_FIXTURE_REPO_ROOT"] = str(checkout)
                completed = subprocess.run(command, cwd=checkout, env=environment)
                if completed.returncode != 0:
                    raise FixtureError(f"fixture command exited {completed.returncode}")
        finally:
            _verify_sources(source_root, entries)
    except FixtureError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
