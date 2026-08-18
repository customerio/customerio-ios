#!/usr/bin/env python3

from pathlib import Path
import unittest


SOURCE = (Path(__file__).resolve().parent / "src" / "AppDelegate.swift").read_text(encoding="utf-8")
APP_SOURCE = (Path(__file__).resolve().parent / "src" / "App.swift").read_text(encoding="utf-8")


class LifecycleInstrumentationTests(unittest.TestCase):
    def test_sdk_deep_link_uses_routing_helper_without_fabricating_os_callback(self) -> None:
        callback = SOURCE.split(".deepLinkCallback", 1)[1].split("let logLevel", 1)[0]
        self.assertIn("routeUniversalLink(openLinkInHostAppActivity)", callback)
        self.assertNotIn("self.application(", callback)
        self.assertNotIn("callback: .applicationContinueUserActivity", callback)

    def test_real_delegate_selector_owns_os_entry_before_shared_routing_helper(self) -> None:
        selector = SOURCE.split("func application(_ application: UIApplication, continue userActivity:", 1)[1]
        selector = selector.split("private func routeUniversalLink", 1)[0]
        first_record = selector.index("LifecycleTraceHarness.sharedRecorder?.record")
        self.assertLess(selector.index("guard userActivity.webpageURL != nil"), first_record)
        self.assertIn("hostTopology == .appDelegateOnly", selector)
        self.assertEqual(selector.count("callback: .applicationContinueUserActivity"), 1)
        self.assertEqual(selector.count("callback: .hostRouteUserActivity"), 2)
        self.assertIn("let handled = routeUniversalLink(userActivity)", selector)
        self.assertIn("LifecycleTraceHarness.endScenario(after: .hostUserActivityRoute)", selector)
        self.assertIn("return handled", selector)

        helper = SOURCE.split("private func routeUniversalLink", 1)[1]
        helper = helper.split("\n    }", 1)[0]
        self.assertNotIn("sharedRecorder?.record", helper)
        self.assertNotIn("callback:", helper)
        self.assertIn("return false", helper)

    def test_launch_and_live_activity_classification_use_canonical_guards(self) -> None:
        launch_helper = SOURCE.split("private func recordLaunchCallback", 1)[1]
        launch_helper = launch_helper.split("\n    }", 1)[0]
        self.assertIn("scenario.isColdStart == true", launch_helper)
        self.assertIn("LifecycleTraceEvidence.isCustomerIOLiveActivityRoute(incomingURL)", APP_SOURCE)
        self.assertIn("LifecycleTraceEvidence.isTraceableURLRoute(incomingURL)", APP_SOURCE)
        self.assertIn("hostTopology == .swiftUILifecycle", APP_SOURCE)
        self.assertIn("callback: .swiftUIScenePhaseChange", APP_SOURCE)
        self.assertIn("hostTopology == .swiftUILifecycle", APP_SOURCE)

    def test_raw_universal_link_is_never_logged(self) -> None:
        self.assertNotIn('print("universalLinkUrl:', SOURCE)


if __name__ == "__main__":
    unittest.main()
