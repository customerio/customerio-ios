import datetime as dt
import io
import unittest
from contextlib import redirect_stdout

from scripts.ci.check_xcode27_nightly_runs import (
    Target,
    build_workflow_runs_url,
    classify_latest_run,
    main,
    parse_target,
)


class CheckXcode27NightlyRunsTests(unittest.TestCase):
    now = dt.datetime(2026, 8, 17, 12, 0, tzinfo=dt.timezone.utc)
    target = Target("customerio/customerio-ios", "ios-toolchain-compatibility.yml")

    def payload(self, **overrides):
        run = {
            "created_at": "2026-08-17T05:17:00Z",
            "status": "completed",
            "conclusion": "success",
            "html_url": "https://github.com/customerio/customerio-ios/actions/runs/1",
        }
        run.update(overrides)
        return {"workflow_runs": [run]}

    def classify(self, payload):
        return classify_latest_run(
            self.target,
            payload,
            now=self.now,
            max_age=dt.timedelta(hours=30),
        )

    def test_successful_fresh_run_is_healthy(self):
        healthy, message = self.classify(self.payload())
        self.assertTrue(healthy)
        self.assertIn("succeeded", message)

    def test_missing_run_is_unhealthy(self):
        healthy, message = self.classify({"workflow_runs": []})
        self.assertFalse(healthy)
        self.assertIn("no scheduled run", message)

    def test_stale_run_is_unhealthy(self):
        healthy, message = self.classify(self.payload(created_at="2026-08-15T05:17:00Z"))
        self.assertFalse(healthy)
        self.assertIn("stale", message)

    def test_future_run_is_unhealthy_with_specific_diagnostic(self):
        healthy, message = self.classify(self.payload(created_at="2026-08-18T05:17:00Z"))
        self.assertFalse(healthy)
        self.assertIn("dated in the future", message)

    def test_run_older_than_missing_nightly_threshold_is_stale(self):
        healthy, message = classify_latest_run(
            self.target,
            self.payload(created_at="2026-08-16T09:00:00Z"),
            now=self.now,
            max_age=dt.timedelta(hours=26),
        )
        self.assertFalse(healthy)
        self.assertIn("stale", message)

    def test_same_days_run_is_fresh(self):
        healthy, _ = classify_latest_run(
            self.target,
            self.payload(created_at="2026-08-17T06:00:00Z"),
            now=self.now,
            max_age=dt.timedelta(hours=26),
        )
        self.assertTrue(healthy)

    def test_incomplete_run_is_unhealthy(self):
        healthy, message = self.classify(self.payload(status="in_progress", conclusion=None))
        self.assertFalse(healthy)
        self.assertIn("in_progress", message)

    def test_failed_run_is_unhealthy(self):
        healthy, message = self.classify(self.payload(conclusion="failure"))
        self.assertFalse(healthy)
        self.assertIn("failure", message)

    def test_target_parser_rejects_missing_repository(self):
        with self.assertRaises(Exception):
            parse_target("ios-toolchain-compatibility.yml")

    def test_workflow_runs_url_cannot_be_masked_by_manual_dispatch(self):
        self.assertEqual(
            build_workflow_runs_url(self.target),
            "https://api.github.com/repos/customerio/customerio-ios/actions/workflows/"
            "ios-toolchain-compatibility.yml/runs?event=schedule&per_page=1",
        )

    def test_main_checks_every_target_and_fails_when_one_is_unhealthy(self):
        requested = []

        def fetcher(target, _token):
            requested.append(target.repository)
            if target.repository.endswith("customerio-flutter"):
                return {"workflow_runs": []}
            return self.payload()

        output = io.StringIO()
        with redirect_stdout(output):
            result = main(
                [
                    "--target",
                    "customerio/customerio-ios:ios-toolchain-compatibility.yml",
                    "--target",
                    "customerio/customerio-flutter:ios-toolchain-compatibility.yml",
                    "--target",
                    "customerio/customerio-expo-plugin:ios-toolchain-compatibility.yml",
                    "--max-age-hours",
                    "26",
                ],
                fetcher=fetcher,
                now=self.now,
            )

        self.assertEqual(result, 1)
        self.assertEqual(
            requested,
            [
                "customerio/customerio-ios",
                "customerio/customerio-flutter",
                "customerio/customerio-expo-plugin",
            ],
        )
        self.assertIn("customerio/customerio-flutter: no scheduled run", output.getvalue())

    def test_main_continues_after_a_target_fetch_raises(self):
        requested = []

        def fetcher(target, _token):
            requested.append(target.repository)
            if target.repository.endswith("customerio-ios"):
                raise TimeoutError("request timed out")
            return self.payload()

        with redirect_stdout(io.StringIO()):
            result = main(
                [
                    "--target",
                    "customerio/customerio-ios:ios-toolchain-compatibility.yml",
                    "--target",
                    "customerio/customerio-flutter:ios-toolchain-compatibility.yml",
                    "--max-age-hours",
                    "26",
                ],
                fetcher=fetcher,
                now=self.now,
            )

        self.assertEqual(result, 1)
        self.assertEqual(
            requested,
            ["customerio/customerio-ios", "customerio/customerio-flutter"],
        )


if __name__ == "__main__":
    unittest.main()
