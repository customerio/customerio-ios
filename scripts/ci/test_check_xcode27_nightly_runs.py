import datetime as dt
import io
import json
import os
import tempfile
import unittest
import urllib.error
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

from scripts.ci.check_xcode27_nightly_runs import (
    Target,
    build_workflow_runs_url,
    classify_latest_run,
    fetch_latest_run,
    main,
    parse_target,
    run_cli,
)


class CheckXcode27NightlyRunsTests(unittest.TestCase):
    now = dt.datetime(2026, 8, 17, 12, 0, tzinfo=dt.timezone.utc)
    target = Target("customerio/customerio-ios", "ios-toolchain-compatibility.yml")

    def setUp(self):
        super().setUp()
        environment = mock.patch.dict(os.environ, {"GITHUB_STEP_SUMMARY": ""})
        environment.start()
        self.addCleanup(environment.stop)

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

    def test_missing_runs_field_is_a_monitoring_error(self):
        with self.assertRaisesRegex(RuntimeError, "workflow runs response is malformed"):
            self.classify({})

    def test_non_list_runs_field_is_a_monitoring_error(self):
        with self.assertRaisesRegex(RuntimeError, "workflow runs response is malformed"):
            self.classify({"workflow_runs": None})

    def test_malformed_run_is_a_monitoring_error(self):
        with self.assertRaisesRegex(RuntimeError, "response is malformed"):
            self.classify({"workflow_runs": ["not a run"]})

    def test_run_without_creation_time_is_a_monitoring_error(self):
        payload = self.payload()
        del payload["workflow_runs"][0]["created_at"]
        with self.assertRaisesRegex(RuntimeError, "no creation time"):
            self.classify(payload)

    def test_invalid_creation_time_is_a_monitoring_error(self):
        with self.assertRaisesRegex(RuntimeError, "invalid creation time"):
            self.classify(self.payload(created_at="not-a-date"))

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

    def test_cancelled_run_is_unhealthy(self):
        healthy, message = self.classify(self.payload(conclusion="cancelled"))
        self.assertFalse(healthy)
        self.assertIn("cancelled", message)

    def test_timed_out_run_is_unhealthy(self):
        healthy, message = self.classify(self.payload(conclusion="timed_out"))
        self.assertFalse(healthy)
        self.assertIn("timed_out", message)

    def test_queued_run_is_unhealthy(self):
        healthy, message = self.classify(self.payload(status="queued", conclusion=None))
        self.assertFalse(healthy)
        self.assertIn("queued", message)

    def test_target_parser_rejects_missing_repository(self):
        with self.assertRaises(Exception):
            parse_target("ios-toolchain-compatibility.yml")

    def test_target_parser_rejects_empty_owner_or_repository(self):
        for target in (
            "/customerio-ios:ios-toolchain-compatibility.yml",
            "customerio/:ios-toolchain-compatibility.yml",
        ):
            with self.subTest(target=target), self.assertRaises(Exception):
                parse_target(target)

    def test_fetch_retries_a_transient_api_failure(self):
        response = io.StringIO(json.dumps(self.payload()))
        opener = mock.Mock(
            side_effect=[urllib.error.URLError("temporary"), response]
        )
        sleeper = mock.Mock()

        result = fetch_latest_run(
            self.target,
            "token",
            opener=opener,
            sleeper=sleeper,
        )

        self.assertEqual(result, self.payload())
        self.assertEqual(opener.call_count, 2)
        sleeper.assert_called_once_with(1)
        request = opener.call_args_list[0].args[0]
        self.assertEqual(request.get_header("Authorization"), "Bearer token")

    def test_fetch_fails_after_exhausting_retries(self):
        opener = mock.Mock(side_effect=urllib.error.URLError("unavailable"))
        sleeper = mock.Mock()

        with self.assertRaisesRegex(RuntimeError, "failed after 3 attempts"):
            fetch_latest_run(
                self.target,
                "token",
                opener=opener,
                sleeper=sleeper,
            )

        self.assertEqual(opener.call_count, 3)
        self.assertEqual(sleeper.call_args_list, [mock.call(1), mock.call(2)])

    def test_fetch_reports_rate_limit_without_retrying(self):
        error = urllib.error.HTTPError(
            url="https://api.github.com/example",
            code=403,
            msg="rate limited",
            hdrs={"X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "12345"},
            fp=None,
        )
        self.addCleanup(error.close)
        opener = mock.Mock(side_effect=error)
        sleeper = mock.Mock()

        with self.assertRaisesRegex(RuntimeError, "rate limited this runner.*reset=12345"):
            fetch_latest_run(
                self.target,
                None,
                opener=opener,
                sleeper=sleeper,
            )

        opener.assert_called_once()
        sleeper.assert_not_called()

    def test_fetch_reports_missing_workflow_without_retrying(self):
        error = urllib.error.HTTPError(
            url="https://api.github.com/example",
            code=404,
            msg="not found",
            hdrs=None,
            fp=None,
        )
        self.addCleanup(error.close)
        opener = mock.Mock(side_effect=error)
        sleeper = mock.Mock()

        with self.assertRaisesRegex(RuntimeError, "monitored workflow was not found"):
            fetch_latest_run(
                self.target,
                None,
                opener=opener,
                sleeper=sleeper,
            )

        opener.assert_called_once()
        sleeper.assert_not_called()

    def test_fetch_omits_authorization_for_public_api_read(self):
        response = io.StringIO(json.dumps(self.payload()))
        opener = mock.Mock(return_value=response)

        fetch_latest_run(self.target, None, opener=opener)

        request = opener.call_args.args[0]
        self.assertIsNone(request.get_header("Authorization"))

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

    def test_main_returns_success_when_every_target_is_healthy(self):
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
                fetcher=lambda _target, _token: self.payload(),
                now=self.now,
            )

        self.assertEqual(result, 0)

    def test_main_returns_monitoring_error_after_a_target_fetch_raises(self):
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

        self.assertEqual(result, 2)
        self.assertEqual(
            requested,
            ["customerio/customerio-ios", "customerio/customerio-flutter"],
        )

    def test_main_uses_repository_token_only_for_its_own_repository(self):
        received_tokens = {}

        def fetcher(target, token):
            received_tokens[target.repository] = token
            return self.payload()

        with mock.patch.dict(
            os.environ,
            {
                "GITHUB_TOKEN": "installation-token",
                "GITHUB_REPOSITORY": "customerio/customerio-ios",
            },
        ), redirect_stdout(io.StringIO()):
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

        self.assertEqual(result, 0)
        self.assertEqual(
            received_tokens,
            {
                "customerio/customerio-ios": "installation-token",
                "customerio/customerio-flutter": None,
            },
        )

    def test_main_omits_token_when_repository_identity_is_unavailable(self):
        received_tokens = []

        def fetcher(_target, token):
            received_tokens.append(token)
            return self.payload()

        with mock.patch.dict(
            os.environ,
            {"GITHUB_TOKEN": "installation-token"},
            clear=True,
        ), redirect_stdout(io.StringIO()):
            result = main(
                [
                    "--target",
                    "customerio/customerio-ios:ios-toolchain-compatibility.yml",
                    "--max-age-hours",
                    "26",
                ],
                fetcher=fetcher,
                now=self.now,
            )

        self.assertEqual(result, 0)
        self.assertEqual(received_tokens, [None])

    def test_main_writes_github_summary(self):
        with tempfile.NamedTemporaryFile(mode="r+", encoding="utf-8") as summary:
            with mock.patch.dict(
                os.environ,
                {"GITHUB_STEP_SUMMARY": summary.name},
            ), redirect_stdout(io.StringIO()):
                result = main(
                    [
                        "--target",
                        "customerio/customerio-ios:ios-toolchain-compatibility.yml",
                        "--max-age-hours",
                        "26",
                    ],
                    fetcher=lambda _target, _token: self.payload(),
                    now=self.now,
                )
            summary.seek(0)
            contents = summary.read()

        self.assertEqual(result, 0)
        self.assertIn("## Xcode 27 nightly watchdog", contents)
        self.assertIn("latest scheduled run succeeded", contents)

    def test_main_preserves_unhealthy_message_when_another_target_has_monitoring_error(self):
        def fetcher(target, _token):
            if target.repository.endswith("customerio-ios"):
                return self.payload(conclusion="failure")
            raise TimeoutError("request timed out")

        output = io.StringIO()
        with redirect_stdout(output):
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

        self.assertEqual(result, 3)
        self.assertIn("latest scheduled run concluded failure", output.getvalue())
        self.assertIn("check failed: request timed out", output.getvalue())

    @mock.patch("scripts.ci.check_xcode27_nightly_runs.main")
    def test_cli_returns_monitoring_error_for_unclassified_fault(self, main_mock):
        main_mock.side_effect = OSError("summary unavailable")
        error = io.StringIO()

        with redirect_stderr(error):
            result = run_cli()

        self.assertEqual(result, 2)
        self.assertIn("watchdog failed before classifying nightlies", error.getvalue())

if __name__ == "__main__":
    unittest.main()
