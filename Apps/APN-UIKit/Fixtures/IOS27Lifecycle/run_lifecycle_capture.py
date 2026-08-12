#!/usr/bin/env python3
"""Run one native Swift lifecycle capture and emit a validated manifest."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import uuid
from typing import Any


TRACE_PREFIX = "CIO-LIFECYCLE-TRACE "
BLUEPRINT_SCHEMA = "cio-lifecycle-capture-blueprint/1"
CONTROL_SCHEMA = "cio-lifecycle-capture-control/1"
UUID_KEYS = ("MANIFEST_ID", "RUN_ID", "STREAM_ID", "PROCESS_INSTANCE_ID")
FIXTURE_ROOT_ENVIRONMENT_KEY = "CIO_LIFECYCLE_FIXTURE_REPO_ROOT"
PATCH_LOCK_PATH = Path(__file__).with_name("source-files.lock.json")
SOURCE_PATCH_PATH = Path(__file__).with_name("ios27-lifecycle-source.patch")
CONTRACT_TOOL_RELATIVE_PATH = Path("scripts/ios27_lifecycle_contract.py")
CONTRACT_VALIDATOR_RELATIVE_PATH = Path("docs/dev-notes/validate_ios27_lifecycle_trace.py")
PATCH_DEPENDENT_SCENARIOS = frozenset({
    "push-tap-warm",
    "push-tap-cold",
    "local-notification-tap-warm",
    "local-notification-tap-cold",
    "token-registration",
    "registration-failure",
})
SUPPORTED_SCENARIOS = (
    "icon-cold-launch",
    "push-tap-warm",
    "push-tap-cold",
    "local-notification-tap-warm",
    "local-notification-tap-cold",
    "custom-url-warm",
    "custom-url-cold",
    "universal-link-warm",
    "universal-link-cold",
    "live-activity-tap-warm",
    "live-activity-tap-cold",
    "token-registration",
    "registration-failure",
    "app-background-foreground",
)


class CaptureError(RuntimeError):
    pass


def _timestamp() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _load_object(path: Path, description: str) -> dict[str, Any]:
    if path.is_symlink() or not path.is_file():
        raise CaptureError(f"{description} must be a regular non-symlink file: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise CaptureError(f"cannot read {description} {path}: {error}") from error
    if not isinstance(value, dict):
        raise CaptureError(f"{description} must contain one JSON object")
    return value


def _patched_source_entries() -> tuple[dict[str, str], ...]:
    lock = _load_object(PATCH_LOCK_PATH, "source patch lock")
    if set(lock) != {"schema", "source_commit", "algorithm", "patch_sha256", "files"}:
        raise CaptureError("source patch lock has an unexpected shape")
    if lock.get("schema") != "cio-lifecycle-source-patch-lock/3" or lock.get("algorithm") != "sha256":
        raise CaptureError("source patch lock provenance is invalid")
    patch_digest = lock.get("patch_sha256")
    if not isinstance(patch_digest, str) or not re.fullmatch(r"[0-9a-f]{64}", patch_digest):
        raise CaptureError("source patch lock digest is invalid")
    if SOURCE_PATCH_PATH.is_symlink() or not SOURCE_PATCH_PATH.is_file():
        raise CaptureError("repository-owned source patch is missing or a symlink")
    if hashlib.sha256(SOURCE_PATCH_PATH.read_bytes()).hexdigest() != patch_digest:
        raise CaptureError("repository-owned source patch digest mismatch")
    files = lock.get("files")
    if not isinstance(files, list) or len(files) != 4:
        raise CaptureError("source patch lock must contain exactly four files")
    entries: list[dict[str, str]] = []
    paths: set[str] = set()
    for entry in files:
        if not isinstance(entry, dict) or set(entry) != {"path", "sha256", "post_sha256"}:
            raise CaptureError("source patch lock file entry has an unexpected shape")
        path = entry.get("path")
        if not isinstance(path, str) or not path.startswith("Sources/"):
            raise CaptureError("source patch lock contains an unsafe path")
        if any(not isinstance(entry.get(key), str) or not re.fullmatch(r"[0-9a-f]{64}", entry[key]) for key in ("sha256", "post_sha256")):
            raise CaptureError("source patch lock contains an invalid file digest")
        paths.add(path)
        entries.append(entry)
    if len(paths) != 4:
        raise CaptureError("source patch lock contains duplicate paths")
    return tuple(entries)


def _patched_source_paths() -> frozenset[str]:
    return frozenset(entry["path"] for entry in _patched_source_entries())


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
        raise CaptureError(f"command failed: {' '.join(arguments)}\n{output}") from error
    return completed.stdout.strip()


def _run_scenario(arguments: list[str], *, cwd: Path, environment: dict[str, str]) -> None:
    try:
        completed = subprocess.run(
            arguments,
            cwd=cwd,
            env=environment,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError as error:
        raise CaptureError("scenario command could not be started") from error
    if completed.returncode != 0:
        raise CaptureError(f"scenario command exited {completed.returncode}")


def _git(root: Path, *arguments: str) -> str:
    return _run(["git", "-C", str(root), *arguments], cwd=root)


def _snapshot(root: Path) -> tuple[bool, dict[str, str] | None]:
    status = _git(root, "status", "--porcelain=v1", "--untracked-files=all")
    if not status:
        return False, None

    listed = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        check=True,
        stdout=subprocess.PIPE,
    ).stdout.split(b"\0")
    tree = hashlib.sha256()
    untracked_output = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z", "--others", "--exclude-standard"],
        check=True,
        stdout=subprocess.PIPE,
    ).stdout
    untracked = {
        value.decode("utf-8") for value in untracked_output.split(b"\0") if value
    }
    untracked_digest = hashlib.sha256()
    for raw_relative in sorted(value for value in listed if value):
        relative = raw_relative.decode("utf-8")
        path = root / relative
        if path.is_symlink() or not path.is_file():
            raise CaptureError(f"source snapshot contains a non-regular path: {relative}")
        content_digest = hashlib.sha256(path.read_bytes()).hexdigest()
        entry = f"{content_digest}  {relative}\n".encode()
        tree.update(entry)
        if relative in untracked:
            untracked_digest.update(entry)

    diff = subprocess.run(
        ["git", "-C", str(root), "diff", "--binary", "--no-ext-diff", "HEAD", "--"],
        check=True,
        stdout=subprocess.PIPE,
    ).stdout
    combined_diff = hashlib.sha256(diff + b"\0UNTRACKED\0" + untracked_digest.digest()).hexdigest()
    return True, {
        "algorithm": "sha256",
        "tree_hash": tree.hexdigest(),
        "diff_hash": combined_diff,
        "ignored_build_inputs_excluded": True,
    }


def _require_disposable_checkout(root: Path, scenario: str) -> None:
    fixture_root_value = os.environ.get(FIXTURE_ROOT_ENVIRONMENT_KEY)
    if fixture_root_value is not None:
        fixture_root = Path(fixture_root_value)
        if fixture_root.is_symlink() or fixture_root.resolve() != root:
            raise CaptureError(
                f"{FIXTURE_ROOT_ENVIRONMENT_KEY} must resolve to source-root"
            )
    if scenario not in PATCH_DEPENDENT_SCENARIOS:
        return
    if fixture_root_value is None:
        raise CaptureError(
            "patch-dependent push/token capture must run inside run_disposable_source_patch.py"
        )
    changed_paths = set(
        _git(root, "diff", "--name-only", "--no-renames", "HEAD", "--").splitlines()
    )
    entries = _patched_source_entries()
    if not {entry["path"] for entry in entries}.issubset(changed_paths):
        raise CaptureError(
            "disposable checkout does not contain every required production source patch"
        )
    for entry in entries:
        path = root / entry["path"]
        if path.is_symlink() or not path.is_file():
            raise CaptureError(f"patched production source is missing or unsafe: {entry['path']}")
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry["post_sha256"]:
            raise CaptureError(f"patched production source digest mismatch: {entry['path']}")


def _toolchain(root: Path) -> dict[str, str | None]:
    xcode_lines = _run(["xcodebuild", "-version"], cwd=root).splitlines()
    if len(xcode_lines) != 2 or not xcode_lines[0].startswith("Xcode ") or not xcode_lines[1].startswith("Build version "):
        raise CaptureError("unexpected xcodebuild -version output")
    swift_output = _run(["xcrun", "swift", "--version"], cwd=root)
    swift_match = re.search(r"Swift version ([0-9A-Za-z.+_-]+)", swift_output)
    if swift_match is None:
        raise CaptureError("unexpected swift --version output")
    return {
        "xcode_version": xcode_lines[0].removeprefix("Xcode "),
        "xcode_build": xcode_lines[1].removeprefix("Build version "),
        "swift_version": swift_match.group(1),
        "flutter_version": None,
        "dart_version": None,
        "node_version": None,
        "expo_cli_version": None,
    }


def _sdk(root: Path) -> dict[str, str]:
    return {
        "platform": "ios",
        "name": "iphonesimulator",
        "version": _run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], cwd=root),
        "build": _run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-build-version"], cwd=root),
    }


def _simulator(root: Path, identifier: str) -> dict[str, str]:
    devices = json.loads(_run(["xcrun", "simctl", "list", "-j", "devices", "available"], cwd=root))
    runtimes = json.loads(_run(["xcrun", "simctl", "list", "-j", "runtimes"], cwd=root))["runtimes"]
    runtime_by_identifier = {runtime["identifier"]: runtime for runtime in runtimes}
    for runtime_identifier, candidates in devices["devices"].items():
        for device in candidates:
            if device.get("udid") != identifier:
                continue
            if device.get("state") != "Booted":
                raise CaptureError("the selected simulator must already be Booted")
            runtime = runtime_by_identifier.get(runtime_identifier)
            if runtime is None or not runtime.get("isAvailable"):
                raise CaptureError("the selected simulator runtime is unavailable")
            architecture = platform.machine()
            if architecture not in {"arm64", "x86_64"}:
                raise CaptureError(f"unsupported simulator architecture: {architecture}")
            return {
                "kind": "simulator",
                "model": device["name"],
                "architecture": architecture,
                "os_name": "iPadOS" if device["name"].startswith("iPad") else "iOS",
                "os_version": runtime["version"],
                "os_build": runtime["buildversion"],
            }
    raise CaptureError("selected simulator was not found in available devices")


def _blueprint(path: Path) -> dict[str, Any]:
    value = _load_object(path, "capture blueprint")
    if set(value) != {"schema", "build", "frameworks", "aggregate_assertions"}:
        raise CaptureError("capture blueprint has an unexpected shape")
    if value["schema"] != BLUEPRINT_SCHEMA:
        raise CaptureError("capture blueprint schema mismatch")
    if not isinstance(value["build"], dict) or not isinstance(value["frameworks"], list):
        raise CaptureError("capture blueprint build/frameworks have invalid types")
    if value["build"].get("product_kind") != "application":
        raise CaptureError("capture blueprint must describe an application product")
    if not isinstance(value["aggregate_assertions"], list):
        raise CaptureError("capture blueprint aggregate_assertions must be an array")
    return value


def _frameworks(declarations: list[Any], commit: str, sdk_version: str) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    for declaration in declarations:
        if not isinstance(declaration, dict):
            raise CaptureError("capture blueprint framework entries must be objects")
        framework = dict(declaration)
        if framework.get("name") in {"customerio-ios", "customerio-messaging-push"}:
            framework["commit_sha"] = commit
        if framework.get("name") == "apple-usernotifications":
            framework["version"] = sdk_version
        normalized.append(framework)
    return normalized


def _records(path: Path, expected: dict[str, str]) -> list[dict[str, Any]]:
    if path.is_symlink() or not path.is_file():
        raise CaptureError("the recorder did not produce a regular trace file")
    records: list[dict[str, Any]] = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.startswith(TRACE_PREFIX):
            raise CaptureError(f"trace line {number} does not have the canonical prefix")
        try:
            record = json.loads(line.removeprefix(TRACE_PREFIX))
        except json.JSONDecodeError as error:
            raise CaptureError(f"trace line {number} is invalid JSON") from error
        if not isinstance(record, dict):
            raise CaptureError(f"trace line {number} is not an object")
        for key, expected_value in expected.items():
            if record.get(key) != expected_value:
                raise CaptureError(f"trace line {number} has mismatched {key}")
        records.append(record)
    if not records:
        raise CaptureError("trace file is empty")
    return records


def _validate_capture(
    validator_python: str,
    validator: Path,
    manifest_path: Path,
    trace_path: Path,
    root: Path,
) -> None:
    output = _run(
        [validator_python, str(validator), str(manifest_path), str(trace_path)],
        cwd=root,
        environment=os.environ.copy(),
    )
    expected = f"VALID: {manifest_path} with 1 stream(s)"
    if output != expected:
        raise CaptureError("canonical lifecycle validator returned unexpected output")


def _verify_contract(validator_python: str, root: Path) -> Path:
    tool = root / CONTRACT_TOOL_RELATIVE_PATH
    validator = root / CONTRACT_VALIDATOR_RELATIVE_PATH
    if tool.is_symlink() or not tool.is_file():
        raise CaptureError("canonical contract verification tool is missing or a symlink")
    output = _run(
        [validator_python, str(tool), "verify", "--root", str(root)],
        cwd=root,
    )
    if output != f"verified 18 canonical files under {root}":
        raise CaptureError("canonical contract verification returned unexpected output")
    if validator.is_symlink() or not validator.is_file():
        raise CaptureError("canonical lifecycle validator is missing or a symlink")
    return validator


def _control(path: Path, scenario: str, provider: str) -> dict[str, Any]:
    value = _load_object(path, "harness control receipt")
    if set(value) != {"schema", "stimulus", "provider_provenance"} or value["schema"] != CONTROL_SCHEMA:
        raise CaptureError("harness control receipt has an unexpected shape")
    stimulus = value.get("stimulus")
    provenance = value.get("provider_provenance")
    if not isinstance(stimulus, dict) or stimulus.get("scenario") != scenario:
        raise CaptureError("control receipt stimulus does not match the requested scenario")
    if not isinstance(provenance, dict) or provenance.get("provider") != provider:
        raise CaptureError("control receipt provider does not match the requested provider")
    if stimulus.get("initiated_at") is None:
        raise CaptureError("control receipt must contain the observed stimulus time")
    if provenance.get("receipt_result") not in {"not-applicable", "unknown"} and provenance.get("receipt_recorded_at") is None:
        raise CaptureError("provider receipt time is required for an observed provider result")
    return value


def capture(arguments: argparse.Namespace) -> None:
    source_root = arguments.source_root
    root = source_root.resolve()
    output = arguments.output_dir.resolve()
    if source_root.is_symlink() or not root.is_dir() or _git(root, "rev-parse", "--show-toplevel") != str(root):
        raise CaptureError("source-root must be a non-symlink Git checkout root")
    _require_disposable_checkout(root, arguments.scenario)
    if output.exists() or output == root or root in output.parents:
        raise CaptureError("output-dir must not exist and must be outside source-root")
    output.mkdir(parents=True)

    blueprint = _blueprint(arguments.blueprint)
    dirty, source_snapshot = _snapshot(root)
    commit = _git(root, "rev-parse", "HEAD")
    toolchain = _toolchain(root)
    sdk = _sdk(root)
    target = _simulator(root, arguments.simulator_id)
    manifest_id, run_id, stream_id, process_instance_id = (str(uuid.uuid4()) for _ in UUID_KEYS)
    ids = dict(zip(UUID_KEYS, (manifest_id, run_id, stream_id, process_instance_id)))
    trace_path = output / "swift.ndjson"
    receipt_path = output / "swift.ndjson.receipt.json"
    control_path = output / "control.json"
    manifest_path = output / "manifest.json"
    context_path = output / "context.json"

    context = {
        "schema": "cio-lifecycle-capture-context/1",
        "manifest_id": manifest_id,
        "run_id": run_id,
        "stream_id": stream_id,
        "process_instance_id": process_instance_id,
        "scenario": arguments.scenario,
        "evidence_level": arguments.evidence_level,
        "integration": arguments.integration,
        "runtime": "swift",
        "provider": arguments.provider,
        "output_path": str(trace_path),
        "control_path": str(control_path),
    }
    context_path.write_text(json.dumps(context, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    environment = os.environ.copy()
    injected = {
        **{f"CIO_LIFECYCLE_{key}": value for key, value in ids.items()},
        "CIO_LIFECYCLE_SCENARIO": arguments.scenario,
        "CIO_LIFECYCLE_EVIDENCE_LEVEL": arguments.evidence_level,
        "CIO_LIFECYCLE_INTEGRATION": arguments.integration,
        "CIO_LIFECYCLE_RUNTIME": "swift",
        "CIO_LIFECYCLE_PROVIDER": arguments.provider,
        "CIO_LIFECYCLE_OUTPUT_PATH": str(trace_path),
        "CIO_LIFECYCLE_CONTROL_PATH": str(control_path),
    }
    environment.update(injected)
    environment.update({f"SIMCTL_CHILD_{key}": value for key, value in injected.items()})

    started_at = _timestamp()
    _run_scenario(arguments.command, cwd=root, environment=environment)
    ended_at = _timestamp()

    control = _control(control_path, arguments.scenario, arguments.provider)
    receipt = _load_object(receipt_path, "post-drain stream receipt")
    if receipt.get("dropped_records_total") != 0 or receipt.get("alias_overflow") is not False:
        raise CaptureError("capture receipt reports drops or alias overflow")
    expected = {
        "manifest_id": manifest_id,
        "run_id": run_id,
        "stream_id": stream_id,
        "scenario": arguments.scenario,
        "evidence_level": arguments.evidence_level,
        "integration": arguments.integration,
        "runtime": "swift",
        "provider": arguments.provider,
    }
    records = _records(trace_path, expected)
    process_ids = {record.get("process_id") for record in records}
    if len(process_ids) != 1:
        raise CaptureError("trace records disagree on process_id")
    process_id = process_ids.pop()
    if process_id is not None and (not isinstance(process_id, int) or process_id < 1):
        raise CaptureError("trace process_id must be null or a positive integer")
    if arguments.evidence_level in {"L2", "L3"} and not any(
        record.get("kind") != "trace-control" for record in records
    ):
        raise CaptureError("acceptance capture contains no non-control runtime observation")

    manifest = {
        "schema": "cio-lifecycle-capture-manifest/1",
        "manifest_id": manifest_id,
        "run_id": run_id,
        "run_started_at": started_at,
        "run_ended_at": ended_at,
        "created_at": _timestamp(),
        "evidence_level": arguments.evidence_level,
        "scenario": arguments.scenario,
        "repositories": [{
            "name": "customerio-ios",
            "commit_sha": commit,
            "dirty": dirty,
            "source_snapshot": source_snapshot,
        }],
        "toolchain": toolchain,
        "sdk": sdk,
        "build": blueprint["build"],
        "target": target,
        "frameworks": _frameworks(blueprint["frameworks"], commit, sdk["version"]),
        "provider_provenance": control["provider_provenance"],
        "stimulus": control["stimulus"],
        "streams": [{
            "stream_id": stream_id,
            "integration": arguments.integration,
            "runtime": "swift",
            "provider": arguments.provider,
            "process_id": process_id,
            "process_instance_id": process_instance_id,
            "receipt": receipt,
        }],
        "aggregate_assertions": blueprint["aggregate_assertions"],
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    validator = _verify_contract(arguments.validator_python, root)
    _validate_capture(
        arguments.validator_python,
        validator,
        manifest_path,
        trace_path,
        root,
    )
    print(f"validated lifecycle capture: {manifest_path}")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--blueprint", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--simulator-id", required=True)
    parser.add_argument("--scenario", choices=SUPPORTED_SCENARIOS, required=True)
    parser.add_argument("--evidence-level", choices=("diagnostic", "L2"), required=True)
    parser.add_argument("--integration", choices=("native-ios",), default="native-ios")
    parser.add_argument("--provider", choices=("apn", "fcm", "local", "none", "unknown"), required=True)
    parser.add_argument("--validator-python", default=sys.executable)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    return parser


def _scenario_command(arguments: list[str]) -> list[str]:
    if arguments[:1] != ["--"] or len(arguments) == 1:
        raise CaptureError("command is required after an explicit -- separator")
    return arguments[1:]


def main() -> int:
    arguments = _parser().parse_args()
    try:
        arguments.command = _scenario_command(arguments.command)
        capture(arguments)
    except (CaptureError, OSError, UnicodeError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
