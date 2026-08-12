import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).with_name("run_lifecycle_capture.py")
SPEC = importlib.util.spec_from_file_location("run_lifecycle_capture", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class LifecycleCaptureTests(unittest.TestCase):
    def testCapture_injectsIdentityAndBuildsManifestFromPostDrainReceipt(self) -> None:
        with tempfile.TemporaryDirectory() as source_directory, tempfile.TemporaryDirectory() as output_parent:
            source = Path(source_directory)
            blueprint = source / "blueprint.json"
            output = Path(output_parent) / "capture"
            for relative in (
                MODULE.CONTRACT_TOOL_RELATIVE_PATH,
                MODULE.CONTRACT_VALIDATOR_RELATIVE_PATH,
            ):
                path = source / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("fixture", encoding="utf-8")
            blueprint.write_text(json.dumps({
                "schema": MODULE.BLUEPRINT_SCHEMA,
                "build": {
                    "configuration": "Debug",
                    "scheme": "APN UIKit",
                    "target_name": "APN UIKit",
                    "product_kind": "application",
                    "deployment_target": "15.0",
                },
                "frameworks": [{
                    "name": "customerio-ios",
                    "role": "sdk",
                    "version": "4.7.3",
                    "commit_sha": None,
                }],
                "aggregate_assertions": [],
            }), encoding="utf-8")

            arguments = MODULE._parser().parse_args([
                "--source-root", str(source),
                "--blueprint", str(blueprint),
                "--output-dir", str(output),
                "--simulator-id", "SIMULATOR",
                "--scenario", "token-registration",
                "--evidence-level", "L2",
                "--provider", "apn",
                "--", "scenario-command",
            ])
            arguments.command = ["scenario-command"]

            def fake_git(_root: Path, *items: str) -> str:
                if items == ("rev-parse", "--show-toplevel"):
                    return str(source.resolve())
                if items == ("rev-parse", "HEAD"):
                    return "1" * 40
                if items == ("diff", "--name-only", "--no-renames", "HEAD", "--"):
                    return "\n".join(sorted(MODULE._patched_source_paths()))
                raise AssertionError(items)

            def fake_run(command: list[str], *, cwd: Path, environment=None) -> str:
                resolved_source = source.resolve()
                if command[1:3] == [str(resolved_source / MODULE.CONTRACT_TOOL_RELATIVE_PATH), "verify"]:
                    return f"verified 18 canonical files under {source.resolve()}"
                if len(command) >= 2 and command[1] == str(
                    resolved_source / MODULE.CONTRACT_VALIDATOR_RELATIVE_PATH
                ):
                    return f"VALID: {command[2]} with 1 stream(s)"
                if command == ["scenario-command"]:
                    assert environment is not None
                    for key in MODULE.UUID_KEYS:
                        self.assertEqual(
                            environment[f"CIO_LIFECYCLE_{key}"],
                            environment[f"SIMCTL_CHILD_CIO_LIFECYCLE_{key}"],
                        )
                    trace = Path(environment["CIO_LIFECYCLE_OUTPUT_PATH"])
                    common = {
                        "manifest_id": environment["CIO_LIFECYCLE_MANIFEST_ID"],
                        "run_id": environment["CIO_LIFECYCLE_RUN_ID"],
                        "stream_id": environment["CIO_LIFECYCLE_STREAM_ID"],
                        "scenario": "token-registration",
                        "evidence_level": "L2",
                        "integration": "native-ios",
                        "runtime": "swift",
                        "provider": "apn",
                        "process_id": 42,
                    }
                    trace.write_text("\n".join(
                        MODULE.TRACE_PREFIX + json.dumps({**common, "kind": kind})
                        for kind in ("trace-control", "os-callback", "trace-control")
                    ) + "\n", encoding="utf-8")
                    Path(str(trace) + ".receipt.json").write_text(json.dumps({
                        "drained_at": "2026-08-11T16:00:04Z",
                        "last_assigned_sequence": 3,
                        "last_emitted_sequence": 3,
                        "emitted_records": 3,
                        "dropped_records_total": 0,
                        "buffer_high_watermark": 1,
                        "buffer_capacity": 256,
                        "alias_counts": {"delivery": 0, "request": 1, "scene": 0, "url": 0, "closure": 0},
                        "alias_overflow": False,
                        "alias_overflow_namespaces": [],
                    }), encoding="utf-8")
                    Path(environment["CIO_LIFECYCLE_CONTROL_PATH"]).write_text(json.dumps({
                        "schema": MODULE.CONTROL_SCHEMA,
                        "stimulus": {
                            "scenario": "token-registration",
                            "source": "system-registration",
                            "initiated_at": "2026-08-11T16:00:02Z",
                        },
                        "provider_provenance": {
                            "provider": "apn",
                            "source": "system-registration",
                            "environment": "simulator",
                            "receipt_result": "registered",
                            "receipt_recorded_at": "2026-08-11T16:00:03Z",
                            "provider_sdk": None,
                        },
                    }), encoding="utf-8")
                return ""

            with patch.dict(os.environ, {
                    MODULE.FIXTURE_ROOT_ENVIRONMENT_KEY: str(source.resolve()),
                }), \
                    patch.object(MODULE, "_git", side_effect=fake_git), \
                    patch.object(MODULE, "_snapshot", return_value=(True, {
                        "algorithm": "sha256", "tree_hash": "2" * 64, "diff_hash": "3" * 64,
                    })), \
                    patch.object(MODULE, "_toolchain", return_value={
                        "xcode_version": "26.6", "xcode_build": "17F113", "swift_version": "6.2.4",
                        "flutter_version": None, "dart_version": None, "node_version": None,
                        "expo_cli_version": None,
                    }), \
                    patch.object(MODULE, "_sdk", return_value={
                        "platform": "ios", "name": "iphonesimulator", "version": "26.5", "build": "23F81a",
                    }), \
                    patch.object(MODULE, "_simulator", return_value={
                        "kind": "simulator", "model": "iPhone 17 Pro", "architecture": "arm64",
                        "os_name": "iOS", "os_version": "26.5", "os_build": "23F81a",
                    }), \
                    patch.object(MODULE, "_run", side_effect=fake_run), \
                    patch.object(MODULE, "_run_scenario", side_effect=fake_run):
                MODULE.capture(arguments)

            manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
            self.assertTrue(manifest["repositories"][0]["dirty"])
            self.assertEqual(manifest["repositories"][0]["source_snapshot"]["tree_hash"], "2" * 64)
            self.assertEqual(manifest["frameworks"][0]["commit_sha"], "1" * 40)
            self.assertEqual(manifest["streams"][0]["process_id"], 42)
            self.assertEqual(manifest["streams"][0]["receipt"]["dropped_records_total"], 0)
            self.assertEqual(
                manifest["streams"][0]["process_instance_id"],
                json.loads((output / "context.json").read_text(encoding="utf-8"))["process_instance_id"],
            )

    def testCapture_patchDependentScenarioFromOuterRoot_failsClosedBeforeSnapshot(self) -> None:
        with tempfile.TemporaryDirectory() as source_directory, tempfile.TemporaryDirectory() as output_parent:
            source = Path(source_directory)
            arguments = MODULE._parser().parse_args([
                "--source-root", str(source),
                "--blueprint", str(source / "unused-blueprint.json"),
                "--output-dir", str(Path(output_parent) / "capture"),
                "--simulator-id", "SIMULATOR",
                "--scenario", "token-registration",
                "--evidence-level", "L2",
                "--provider", "apn",
                "--", "scenario-command",
            ])
            arguments.command = ["scenario-command"]

            with patch.dict(os.environ, {}, clear=True), \
                    patch.object(MODULE, "_git", return_value=str(source.resolve())), \
                    patch.object(MODULE, "_snapshot") as snapshot:
                with self.assertRaisesRegex(MODULE.CaptureError, "must run inside"):
                    MODULE.capture(arguments)
            snapshot.assert_not_called()

    def testCapture_fixtureRootThatDoesNotMatchSourceRoot_failsClosed(self) -> None:
        with tempfile.TemporaryDirectory() as source_directory, tempfile.TemporaryDirectory() as other_directory:
            source = Path(source_directory)
            with patch.dict(os.environ, {
                    MODULE.FIXTURE_ROOT_ENVIRONMENT_KEY: other_directory,
                }), \
                    patch.object(MODULE, "_git", return_value=str(source.resolve())):
                with self.assertRaisesRegex(MODULE.CaptureError, "must resolve to source-root"):
                    MODULE._require_disposable_checkout(source.resolve(), "icon-cold-launch")

    def testCanonicalValidator_whenItRejectsOutput_thenCaptureFailsClosed(self) -> None:
        manifest = Path("manifest.json")
        trace = Path("swift.ndjson")
        with patch.object(MODULE, "_run", side_effect=MODULE.CaptureError("validator rejected")) as run:
            with self.assertRaisesRegex(MODULE.CaptureError, "validator rejected"):
                MODULE._validate_capture("validator-python", Path("validator.py"), manifest, trace, Path("."))
        run.assert_called_once()
        self.assertEqual(
            run.call_args.args[0],
            ["validator-python", "validator.py", "manifest.json", "swift.ndjson"],
        )

    def testContractVerification_usesOnlyRepositoryOwnedToolAndValidator(self) -> None:
        root = Path("/source-root")
        tool = root / MODULE.CONTRACT_TOOL_RELATIVE_PATH
        validator = root / MODULE.CONTRACT_VALIDATOR_RELATIVE_PATH

        with patch.object(Path, "is_symlink", return_value=False), \
                patch.object(Path, "is_file", return_value=True), \
                patch.object(
                    MODULE,
                    "_run",
                    return_value=f"verified 18 canonical files under {root}",
                ) as run:
            result = MODULE._verify_contract("validator-python", root)

        self.assertEqual(result, validator)
        run.assert_called_once_with(
            ["validator-python", str(tool), "verify", "--root", str(root)],
            cwd=root,
        )

    def testParser_rejectsAlternateValidator(self) -> None:
        parser = MODULE._parser()
        self.assertNotIn("validator", {action.dest for action in parser._actions})
        with self.assertRaises(SystemExit):
            parser.parse_args([
                "--source-root", ".",
                "--blueprint", "blueprint.json",
                "--output-dir", "capture",
                "--simulator-id", "SIMULATOR",
                "--scenario", "icon-cold-launch",
                "--evidence-level", "diagnostic",
                "--provider", "none",
                "--validator", "noop.py",
                "--", "scenario-command",
            ])

    def testParser_rejectsScenarioWithoutReachableProducerTerminal(self) -> None:
        with self.assertRaises(SystemExit):
            MODULE._parser().parse_args([
                "--source-root", ".",
                "--blueprint", "blueprint.json",
                "--output-dir", "capture",
                "--simulator-id", "SIMULATOR",
                "--scenario", "notification-settings",
                "--evidence-level", "diagnostic",
                "--provider", "none",
                "--", "scenario-command",
            ])

    def testBlueprint_rejectsNonApplicationProduct(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "blueprint.json"
            path.write_text(json.dumps({
                "schema": MODULE.BLUEPRINT_SCHEMA,
                "build": {"product_kind": "unit-test"},
                "frameworks": [],
                "aggregate_assertions": [],
            }), encoding="utf-8")
            with self.assertRaisesRegex(MODULE.CaptureError, "application product"):
                MODULE._blueprint(path)

    def testScenarioCommand_whenItPrintsSecretsAndFails_thenOutputIsSuppressed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            command = [
                sys.executable,
                "-c",
                (
                    "import sys; print('SECRET-URL'); "
                    "print('SECRET-TOKEN', file=sys.stderr); raise SystemExit(7)"
                ),
            ]
            with self.assertRaisesRegex(MODULE.CaptureError, "scenario command exited 7") as raised:
                MODULE._run_scenario(command, cwd=Path(directory), environment=os.environ.copy())
            self.assertNotIn("SECRET", str(raised.exception))

    def testRecorder_unrestrictedDrainIsNotPublicProducerAPI(self) -> None:
        diagnostics = SCRIPT.parents[3] / "Common" / "Source" / "Diagnostics"
        recorder = (diagnostics / "LifecycleTraceRecorder.swift").read_text(encoding="utf-8")
        probe = (diagnostics / "LifecycleTraceProbe.swift").read_text(encoding="utf-8")

        self.assertNotIn("public func endScenarioAndDrain", recorder)
        self.assertNotIn("public static func endScenarioAndDrain", probe)

    def testFrameworks_fillOnlyObservedNativeProvenance(self) -> None:
        declarations = [
            {"name": "customerio-ios", "role": "sdk", "version": "4.7.3", "commit_sha": None},
            {
                "name": "apple-usernotifications",
                "role": "platform-framework",
                "version": None,
                "commit_sha": None,
            },
        ]

        result = MODULE._frameworks(declarations, "1" * 40, "26.5")

        self.assertEqual(result[0]["commit_sha"], "1" * 40)
        self.assertEqual(result[1]["version"], "26.5")
        self.assertIsNone(declarations[0]["commit_sha"])

    def testSimulator_whenDeviceIsIPadOnIOSRuntime_thenLabelsIPadOS(self) -> None:
        devices = {
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [{
                    "name": "iPad Pro 13-inch (M5)",
                    "udid": "IPAD-SIMULATOR",
                    "state": "Booted",
                }],
            },
        }
        runtimes = {
            "runtimes": [{
                "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
                "name": "iOS 26.5",
                "version": "26.5",
                "buildversion": "23F81a",
                "isAvailable": True,
            }],
        }

        with patch.object(MODULE, "_run", side_effect=[json.dumps(devices), json.dumps(runtimes)]), \
                patch.object(MODULE.platform, "machine", return_value="arm64"):
            result = MODULE._simulator(Path("."), "IPAD-SIMULATOR")

        self.assertEqual(result["model"], "iPad Pro 13-inch (M5)")
        self.assertEqual(result["os_name"], "iPadOS")

    def testRecords_rejectMismatchedHarnessIdentity(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "swift.ndjson"
            path.write_text(
                MODULE.TRACE_PREFIX + json.dumps({"run_id": "wrong"}) + "\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(MODULE.CaptureError, "mismatched run_id"):
                MODULE._records(path, {"run_id": "expected"})

    def testControl_requiresObservedProviderReceiptTime(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "control.json"
            path.write_text(
                json.dumps({
                    "schema": MODULE.CONTROL_SCHEMA,
                    "stimulus": {
                        "scenario": "token-registration",
                        "source": "system-registration",
                        "initiated_at": "2026-08-11T16:00:02Z",
                    },
                    "provider_provenance": {
                        "provider": "apn",
                        "source": "system-registration",
                        "environment": "simulator",
                        "receipt_result": "registered",
                        "receipt_recorded_at": None,
                        "provider_sdk": None,
                    },
                }),
                encoding="utf-8",
            )

            with self.assertRaisesRegex(MODULE.CaptureError, "provider receipt time"):
                MODULE._control(path, "token-registration", "apn")


if __name__ == "__main__":
    unittest.main()
