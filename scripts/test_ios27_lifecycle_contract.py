from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).with_name("ios27_lifecycle_contract.py")
SPEC = importlib.util.spec_from_file_location("ios27_lifecycle_contract", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class ContractLockTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "source"
        self.destination = Path(self.temporary.name) / "destination"
        self.root.mkdir()
        self.destination.mkdir()
        self.root = self.root.resolve()
        self.destination = self.destination.resolve()
        self.run_command("git", "init", "-q", str(self.root))
        self.run_command("git", "-C", str(self.root), "config", "user.email", "fixture@example.com")
        self.run_command("git", "-C", str(self.root), "config", "user.name", "Fixture")
        self.run_command(
            "git", "-C", str(self.root), "remote", "add", "origin",
            "https://github.com/customerio/customerio-ios.git",
        )
        self.relative = "docs/contract.txt"
        path = self.root / self.relative
        path.parent.mkdir()
        path.write_text("reviewed contract\n", encoding="utf-8")
        self.run_command("git", "-C", str(self.root), "add", self.relative)
        self.run_command("git", "-C", str(self.root), "commit", "-qm", "contract content")
        self.content_commit = self.output(
            "git", "-C", str(self.root), "rev-parse", "HEAD"
        )
        self.digest = hashlib.sha256(path.read_bytes()).hexdigest()
        self.lock_path = Path(self.temporary.name) / "lock.json"
        self.write_lock(self.content_commit, self.digest)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @staticmethod
    def run_command(*arguments: str) -> None:
        subprocess.run(arguments, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    @staticmethod
    def output(*arguments: str) -> str:
        return subprocess.run(
            arguments, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        ).stdout.strip()

    def write_lock(self, pinned: str, digest: str) -> None:
        self.lock_path.write_text(json.dumps({
            "schema": MODULE.SCHEMA,
            "source_repository": MODULE.SOURCE_REPOSITORY,
            "pinned_content_commit": pinned,
            "relock_note": MODULE.RELOCK_NOTE,
            "algorithm": MODULE.ALGORITHM,
            "files": [{"path": self.relative, "sha256": digest}],
        }), encoding="utf-8")

    def load_lock(self):
        with patch.object(MODULE, "EXPECTED_PATHS", (self.relative,)):
            return MODULE._load_lock(self.lock_path)

    def testSync_fromDescendantRelockHead_copiesPinnedContent(self) -> None:
        (self.root / "relock.txt").write_text("lock metadata\n", encoding="utf-8")
        self.run_command("git", "-C", str(self.root), "add", "relock.txt")
        self.run_command("git", "-C", str(self.root), "commit", "-qm", "relock")

        MODULE.sync(self.root, self.destination, self.load_lock())

        self.assertEqual(
            (self.destination / self.relative).read_text(encoding="utf-8"),
            "reviewed contract\n",
        )

    def testSync_whenPinnedCommitIsNotAncestor_failsClosed(self) -> None:
        unrelated = "f" * 40
        self.write_lock(unrelated, self.digest)
        with self.assertRaisesRegex(
            MODULE.ContractError, "pinned_content_commit must be an ancestor"
        ):
            MODULE.sync(self.root, self.destination, self.load_lock())

    def testSync_whenWorkingContentDrifts_failsClosed(self) -> None:
        (self.root / self.relative).write_text("unreviewed drift\n", encoding="utf-8")
        with self.assertRaisesRegex(MODULE.ContractError, "sha256 mismatch"):
            MODULE.sync(self.root, self.destination, self.load_lock())

    def testSync_whenPinnedBlobDoesNotMatchDigest_failsClosed(self) -> None:
        wrong_digest = hashlib.sha256(b"different\n").hexdigest()
        self.write_lock(self.content_commit, wrong_digest)
        (self.root / self.relative).write_text("different\n", encoding="utf-8")
        with self.assertRaisesRegex(MODULE.ContractError, "pinned content differs"):
            MODULE.sync(self.root, self.destination, self.load_lock())


if __name__ == "__main__":
    unittest.main()
