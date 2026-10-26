"""Exercise the real publish script with fake commands; never publish a pod."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'push-cocoapod.sh'
REPO = SCRIPT.parent.parent
SDK_VERSION = re.search(r'public static let version: String = "([^"]+)"',
                        (REPO / 'Sources/Common/Version.swift').read_text()).group(1)
TIMEOUT = '[!] Calling the GitHub commit API timed out. Please try again later.'
SUCCESS = 'CustomerIOCommon (5.0.0) successfully published'
CLOSED = '[!] We have closed pushing to CocoaPods trunk'
STUB = r'''
import json, os, sys
from pathlib import Path
path = Path(os.environ['PUSH_TEST_STATE'])
s = json.loads(path.read_text())
tool = Path(sys.argv[0]).name
args = sys.argv[1:]
event = {'tool': tool, 'args': args, 'time': s['now']}
s['events'].append(event)
code = 0
if tool == 'date':
    print(int(s['now']))
elif tool == 'sleep':
    s['now'] += float(args[0])
elif tool == 'curl':
    index = s['curl_calls']
    s['curl_calls'] += 1
    status = s['statuses'][min(index, len(s['statuses']) - 1)]
    if s.get('published_at') is not None:
        status = '200' if s['now'] >= s['published_at'] else '404'
    timeout = float(args[args.index('--max-time') + 1])
    delay = s.get('curl_delay', 0)
    s['now'] += min(delay, timeout)
    if delay > timeout or status == '000':
        status, code = '000', 28
    event['status'], event['max_time'] = status, timeout
    print(status, end='')
elif tool == 'pod':
    index = s['pod_calls']
    s['pod_calls'] += 1
    output = s['outputs'][min(index, len(s['outputs']) - 1)]
    print(output)
    code = 0 if 'successfully published' in output else 1
else:
    raise RuntimeError('unexpected stub: ' + tool)
path.write_text(json.dumps(s))
sys.exit(code)
'''


class PushCocoapodTests(unittest.TestCase):
    def run_script(self, statuses=('404',), outputs=(TIMEOUT,), published_at=None,
                   curl_delay=0, podspec=None, argument='spec', podspec_file=None,
                   expected_name='CustomerIOCommon', expected_version='5.0.0'):
        with tempfile.TemporaryDirectory(prefix='push-cocoapod-test-') as directory:
            root = Path(directory)
            (root / 'bin').mkdir()
            state_path = root / 'state.json'
            state_path.write_text(json.dumps({
                'now': 0, 'events': [], 'curl_calls': 0, 'pod_calls': 0,
                'statuses': list(statuses), 'outputs': list(outputs),
                'published_at': published_at, 'curl_delay': curl_delay,
            }))
            for name in ('pod', 'curl', 'sleep', 'date'):
                path = root / 'bin' / name
                path.write_text('#!' + sys.executable + '\n' + STUB)
                path.chmod(0o755)
            spec = root / 'sample.podspec'
            spec.write_text(podspec if podspec is not None else (
                'Pod::Spec.new do |spec|\n'
                '  spec.name = "CustomerIOCommon"\n'
                '  spec.version = "5.0.0"\nend\n'
            ))
            args = [] if argument is None else [str(podspec_file or (spec if argument == 'spec' else root / argument))]
            env = {**os.environ, 'PATH': str(root / 'bin') + ':' + os.environ['PATH'],
                   'PUSH_TEST_STATE': str(state_path)}
            env.pop('COCOAPODS_TRUNK_TOKEN', None)
            result = subprocess.run(
                [os.environ.get('PUSH_COCOAPOD_TEST_SHELL', '/bin/sh'), str(SCRIPT), *args],
                env=env, capture_output=True, text=True, timeout=30,
            )
            state = json.loads(state_path.read_text())
            self.assertNotIn('not found', result.stderr, result.stderr)
            for event in state['events']:
                if event['tool'] == 'pod':
                    self.assertEqual(event['args'][:2], ['trunk', 'push'])
                    self.assertEqual(event['args'][-2:], ['--allow-warnings', '--synchronous'])
                if event['tool'] == 'curl':
                    self.assertEqual(event['args'][-1],
                                     f'https://trunk.cocoapods.org/api/v1/pods/{expected_name}/versions/{expected_version}')
            return result, state

    def assert_exit(self, result, expected):
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)

    def test_already_published_version_skips_push_and_sleep(self):
        result, state = self.run_script(statuses=['200'])
        self.assert_exit(result, 0)
        self.assertEqual(state['pod_calls'], 0)
        self.assertEqual(state['curl_calls'], 1)
        self.assertFalse(any(e['tool'] == 'sleep' for e in state['events']))

    def test_missing_or_unknown_version_does_not_block_successful_push(self):
        for status in ['404', '000', '503']:
            with self.subTest(status=status):
                result, state = self.run_script(statuses=[status], outputs=[SUCCESS])
                self.assert_exit(result, 0)
                self.assertEqual(state['pod_calls'], 1)

    def test_real_release_podspecs_skip_using_their_exact_identity(self):
        for name in ['CustomerIOCommon', 'CioFirebaseWrapper']:
            with self.subTest(name=name):
                # Read the real files unchanged, including trailing version comments,
                # interpolation and subspecs. The SDK's public version is the oracle.
                result, state = self.run_script(
                    statuses=['200'], podspec_file=REPO / (name + '.podspec'),
                    expected_name=name, expected_version=SDK_VERSION,
                )
                self.assert_exit(result, 0)
                self.assertEqual(state['pod_calls'], 0)
                self.assertEqual(state['curl_calls'], 1)

    def test_timeout_lands_after_old_45_second_check_without_repush(self):
        result, state = self.run_script(published_at=90)
        self.assert_exit(result, 0)
        self.assertEqual(state['pod_calls'], 1)
        self.assertGreaterEqual(state['now'], 90)
        self.assertLessEqual(state['now'], 180)

    def test_commit_arriving_during_backoff_avoids_another_push(self):
        result, state = self.run_script(published_at=195)
        self.assert_exit(result, 0)
        self.assertEqual(state['pod_calls'], 1)
        self.assertEqual(state['now'], 210)

    def test_known_transient_failures_retry_after_settling(self):
        for output in [TIMEOUT, '[!] An error occurred on GitHub’s side.',
                       '[!] An internal server error occurred. Please try again later.',
                       '[!] HTTP 502 Bad Gateway', '[!] request returned status code: 503',
                       '[!] There was an error pushing a new version to trunk: Net::ReadTimeout']:
            with self.subTest(output=output):
                result, state = self.run_script(outputs=[output, SUCCESS])
                self.assert_exit(result, 0)
                self.assertEqual(state['pod_calls'], 2)
                self.assertEqual(state['now'], 210)

    def test_three_retries_are_bounded_and_preserve_status_diagnostics(self):
        for status, diagnostic in [('404', 'does not hold'), ('000', 'HTTP 000')]:
            with self.subTest(status=status):
                result, state = self.run_script(statuses=[status])
                self.assert_exit(result, 1)
                self.assertEqual(state['pod_calls'], 4)
                self.assertIn(diagnostic, result.stdout)
                self.assertIn('after 4 push attempt(s)', result.stdout)
                self.assertEqual(state['now'], 930)

    def test_curl_time_is_part_of_the_settling_deadline(self):
        result, state = self.run_script(curl_delay=20)
        self.assert_exit(result, 1)
        self.assertEqual(state['pod_calls'], 4)
        # Four 180s windows, 30/60/120s backoff, and four 20s checks outside windows.
        self.assertEqual(state['now'], 1010)
        self.assertTrue(any(e['tool'] == 'curl' and e['max_time'] < 20 for e in state['events']))

    def test_permanent_or_unclassified_errors_are_not_retried(self):
        for output in ['[!] Authentication token is invalid or unverified',
                       '[!] The spec did not pass validation',
                       '[!] Compile error at line 500 in TimeoutHandler.swift']:
            with self.subTest(output=output):
                result, state = self.run_script(outputs=[output])
                self.assert_exit(result, 1)
                self.assertEqual(state['pod_calls'], 1)
                self.assertEqual(state['now'], 45)

    def test_unknown_failure_still_accepts_confirmed_publication(self):
        result, state = self.run_script(statuses=['404', '200'], outputs=['[!] Some other failure'])
        self.assert_exit(result, 0)
        self.assertEqual(state['pod_calls'], 1)
        self.assertEqual(state['now'], 45)

    def test_duplicate_racing_with_preflight_remains_success(self):
        result, state = self.run_script(outputs=['[!] Unable to accept duplicate entry for: CustomerIOCommon'])
        self.assert_exit(result, 0)
        self.assertEqual(state['pod_calls'], 1)
        self.assertEqual(state['now'], 0)

    def test_closed_trunk_preserves_existing_exit_codes_without_retry(self):
        for status, expected in [('200', 0), ('404', 3), ('000', 1), ('503', 1)]:
            with self.subTest(status=status):
                result, state = self.run_script(statuses=['404', status], outputs=[CLOSED])
                self.assert_exit(result, expected)
                self.assertEqual(state['pod_calls'], 1)
                self.assertEqual(state['now'], 0)

    def test_trunk_closing_on_a_retry_stops_further_attempts(self):
        result, state = self.run_script(outputs=[TIMEOUT, CLOSED])
        self.assert_exit(result, 3)
        self.assertEqual(state['pod_calls'], 2)

    def test_permanent_error_on_retry_stops_further_pushes(self):
        result, state = self.run_script(outputs=[TIMEOUT, '[!] The spec did not pass validation'])
        self.assert_exit(result, 1)
        self.assertEqual(state['pod_calls'], 2)
        self.assertIn('after 2 push attempt(s)', result.stdout)
        self.assertEqual(state['now'], 255)

    def test_invalid_podspec_identity_fails_before_network_or_push(self):
        for body in ['spec.name = "CustomerIOCommon"\n', 'spec.version = "5.0.0"\n', '']:
            with self.subTest(body=body):
                result, state = self.run_script(podspec=body)
                self.assert_exit(result, 1)
                self.assertEqual(state['pod_calls'], 0)
                self.assertEqual(state['curl_calls'], 0)

    def test_missing_podspec_or_argument_fails_without_network(self):
        for argument in [None, 'missing.podspec']:
            with self.subTest(argument=argument):
                result, state = self.run_script(argument=argument)
                self.assert_exit(result, 1)
                self.assertEqual(state['pod_calls'], 0)
                self.assertEqual(state['curl_calls'], 0)


if __name__ == '__main__':
    unittest.main()
