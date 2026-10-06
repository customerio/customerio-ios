import CioMessagingPushFCM
import Foundation

// MARK: - Mock FirebaseService for Testing

class MockFirebaseService: FirebaseService {
    var mockApnsToken: Data?
    var mockDelegate: FirebaseServiceDelegate?
    var mockTokenCompletion: ((String?, Error?) -> Void)?
    var fetchTokenCallCount = 0
    var mockIsInstallationIdEnabled = false
    var mockInstallationIdCompletion: ((String?, Error?) -> Void)?
    var fetchInstallationIdCallCount = 0

    // MARK: - FirebaseService Protocol Implementation

    var apnsToken: Data? {
        get {
            mockApnsToken
        }
        set {
            mockApnsToken = newValue
        }
    }

    var delegate: FirebaseServiceDelegate? {
        get {
            mockDelegate
        }
        set {
            mockDelegate = newValue
        }
    }

    func fetchToken(completion: @escaping (String?, Error?) -> Void) {
        fetchTokenCallCount += 1
        mockTokenCompletion = completion
    }

    var isInstallationIdEnabled: Bool {
        mockIsInstallationIdEnabled
    }

    func fetchInstallationId(completion: @escaping (String?, Error?) -> Void) {
        fetchInstallationIdCallCount += 1
        mockInstallationIdCompletion = completion
    }

    // MARK: - Test Helper Methods

    func simulateTokenSuccess(_ token: String) {
        mockTokenCompletion?(token, nil)
    }

    func simulateTokenError(_ error: Error) {
        mockTokenCompletion?(nil, error)
    }

    func simulateInstallationIdSuccess(_ fid: String) {
        mockInstallationIdCompletion?(fid, nil)
    }

    func simulateInstallationIdError(_ error: Error) {
        mockInstallationIdCompletion?(nil, error)
    }

    func simulateRegistrationToken(_ token: String?) {
        mockDelegate?.didReceiveRegistrationToken(token)
    }

    func simulateRegistration(_ installationId: String?) {
        mockDelegate?.didReceiveRegistration(installationId)
    }

    func reset() {
        mockApnsToken = nil
        mockDelegate = nil
        mockTokenCompletion = nil
        fetchTokenCallCount = 0
        mockIsInstallationIdEnabled = false
        mockInstallationIdCompletion = nil
        fetchInstallationIdCallCount = 0
    }
}

// MARK: - Mock FirebaseServiceDelegate for Testing

class MockFirebaseServiceDelegate: FirebaseServiceDelegate {
    var receivedToken: String?
    var tokenCallCount = 0
    var didReceiveRegistrationTokenCalled = false
    var receivedRegistrations: [String?] = []

    func didReceiveRegistrationToken(_ token: String?) {
        receivedToken = token
        tokenCallCount += 1
        didReceiveRegistrationTokenCalled = true
    }

    func didReceiveRegistration(_ installationId: String?) {
        receivedRegistrations.append(installationId)
    }

    func reset() {
        receivedToken = nil
        tokenCallCount = 0
        didReceiveRegistrationTokenCalled = false
        receivedRegistrations = []
    }
}
