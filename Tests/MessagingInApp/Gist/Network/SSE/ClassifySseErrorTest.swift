@testable import CioMessagingInApp
import Foundation
import XCTest

/// Tests for the `classifySseError` function that classifies errors for retry logic.
class ClassifySseErrorTest: XCTestCase {
    // MARK: - URLError Classification

    func test_classifySseError_givenNotConnectedToInternet_expectNetworkError() {
        let urlError = URLError(.notConnectedToInternet)

        let result = classifySseError(urlError)

        XCTAssertEqual(result.errorType, "NetworkError")
        XCTAssertTrue(result.shouldRetry)
    }

    func test_classifySseError_givenNetworkConnectionLost_expectNetworkError() {
        let urlError = URLError(.networkConnectionLost)

        let result = classifySseError(urlError)

        XCTAssertEqual(result.errorType, "NetworkError")
        XCTAssertTrue(result.shouldRetry)
    }

    func test_classifySseError_givenCannotFindHost_expectNetworkError() {
        let urlError = URLError(.cannotFindHost)

        let result = classifySseError(urlError)

        XCTAssertEqual(result.errorType, "NetworkError")
        XCTAssertTrue(result.shouldRetry)
    }

    func test_classifySseError_givenCannotConnectToHost_expectNetworkError() {
        let urlError = URLError(.cannotConnectToHost)

        let result = classifySseError(urlError)

        XCTAssertEqual(result.errorType, "NetworkError")
        XCTAssertTrue(result.shouldRetry)
    }

    func test_classifySseError_givenDnsLookupFailed_expectNetworkError() {
        let urlError = URLError(.dnsLookupFailed)

        let result = classifySseError(urlError)

        XCTAssertEqual(result.errorType, "NetworkError")
        XCTAssertTrue(result.shouldRetry)
    }

    func test_classifySseError_givenTimedOut_expectTimeoutError() {
        let urlError = URLError(.timedOut)

        let result = classifySseError(urlError)

        XCTAssertEqual(result.errorType, "TimeoutError")
        XCTAssertTrue(result.shouldRetry)
    }

    func test_classifySseError_givenOtherURLError_expectNetworkError() {
        let urlError = URLError(.badURL)

        let result = classifySseError(urlError)

        XCTAssertEqual(result.errorType, "NetworkError")
        XCTAssertTrue(result.shouldRetry)
    }

    // MARK: - HTTP Response Code Classification

    func test_classifySseError_givenRequestTimeout408_expectServerErrorRetryable() {
        let error = NSError(domain: "test", code: 408)

        let result = classifySseError(error, responseCode: 408)

        XCTAssertTrue(result.errorType.contains("ServerError"))
        XCTAssertTrue(result.errorType.contains("408"))
        XCTAssertTrue(result.shouldRetry)
    }

    func test_classifySseError_givenTooManyRequests429_expectServerErrorRetryable() {
        let error = NSError(domain: "test", code: 429)

        let result = classifySseError(error, responseCode: 429)

        XCTAssertTrue(result.errorType.contains("ServerError"))
        XCTAssertTrue(result.errorType.contains("429"))
        XCTAssertTrue(result.shouldRetry)
    }

    func test_classifySseError_givenServerError500_expectServerErrorRetryable() {
        let error = NSError(domain: "test", code: 500)

        let result = classifySseError(error, responseCode: 500)

        XCTAssertTrue(result.errorType.contains("ServerError"))
        XCTAssertTrue(result.errorType.contains("500"))
        XCTAssertTrue(result.shouldRetry)
    }

    func test_classifySseError_givenServerError502_expectServerErrorRetryable() {
        let error = NSError(domain: "test", code: 502)

        let result = classifySseError(error, responseCode: 502)

        XCTAssertTrue(result.errorType.contains("ServerError"))
        XCTAssertTrue(result.shouldRetry)
    }

    func test_classifySseError_givenServerError503_expectServerErrorRetryable() {
        let error = NSError(domain: "test", code: 503)

        let result = classifySseError(error, responseCode: 503)

        XCTAssertTrue(result.errorType.contains("ServerError"))
        XCTAssertTrue(result.shouldRetry)
    }

    func test_classifySseError_givenClientError400_expectServerErrorNotRetryable() {
        let error = NSError(domain: "test", code: 400)

        let result = classifySseError(error, responseCode: 400)

        XCTAssertTrue(result.errorType.contains("ServerError"))
        XCTAssertTrue(result.errorType.contains("400"))
        XCTAssertFalse(result.shouldRetry)
    }

    func test_classifySseError_givenUnauthorized401_expectServerErrorNotRetryable() {
        let error = NSError(domain: "test", code: 401)

        let result = classifySseError(error, responseCode: 401)

        XCTAssertTrue(result.errorType.contains("ServerError"))
        XCTAssertFalse(result.shouldRetry)
    }

    func test_classifySseError_givenForbidden403_expectServerErrorNotRetryable() {
        let error = NSError(domain: "test", code: 403)

        let result = classifySseError(error, responseCode: 403)

        XCTAssertTrue(result.errorType.contains("ServerError"))
        XCTAssertFalse(result.shouldRetry)
    }

    func test_classifySseError_givenNotFound404_expectServerErrorNotRetryable() {
        let error = NSError(domain: "test", code: 404)

        let result = classifySseError(error, responseCode: 404)

        XCTAssertTrue(result.errorType.contains("ServerError"))
        XCTAssertFalse(result.shouldRetry)
    }

    // MARK: - Unknown Error Classification

    func test_classifySseError_givenUnknownError_expectUnknownErrorRetryable() {
        let error = NSError(domain: "custom", code: 999, userInfo: [NSLocalizedDescriptionKey: "Custom error"])

        let result = classifySseError(error)

        XCTAssertEqual(result.errorType, "UnknownError")
        XCTAssertTrue(result.shouldRetry)
    }

    // MARK: - SseError Properties

    func test_sseError_networkError_message() {
        let error = SseError.networkError(message: "Connection failed", underlyingError: nil)

        XCTAssertEqual(error.message, "Network error: Connection failed")
        XCTAssertTrue(error.shouldRetry)
        XCTAssertEqual(error.errorType, "NetworkError")
    }

    func test_sseError_timeoutError_message() {
        let error = SseError.timeoutError

        XCTAssertEqual(error.message, "Connection timeout")
        XCTAssertTrue(error.shouldRetry)
        XCTAssertEqual(error.errorType, "TimeoutError")
    }

    func test_sseError_serverError_withCode_message() {
        let error = SseError.serverError(message: "Internal Server Error", responseCode: 500, shouldRetry: true)

        XCTAssertEqual(error.message, "Server error (HTTP 500): Internal Server Error")
        XCTAssertTrue(error.shouldRetry)
        XCTAssertEqual(error.errorType, "ServerError(500)")
    }

    func test_sseError_serverError_withoutCode_message() {
        let error = SseError.serverError(message: "Unknown server error", responseCode: nil, shouldRetry: false)

        XCTAssertEqual(error.message, "Server error: Unknown server error")
        XCTAssertFalse(error.shouldRetry)
        XCTAssertEqual(error.errorType, "ServerError")
    }

    func test_sseError_unknownError_message() {
        let error = SseError.unknownError(message: "Something went wrong", underlyingError: nil)

        XCTAssertEqual(error.message, "Unknown error: Something went wrong")
        XCTAssertTrue(error.shouldRetry)
        XCTAssertEqual(error.errorType, "UnknownError")
    }

    func test_sseError_configurationError_message() {
        let error = SseError.configurationError(message: "Missing user token")

        XCTAssertEqual(error.message, "Configuration error: Missing user token")
        XCTAssertFalse(error.shouldRetry)
        XCTAssertEqual(error.errorType, "ConfigurationError")
    }

    // MARK: - SseError Equatable

    func test_sseError_timeoutError_equatable() {
        XCTAssertEqual(SseError.timeoutError, SseError.timeoutError)
    }

    func test_sseError_serverError_equatable() {
        let error1 = SseError.serverError(message: "Error", responseCode: 500, shouldRetry: true)
        let error2 = SseError.serverError(message: "Error", responseCode: 500, shouldRetry: true)
        let error3 = SseError.serverError(message: "Error", responseCode: 500, shouldRetry: false)

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    func test_sseError_configurationError_equatable() {
        let error1 = SseError.configurationError(message: "Missing token")
        let error2 = SseError.configurationError(message: "Missing token")
        let error3 = SseError.configurationError(message: "Invalid config")

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    func test_sseError_differentTypes_notEqual() {
        let networkError = SseError.networkError(message: "error", underlyingError: nil)
        let timeoutError = SseError.timeoutError
        let configError = SseError.configurationError(message: "error")

        XCTAssertNotEqual(networkError, timeoutError)
        XCTAssertNotEqual(timeoutError, configError)
        XCTAssertNotEqual(networkError, configError)
    }
}
