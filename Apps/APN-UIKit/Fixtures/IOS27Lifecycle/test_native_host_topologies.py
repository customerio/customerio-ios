import plistlib
import unittest
from pathlib import Path


APP_ROOT = Path(__file__).resolve().parents[2] / "APN UIKit"
FIXTURE_ROOT = Path(__file__).resolve().parent


class NativeHostTopologyTests(unittest.TestCase):
    @staticmethod
    def _build_configuration(project: str, identifier: str, name: str) -> str:
        marker = f"\t\t{identifier} /* {name} */ = {{"
        start = project.index(marker)
        end = project.index(f"\n\t\t}};\n\t\t", start) + len("\n\t\t};")
        return project[start:end]

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
        app_configurations = (
            self._build_configuration(project, "46D5D9A829E459D800EAF40B", "Debug"),
            self._build_configuration(project, "46D5D9A929E459D800EAF40B", "Release"),
        )
        for configuration in app_configurations:
            self.assertIn(
                'CIO_LIFECYCLE_INFOPLIST_FILE = "APN UIKit/Info.plist";',
                configuration,
            )
            self.assertIn(
                'INFOPLIST_FILE = "$(CIO_LIFECYCLE_INFOPLIST_FILE)";',
                configuration,
            )
        notification_service_debug = self._build_configuration(
            project, "4650330829F68FEB001B6552", "Debug"
        )
        self.assertNotIn("CIO_LIFECYCLE_INFOPLIST_FILE", notification_service_debug)
        compilation_setting = (
            'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) '
            '$(CIO_LIFECYCLE_SWIFT_ACTIVE_COMPILATION_CONDITIONS)";'
        )
        self.assertEqual(project.count(compilation_setting), 2)

        control = (FIXTURE_ROOT / "AppDelegateOnly.xcconfig").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            "CIO_LIFECYCLE_INFOPLIST_FILE = APN UIKit/Info-AppDelegateOnly.plist",
            control,
        )
        self.assertIn(
            "CIO_LIFECYCLE_SWIFT_ACTIVE_COMPILATION_CONDITIONS = "
            "CIO_APP_DELEGATE_ONLY",
            control,
        )

        workflow = (
            APP_ROOT.parents[2] / ".github/workflows/ios-toolchain-compatibility.yml"
        ).read_text(encoding="utf-8")
        self.assertNotIn("cp \"$control_info\" \"$default_info\"", workflow)
        self.assertEqual(
            workflow.split("pull_request:", 1)[1].split("schedule:", 1)[0].count("- '"),
            1,
        )
        fastfile = (APP_ROOT.parents[1] / "fastlane/Fastfile").read_text(
            encoding="utf-8"
        )
        self.assertIn("resolve_declared_build_settings", fastfile)
        self.assertIn(
            "build_settings.fetch(setting_name, matched_expression)",
            fastfile,
        )
        self.assertIn(
            "plutil -extract UIApplicationSceneManifest xml1", workflow
        )
        self.assertIn("-appdelegate-only-xcode-27", workflow)
        self.assertIn(
            "AppDelegate-only control unexpectedly contains UIApplicationSceneManifest.",
            workflow,
        )
        contract_workflow = (
            APP_ROOT.parents[2] / ".github/workflows/test.yml"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "python scripts/ios27_lifecycle_contract.py sync",
            contract_workflow,
        )
        self.assertIn("--source-root .", contract_workflow)
        self.assertIn(
            '--destination-root "$contract_copy"',
            contract_workflow,
        )

    def testAppDelegateOnlyControl_compilesOutSceneSessionSelectors(self) -> None:
        source = (APP_ROOT / "AppDelegate.swift").read_text(encoding="utf-8")
        scene_section = source.split("// MARK: UISceneSession Lifecycle", 1)[1].split(
            "\n}\n\n/*", 1
        )[0]

        guard_start = scene_section.index("#if !CIO_APP_DELEGATE_ONLY")
        guard_end = scene_section.index("#endif")
        for selector in (
            "configurationForConnecting connectingSceneSession",
            "didDiscardSceneSessions sceneSessions",
        ):
            selector_position = scene_section.index(selector)
            self.assertLess(guard_start, selector_position)
            self.assertLess(selector_position, guard_end)

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
