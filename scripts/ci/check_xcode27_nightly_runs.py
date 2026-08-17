#!/usr/bin/env python3

"""Fail when an expected Xcode 27 scheduled workflow is absent or unhealthy."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass


@dataclass(frozen=True)
class Target:
    repository: str
    workflow: str


def parse_target(raw: str) -> Target:
    try:
        repository, workflow = raw.split(":", 1)
    except ValueError as error:
        raise argparse.ArgumentTypeError("target must be OWNER/REPO:WORKFLOW") from error
    if repository.count("/") != 1 or not workflow:
        raise argparse.ArgumentTypeError("target must be OWNER/REPO:WORKFLOW")
    return Target(repository=repository, workflow=workflow)


def parse_github_time(raw: str) -> dt.datetime:
    return dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))


def classify_latest_run(
    target: Target,
    payload: dict[str, object],
    *,
    now: dt.datetime,
    max_age: dt.timedelta,
) -> tuple[bool, str]:
    runs = payload.get("workflow_runs")
    if not isinstance(runs, list) or not runs:
        return False, f"{target.repository}: no scheduled run exists"

    run = runs[0]
    if not isinstance(run, dict):
        return False, f"{target.repository}: latest run response is malformed"
    created_at = run.get("created_at")
    if not isinstance(created_at, str):
        return False, f"{target.repository}: latest run has no creation time"

    age = now - parse_github_time(created_at)
    url = run.get("html_url", "unknown URL")
    if age < dt.timedelta(0):
        return False, f"{target.repository}: latest scheduled run is dated in the future ({created_at}, {url})"
    if age > max_age:
        return False, f"{target.repository}: latest scheduled run is stale ({created_at}, {url})"
    if run.get("status") != "completed":
        return False, f"{target.repository}: latest scheduled run is {run.get('status')} ({url})"
    if run.get("conclusion") != "success":
        return False, f"{target.repository}: latest scheduled run concluded {run.get('conclusion')} ({url})"
    return True, f"{target.repository}: latest scheduled run succeeded ({url})"


def build_workflow_runs_url(target: Target) -> str:
    workflow = urllib.parse.quote(target.workflow, safe="")
    return (
        f"https://api.github.com/repos/{target.repository}/actions/workflows/"
        f"{workflow}/runs?event=schedule&per_page=1"
    )


def fetch_latest_run(target: Target, token: str | None) -> dict[str, object]:
    url = build_workflow_runs_url(target)
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "customerio-xcode27-nightly-watchdog",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response)
    except (urllib.error.URLError, json.JSONDecodeError) as error:
        raise RuntimeError(f"{target.repository}: GitHub API request failed: {error}") from error


def write_summary(lines: list[str]) -> None:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return
    with open(summary_path, "a", encoding="utf-8") as summary:
        summary.write("## Xcode 27 nightly watchdog\n\n")
        summary.writelines(f"- {line}\n" for line in lines)


def main(
    argv: list[str] | None = None,
    *,
    fetcher=fetch_latest_run,
    now: dt.datetime | None = None,
) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", action="append", required=True, type=parse_target)
    parser.add_argument("--max-age-hours", required=True, type=int)
    arguments = parser.parse_args(argv)
    if arguments.max_age_hours <= 0:
        parser.error("--max-age-hours must be positive")

    now = now or dt.datetime.now(dt.timezone.utc)
    max_age = dt.timedelta(hours=arguments.max_age_hours)
    messages: list[str] = []
    healthy = True
    for target in arguments.target:
        try:
            payload = fetcher(target, os.environ.get("GITHUB_TOKEN"))
            target_healthy, message = classify_latest_run(target, payload, now=now, max_age=max_age)
        except Exception as error:
            target_healthy, message = False, f"{target.repository}: check failed: {error}"
        healthy = healthy and target_healthy
        messages.append(message)
        print(message)

    write_summary(messages)
    return 0 if healthy else 1


if __name__ == "__main__":
    sys.exit(main())
