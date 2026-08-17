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


if __name__ == "__main__":
    unittest.main()
