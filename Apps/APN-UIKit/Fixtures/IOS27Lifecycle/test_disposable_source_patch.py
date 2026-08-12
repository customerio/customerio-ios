#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


FIXTURE_DIRECTORY = Path(__file__).resolve().parent
REPOSITORY_ROOT = FIXTURE_DIRECTORY.parents[3]
RUNNER = FIXTURE_DIRECTORY / "run_disposable_source_patch.py"
SPEC = importlib.util.spec_from_file_location("run_disposable_source_patch", RUNNER)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class DisposableSourcePatchTests(unittest.TestCase):
    def test_app_cold_seats_and_live_activity_route_use_canonical_guards(self) -> None:
        app_delegate = (REPOSITORY_ROOT / "Apps/APN-UIKit/APN UIKit/AppDelegate.swift").read_text(
            encoding="utf-8"
        )
        scene_delegate = (REPOSITORY_ROOT / "Apps/APN-UIKit/APN UIKit/SceneDelegate.swift").read_text(
            encoding="utf-8"
        )

        launch = app_delegate.split("callback: .applicationDidFinishLaunching", 1)[0]
        self.assertIn("scenario.isColdStart == true", launch)
        connection = scene_delegate.split("callback: .sceneWillConnect", 1)[0]
        self.assertIn("scenario.isColdStart == true", connection)
        self.assertIn("LifecycleTraceEvidence.isCustomerIOLiveActivityRoute(url)", scene_delegate)
        self.assertIn("let shouldTrace = URLContexts.count == 1", scene_delegate)
        self.assertIn("if handle(urlContexts: connectionOptions.urlContexts)", scene_delegate)
        source_patch = (FIXTURE_DIRECTORY / "ios27-lifecycle-source.patch").read_text(encoding="utf-8")
        self.assertIn(
            "if handled, response.actionIdentifier == UNNotificationDefaultActionIdentifier",
            source_patch,
        )

    def test_fixture_applies_in_disposable_checkout_without_absolute_workspace_paths(self) -> None:
        forbidden_workspace_prefix = b"/" + b"Users/"
        for path in FIXTURE_DIRECTORY.iterdir():
            if path.is_file():
                self.assertNotIn(forbidden_workspace_prefix, path.read_bytes(), path.name)
        completed = subprocess.run(
            [
                sys.executable,
                str(RUNNER),
                "--source-root",
                str(REPOSITORY_ROOT),
                "--",
                sys.executable,
                "-c",
                (
                    "import importlib.util, os; from pathlib import Path; "
                    "root = Path(os.environ['CIO_LIFECYCLE_FIXTURE_REPO_ROOT']).resolve(); "
                    "assert root == Path.cwd().resolve(); "
                    "script = root / 'Apps/APN-UIKit/Fixtures/IOS27Lifecycle/"
                    "run_lifecycle_capture.py'; assert script.is_file(); "
                    "spec = importlib.util.spec_from_file_location('capture', script); "
                    "module = importlib.util.module_from_spec(spec); "
                    "spec.loader.exec_module(module); "
                    "module._require_disposable_checkout(root, 'token-registration'); "
                    "assert 'LifecycleTraceHarness.configureFromEnvironment' in "
                    "(root / 'Apps/CocoaPods-FCM/src/AppDelegate.swift').read_text(); "
                    "assert (root / 'Apps/CocoaPods-FCM/test_ios27_lifecycle_instrumentation.py').is_file(); "
                    "dirty, snapshot = module._snapshot(root); "
                    "assert dirty and snapshot is not None; "
                    "assert len(snapshot['tree_hash']) == 64; "
                    "assert len(snapshot['diff_hash']) == 64"
                ),
            ],
            cwd=REPOSITORY_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout)

    def test_patch_path_verifier_rejects_patch_with_unlocked_path(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cio-ios27-fixture-test-") as temporary:
            temporary_directory = Path(temporary)
            mutated_patch = temporary_directory / "mutated.patch"
            mutated_patch.write_bytes(
                (FIXTURE_DIRECTORY / "ios27-lifecycle-source.patch").read_bytes()
                + b"""
diff --git a/Apps/APN-UIKit/.DS_Store b/Apps/APN-UIKit/.DS_Store
new file mode 100644
--- /dev/null
+++ b/Apps/APN-UIKit/.DS_Store
@@ -0,0 +1 @@
+unexpected
"""
            )
            expected_paths = {entry["path"] for entry in MODULE._load_lock()}

            with self.assertRaisesRegex(MODULE.FixtureError, "source patch declares unexpected paths"):
                MODULE._verify_patch_paths(REPOSITORY_ROOT, mutated_patch, expected_paths)

    def test_patch_digest_rejects_same_path_behavior_mutation_before_prepare(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cio-ios27-fixture-test-") as temporary:
            temporary_directory = Path(temporary)
            mutated_patch = temporary_directory / "mutated.patch"
            mutated_patch.write_bytes(
                (FIXTURE_DIRECTORY / "ios27-lifecycle-source.patch").read_bytes().replace(
                    b"notification-center.will-present.entry",
                    b"notification-center.will-present.other",
                    1,
                )
            )
            expected_paths = {entry["path"] for entry in MODULE._load_lock()}
            MODULE._verify_patch_paths(REPOSITORY_ROOT, mutated_patch, expected_paths)

            with self.assertRaisesRegex(MODULE.FixtureError, "source patch digest mismatch"):
                MODULE._load_lock(FIXTURE_DIRECTORY / "source-files.lock.json", mutated_patch)


if __name__ == "__main__":
    unittest.main()
