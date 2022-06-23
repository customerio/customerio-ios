import Foundation

// The SDK has the ability to be used with 1+ different Customer.io workspaces. However,
// there are use cases in the SDK where we do not want to perform an action on a workspace
// that has not been used in a long time. We can assume that those workspaces are not active
// anymore.
//
// In the SDK, a workspace is said to be "active" if the SDK has been initialized with a siteId
// since the app has opened from a cold start. We only keep track of these active workspaces in-memory
// so when the app opens from a cold start again, we can assume that any workspace used previously
// may never be used again.
public protocol ActiveWorkspacesManager: AutoMockable {
    func addWorkspace(siteId: SiteId)
    var activeWorkspaces: [SiteId] { get }
}

// sourcery: InjectRegister = "ActiveWorkspacesManager"
// sourcery: InjectSingleton
public class InMemoryActiveWorkspaces: ActiveWorkspacesManager {
    private var activeWorkspacesSet: Set<SiteId> = Set()

    public var activeWorkspaces: [SiteId] {
        Array(activeWorkspacesSet)
    }

    public func addWorkspace(siteId: SiteId) {
        activeWorkspacesSet.insert(siteId)
    }

    // Convenient method to get instance. This object is meant to be shared by all workspaces running
    // with the SDK so we need to use the special instance of the DI graph.
    public static func getInstance() -> ActiveWorkspacesManager {
        DIGraph.getAllWorkspacesSharedInstance().activeWorkspacesManager
    }
}
