#!/usr/bin/env python3
"""Grades the geofence replay check. A skipped suite exits 0, so at least one drive must run.

Private corpus, public logs: print only names and outcomes, plus authored scenarios' failures.

Usage: xcrun xcresulttool get test-results tests --path R.xcresult > tests.json
       geofence_replay_gate.py tests.json [scenarios-dir]
Exit: 0 every drive replayed green; 1 something failed; 2 no drive was actually replayed.
"""
import json
import pathlib
import sys

REPLAY_CASE = "replay_givenRecordedDrive_expectRecordedDecisions"


def authored_names(scenarios_dir):
    """`source.kind == authored` scenarios: synthetic data, so their failures are safe to print."""
    names = set()
    if not scenarios_dir:
        return names
    for path in pathlib.Path(scenarios_dir).glob("*.scenario.ndjson"):
        try:
            with open(path) as f:
                header = json.loads(f.readline())
        except (OSError, ValueError):
            continue
        if (header.get("source") or {}).get("kind") == "authored":
            names.add(header.get("name") or path.name.removesuffix(".scenario.ndjson"))
    return names


def cases(node):
    if node.get("nodeType") == "Test Case":
        yield node
        return
    for child in node.get("children", []):
        yield from cases(child)


def outcome(node):
    result = node.get("result", "")
    if result == "Failed":
        return "failed"
    if result == "Skipped":
        return "skipped"
    return "passed"


def main(path, scenarios_dir=None):
    with open(path) as f:
        tree = json.load(f)
    authored = authored_names(scenarios_dir)
    details = {}

    drives, others = [], []
    for case in (c for root in tree.get("testNodes", []) for c in cases(root)):
        name = case.get("name", "?")
        if not name.startswith(REPLAY_CASE):
            others.append((name, outcome(case)))
            continue
        # Only `Arguments` children (one per drive) count; a case with none is reported, never counted.
        arguments = [c for c in case.get("children", []) if c.get("nodeType") == "Arguments"]
        if arguments:
            for a in arguments:
                drive = a.get("name", "?").strip('"')
                drives.append((drive, outcome(a)))
                if outcome(a) == "failed" and drive in authored:
                    details[drive] = [c.get("name", "") for c in a.get("children", [])
                                      if c.get("nodeType") == "Failure Message"]
        else:
            result = outcome(case)
            drives.append((name, "failed" if result == "failed" else "skipped"))

    print("Recorded drives:")
    for name, result in drives:
        print(f"  {result:<8} {name}")
        for message in details.get(name, []):
            print("\n".join("             " + line for line in message.splitlines()))
    ran_others = [name for name, result in others if result != "skipped"]
    failed_others = [name for name, result in others if result == "failed"]
    print(f"Harness tests: {len(ran_others)} run, {len(failed_others)} failed")
    for name in failed_others:
        print(f"  failed   {name}")

    replayed = [d for d in drives if d[1] != "skipped"]
    failed = [d for d in drives if d[1] == "failed"] + failed_others
    if not replayed:
        print("::error::No recorded drive was replayed: the corpus was not found, or holds no "
              "scenarios for this platform. That is a setup failure, not a pass.")
        return 2
    if failed:
        print(f"::error::{len(failed)} geofence replay test(s) failed. A recorded drive's details stay "
              "out of this public log; rerun locally against the pinned corpus to see them.")
        return 1
    print(f"All {len(replayed)} recorded drive(s) replayed green.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None))
