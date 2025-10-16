import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "GistSSEClient"
public class GistSSEClient: NSObject, URLSessionDataDelegate {
    private let logger: Logger
    private let inAppMessageManager: InAppMessageManager
    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var sessionId = UUID().uuidString
    private var isListening = false
    private var isStopped = false

    private let networkConfig: URLSessionConfiguration = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TimeInterval.infinity
        config.timeoutIntervalForResource = TimeInterval.infinity
        return config
    }()

    init(logger: Logger, inAppMessageManager: InAppMessageManager) {
        self.logger = logger
        self.inAppMessageManager = inAppMessageManager
        super.init()
        self.session = URLSession(configuration: networkConfig, delegate: self, delegateQueue: nil)
    }

    private func logMessage(_ message: String) {
        logger.debug("[DEV][SSE] \(message)")
    }

    func checkForSSEStatus() async {
        guard let url = URL(string: Constants.CONSUMER_STATUS_URL) else {
            logMessage("Invalid CONSUMER_STATUS_URL")
            return
        }

        var request = URLRequest(url: url)
        do {
            let (data, response) = try await session.data(for: request)
            guard
                let httpResponse = response as? HTTPURLResponse,
                let sseHeader = httpResponse.value(forHTTPHeaderField: Constants.SSE_STATUS_HEADER)
            else {
                logMessage("Missing SSE header")
                return
            }

            let useSSE = (sseHeader as NSString).boolValue
            if useSSE {
                logMessage("SSE enabled, starting listener...")
                try await startListening()
            } else {
                logMessage("SSE disabled, fallback to regular flow")
            }
        } catch {
            logMessage("Failed to fetch config: \(error.localizedDescription)")
        }
    }

    public func startListening() async throws {
        guard !isListening else {
            logMessage("Already listening to SSE")
            return
        }

        let state = await inAppMessageManager.state
        guard let userId = state.userId, !userId.isEmpty else {
            logMessage("User ID is empty, cannot start SSE listener")
            return
        }

        let userToken = Data(userId.utf8).base64EncodedString()

        guard var urlComponents = URLComponents(string: Constants.SSE_CONNECTION_URL) else {
            logMessage("Invalid SSE_CONNECTION_URL")
            return
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "siteId", value: state.siteId),
            URLQueryItem(name: "userToken", value: userToken)
        ]

        guard let url = urlComponents.url else {
            logMessage("Failed to build SSE URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        isStopped = false
        task = session.dataTask(with: request)
        task?.resume()
        isListening = true
        logMessage("SSE client started.")
    }

    public func stopListening() {
        logMessage("Stopping listening to SSE")
        isStopped = true
        task?.cancel()
        task = nil
        isListening = false
        logMessage("Stopped listening to SSE")
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isStopped else { return } // ignore any late data
        guard let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n")

        for line in lines where line.hasPrefix("data:") {
            let jsonString = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            logMessage("Received event: \(jsonString)")

            if jsonString.contains("heartbeat") {
                do {
                    if let jsonData = jsonString.data(using: .utf8),
                       let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let heartbeat = json["heartbeat"] as? Int {
                        logMessage("Heartbeat received: \(heartbeat)")
                    }
                } catch {
                    logMessage("Failed to parse heartbeat: \(error.localizedDescription)")
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if isStopped {
            logMessage("Connection closed by client.")
        } else if let error = error {
            logMessage("SSE failure: \(error.localizedDescription)")
        } else {
            logMessage("Connection closed normally.")
        }
        isListening = false
    }

    private enum Constants {
        static let CONSUMER_STATUS_URL = "https://consumer.cloud.gist.build/api/v3/users"
        static let SSE_CONNECTION_URL = "https://realtime.cloud.gist.build/api/v3/sse"
        static let SSE_STATUS_HEADER = "X-CIO-Use-SSE"
    }
}
