import plistlib
import unittest
from pathlib import Path


APP_ROOT = Path(__file__).resolve().parents[2] / "APN UIKit"


class NativeHostTopologyTests(unittest.TestCase):
    def testUISceneControl_hasOneParticipatingScene(self) -> None:
        with (APP_ROOT / "Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        manifest = info["UIApplicationSceneManifest"]
        self.assertFalse(manifest["UIApplicationSupportsMultipleScenes"])
        configurations = manifest["UISceneConfigurations"][
            "UIWindowSceneSessionRoleApplication"
        ]
        self.assertEqual(len(configurations), 1)
        self.assertEqual(
            configurations[0]["UISceneDelegateClassName"],
            "$(PRODUCT_MODULE_NAME).SceneDelegate",
        )

    def testAppDelegateOnlyControl_hasNoSceneManifest(self) -> None:
        with (APP_ROOT / "Info-AppDelegateOnly.plist").open("rb") as stream:
            info = plistlib.load(stream)
        self.assertNotIn("UIApplicationSceneManifest", info)

    def testAppDelegateOnlyURLRoute_matchesCanonicalTraceChain(self) -> None:
        source = (APP_ROOT / "AppDelegate.swift").read_text(encoding="utf-8")
        selector = source.split("open url: URL", 1)[1].split(
            "func initializeCioAndInAppListeners", 1
        )[0]

        self.assertIn("LifecycleTraceEvidence.isTraceableURLRoute(url)", selector)
        self.assertIn("LifecycleTraceEvidence.isCustomerIOLiveActivityRoute(url)", selector)
        self.assertEqual(selector.count("callback: .hostRouteURL"), 2)
        self.assertEqual(selector.count("callback: .customerIORouteDeepLink"), 2)
        self.assertLess(
            selector.index("phase: .intent"),
            selector.index("CustomerIO.liveActivities.handleWidgetUrl(url)"),
        )
        self.assertLess(
            selector.index("CustomerIO.liveActivities.handleWidgetUrl(url)"),
            selector.index("phase: .result"),
        )
        self.assertIn("if traceRoute {", selector)
        self.assertIn("LifecycleTraceHarness.endScenario(after: .hostURLRoute)", selector)


if __name__ == "__main__":
    unittest.main()
