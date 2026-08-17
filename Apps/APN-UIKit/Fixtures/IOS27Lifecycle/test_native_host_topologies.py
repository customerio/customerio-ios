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
        project = (
            APP_ROOT.parent / "APN UIKit.xcodeproj" / "project.pbxproj"
        ).read_text(encoding="utf-8")
        setting = 'INFOPLIST_FILE = "APN UIKit/Info$(CIO_LIFECYCLE_INFOPLIST_SUFFIX).plist";'
        self.assertEqual(project.count(setting), 2)

    def testAppDelegateOnlyURLRoute_matchesCanonicalTraceChain(self) -> None:
        source = (APP_ROOT / "AppDelegate.swift").read_text(encoding="utf-8")
        scene_source = (APP_ROOT / "SceneDelegate.swift").read_text(encoding="utf-8")
        router_source = (APP_ROOT / "Util" / "DeepLinksHandlerUtil.swift").read_text(
            encoding="utf-8"
        )
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
        route_call = "routeAppSchemeDestination"
        self.assertIn(route_call, selector)
        self.assertIn(route_call, scene_source)
        self.assertIn(
            "destination.host == LiveActivitiesViewController.deepLinkHost",
            router_source,
        )
        self.assertIn("pushViewController(LiveActivitiesViewController()", router_source)
        self.assertIn("LifecycleTraceHarness.endScenario(after: .hostURLRoute)", selector)

    def testAppDelegateUniversalLink_onlyTracesAppDelegateOnlyTopology(self) -> None:
        source = (APP_ROOT / "AppDelegate.swift").read_text(encoding="utf-8")
        selector = source.split(
            "continue userActivity: NSUserActivity", 1
        )[1].split("// MARK: UISceneSession Lifecycle", 1)[0]

        topology_guard = (
            "LifecycleTraceHarness.sharedRecorder?.hostTopology == .appDelegateOnly"
        )
        route_call = "deepLinkHandler.handleUniversalLinkDeepLink(universalLinkUrl)"
        self.assertIn(topology_guard, selector)
        self.assertEqual(selector.count("callback: .applicationContinueUserActivity"), 1)
        self.assertEqual(selector.count("callback: .hostRouteUserActivity"), 2)
        self.assertEqual(selector.count("if shouldTraceIngress {"), 2)
        self.assertIn(route_call, selector)
        self.assertLess(selector.index("if shouldTraceIngress {"), selector.index(route_call))
        self.assertLess(selector.index(route_call), selector.rindex("if shouldTraceIngress {"))
        self.assertIn(
            "LifecycleTraceHarness.endScenario(after: .hostUserActivityRoute)",
            selector,
        )


if __name__ == "__main__":
    unittest.main()
