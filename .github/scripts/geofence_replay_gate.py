#!/usr/bin/env python3
"""Decides the geofence corpus replay check from the xcresult test tree.

xcodebuild's exit code is not enough: with no corpus the replay test is *skipped* by its
`.enabled(if: Scenarios.isAvailable)` trait, and a skipped suite exits 0 — a pass that replayed
nothing. So this requires at least one recorded drive to have actually run.

The corpus is private, and this repo's Actions logs are public. Failure messages carry fence names
and coordinates, so this prints only test and drive names with their outcome, never a message.

Usage: xcrun xcresulttool get test-results tests --path R.xcresult > tests.json
       geofence_replay_gate.py tests.json
Exit: 0 every drive replayed green; 1 something failed; 2 no drive was actually replayed.
"""
import json
import sys

REPLAY_CASE = "replay_givenRecordedDrive_expectRecordedDecisions"


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


def main(path):
    with open(path) as f:
        tree = json.load(f)

    drives, others = [], []
    for case in (c for root in tree.get("testNodes", []) for c in cases(root)):
        name = case.get("name", "?")
        if not name.startswith(REPLAY_CASE):
            others.append((name, outcome(case)))
            continue
        # One `Arguments` child per drive, and only those count as replays. A case with none either
        # skipped or had no drives to expand — a corpus holding only the other platform's scenarios
        # "passes" that way having replayed nothing — so it is reported but never counted.
        arguments = [c for c in case.get("children", []) if c.get("nodeType") == "Arguments"]
        if arguments:
            drives += [(a.get("name", "?").strip('"'), outcome(a)) for a in arguments]
        else:
            result = outcome(case)
            drives.append((name, "failed" if result == "failed" else "skipped"))

    print("Recorded drives:")
    for name, result in drives:
        print(f"  {result:<8} {name}")
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
        print(f"::error::{len(failed)} geofence replay test(s) failed. Details stay out of this "
              "public log; rerun locally against the pinned corpus to see them.")
        return 1
    print(f"All {len(replayed)} recorded drive(s) replayed green.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
