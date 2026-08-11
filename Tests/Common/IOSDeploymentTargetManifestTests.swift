import Foundation
import XCTest

final class IOSDeploymentTargetManifestTests: XCTestCase {
    private let expectedManifestMarkers: [String: String] = [
        "Apps/Common/Package.swift": ".iOS(.v15)",
        "Apps/Common/SampleAppsCommon.podspec": "spec.ios.deployment_target = \"15.0\"",
        "CustomerIO.podspec": "spec.ios.deployment_target = \"15.0\"",
        "CustomerIOCommon.podspec": "spec.ios.deployment_target = \"15.0\"",
        "CustomerIODataPipelines.podspec": "spec.ios.deployment_target = \"15.0\"",
        "CustomerIOLiveActivities.podspec": "spec.ios.deployment_target = \"15.0\"",
        "CustomerIOLiveActivitiesAttributes.podspec": "spec.ios.deployment_target = \"15.0\"",
        "CustomerIOLiveActivitiesTemplates.podspec": "spec.ios.deployment_target = \"15.0\"",
        "CustomerIOLocation.podspec": "spec.ios.deployment_target = \"15.0\"",
        "CustomerIOLocationGeofence.podspec": "spec.ios.deployment_target = \"15.0\"",
        "CustomerIOMessagingInApp.podspec": "spec.ios.deployment_target = \"15.0\"",
        "CustomerIOMessagingInbox.podspec": "spec.ios.deployment_target = \"15.0\"",
        "CustomerIOMessagingPush.podspec": "spec.ios.deployment_target = \"15.0\"",
        "CustomerIOMessagingPushAPN.podspec": "spec.ios.deployment_target = \"15.0\"",
        "CustomerIOMessagingPushFCM.podspec": "spec.ios.deployment_target = \"15.0\"",
        "CustomerIOTrackingMigration.podspec": "spec.ios.deployment_target = \"15.0\"",
        "Package.swift": ".iOS(.v15)"
    ]

    func testOwnedIOSManifests_whenValidated_useIOS15DeploymentTarget() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let discoveredManifests = try discoverOwnedIOSManifests(in: repositoryRoot)
        let expectedManifests = Set(expectedManifestMarkers.keys)

        XCTAssertEqual(
            discoveredManifests,
            expectedManifests,
            "Owned iOS manifest inventory changed. Added: \(discoveredManifests.subtracting(expectedManifests).sorted()); missing: \(expectedManifests.subtracting(discoveredManifests).sorted())"
        )

        for (relativePath, marker) in expectedManifestMarkers {
            let contents = try String(
                contentsOf: repositoryRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            let activeDeploymentDeclarations = contents
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { line in
                    !line.hasPrefix("//") &&
                        !line.hasPrefix("#") &&
                        (line.hasPrefix(".iOS(.v") || line.hasPrefix("spec.ios.deployment_target"))
                }
            XCTAssertEqual(
                activeDeploymentDeclarations,
                [marker],
                "Expected \(relativePath) to contain exactly one active iOS deployment declaration: \(marker)"
            )
        }
    }

    private func discoverOwnedIOSManifests(in repositoryRoot: URL) throws -> Set<String> {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: repositoryRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ManifestDiscoveryError.cannotEnumerate(repositoryRoot.path)
        }

        let excludedDirectories: Set = [".build", ".swiftpm", "Pods"]
        var manifests: Set<String> = []

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true, excludedDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            guard values.isDirectory != true,
                  url.lastPathComponent == "Package.swift" || url.pathExtension == "podspec"
            else {
                continue
            }

            let relativePath = String(url.path.dropFirst(repositoryRoot.path.count + 1))
            manifests.insert(relativePath)
        }

        return manifests
    }

    private enum ManifestDiscoveryError: Error {
        case cannotEnumerate(String)
    }
}
