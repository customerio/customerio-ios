@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class RichPushRequestTests: UnitTest {
    private var httpClientMock: HttpClientMock!
    private let imageURL = URL(string: "https://example.com/rich-image.png")!

    override func setUp() {
        super.setUp()
        httpClientMock = HttpClientMock()
        mockCollection.add(mocks: [httpClientMock])
    }

    // MARK: - start()

    func test_start_expectHttpClientDownloadFileCalledWithImageURLAndRichPushImageType() {
        let completionCalled = expectation(description: "completion called")
        httpClientMock.downloadFileClosure = { url, fileType, onComplete in
            XCTAssertEqual(url, self.imageURL)
            XCTAssertEqual(fileType, .richPushImage)
            onComplete(nil)
        }

        let push = PushNotificationStub.getPushSentFromCIO(imageUrl: imageURL.absoluteString)
        let request = RichPushRequest(
            push: push,
            imageURL: imageURL,
            httpClient: httpClientMock,
            completionHandler: { _ in completionCalled.fulfill() }
        )

        request.start()

        wait(for: [completionCalled], timeout: 1.0)
        XCTAssertEqual(httpClientMock.downloadFileCallsCount, 1)
    }

    func test_start_whenDownloadSucceedsWithFilePath_expectPushHasAttachmentAndCompletionCalledOnce() {
        let givenLocalPath = URL(fileURLWithPath: "/tmp/cio-image-123.png")
        var receivedPush: PushNotification?
        let completionCalled = expectation(description: "completion called")
        httpClientMock.downloadFileClosure = { [weak self] _, _, onComplete in
            onComplete(givenLocalPath)
        }

        let push = PushNotificationStub.getPushSentFromCIO(imageUrl: imageURL.absoluteString)
        let request = RichPushRequest(
            push: push,
            imageURL: imageURL,
            httpClient: httpClientMock,
            completionHandler: { push in
                receivedPush = push
                completionCalled.fulfill()
            }
        )

        request.start()

        wait(for: [completionCalled], timeout: 1.0)
        XCTAssertEqual(receivedPush?.cioRichPushImageFile, givenLocalPath)
        XCTAssertEqual(receivedPush?.cioAttachments.count, 1)
        XCTAssertEqual(receivedPush?.cioAttachments.first?.localFileUrl, givenLocalPath)
    }

    func test_start_whenDownloadSucceedsWithNilPath_expectCompletionCalledWithUnmodifiedPush() {
        var receivedPush: PushNotification?
        let completionCalled = expectation(description: "completion called")
        httpClientMock.downloadFileClosure = { _, _, onComplete in
            onComplete(nil)
        }

        let push = PushNotificationStub.getPushSentFromCIO(imageUrl: imageURL.absoluteString)
        let request = RichPushRequest(
            push: push,
            imageURL: imageURL,
            httpClient: httpClientMock,
            completionHandler: { push in
                receivedPush = push
                completionCalled.fulfill()
            }
        )

        request.start()

        wait(for: [completionCalled], timeout: 1.0)
        XCTAssertNil(receivedPush?.cioRichPushImageFile)
        XCTAssertTrue(receivedPush?.cioAttachments.isEmpty ?? false)
    }

    func test_start_whenDownloadCallbackNotInvoked_expectCompletionNotCalled() {
        var completionCallCount = 0
        httpClientMock.downloadFileClosure = { _, _, _ in
            // Never call onComplete
        }

        let push = PushNotificationStub.getPushSentFromCIO(imageUrl: imageURL.absoluteString)
        let request = RichPushRequest(
            push: push,
            imageURL: imageURL,
            httpClient: httpClientMock,
            completionHandler: { _ in completionCallCount += 1 }
        )

        request.start()

        // Give a short window; completion should not be called
        usleep(100000)
        XCTAssertEqual(completionCallCount, 0)
    }

    // MARK: - cancel()

    func test_cancel_whenNotCompleted_expectCompletionCalledOnceWithoutHttpClientCancel() {
        var completionCallCount = 0
        var receivedPush: PushNotification?
        httpClientMock.downloadFileClosure = { _, _, _ in
            // Never complete download
        }

        let push = PushNotificationStub.getPushSentFromCIO(imageUrl: imageURL.absoluteString)
        let request = RichPushRequest(
            push: push,
            imageURL: imageURL,
            httpClient: httpClientMock,
            completionHandler: { push in
                completionCallCount += 1
                receivedPush = push
            }
        )

        request.start()
        request.cancel()

        XCTAssertEqual(completionCallCount, 1)
        XCTAssertEqual(httpClientMock.cancelCallsCount, 0)
        XCTAssertNil(receivedPush?.cioRichPushImageFile)
    }

    func test_cancel_whenCalledTwice_expectCompletionAndHttpClientCancelOnlyCalledOnce() {
        var completionCallCount = 0
        httpClientMock.downloadFileClosure = { _, _, _ in }

        let push = PushNotificationStub.getPushSentFromCIO(imageUrl: imageURL.absoluteString)
        let request = RichPushRequest(
            push: push,
            imageURL: imageURL,
            httpClient: httpClientMock,
            completionHandler: { _ in completionCallCount += 1 }
        )

        request.start()
        request.cancel()
        request.cancel()

        XCTAssertEqual(completionCallCount, 1)
        XCTAssertEqual(httpClientMock.cancelCallsCount, 0)
    }

    func test_cancel_beforeStart_expectCompletionCalledWithoutHttpClientCancel() {
        var completionCalled = false
        let push = PushNotificationStub.getPushSentFromCIO(imageUrl: imageURL.absoluteString)
        let request = RichPushRequest(
            push: push,
            imageURL: imageURL,
            httpClient: httpClientMock,
            completionHandler: { _ in completionCalled = true }
        )

        request.cancel()

        XCTAssertTrue(completionCalled)
        XCTAssertEqual(httpClientMock.cancelCallsCount, 0)
    }

    // MARK: - start then cancel / completeOnce idempotency

    func test_start_whenDownloadCompletesThenCancel_expectCompletionOnlyCalledOnce() {
        var completionCallCount = 0
        let completionCalled = expectation(description: "completion called")
        httpClientMock.downloadFileClosure = { _, _, onComplete in
            onComplete(nil)
        }

        let push = PushNotificationStub.getPushSentFromCIO(imageUrl: imageURL.absoluteString)
        let request = RichPushRequest(
            push: push,
            imageURL: imageURL,
            httpClient: httpClientMock,
            completionHandler: { _ in
                completionCallCount += 1
                completionCalled.fulfill()
            }
        )

        request.start()
        wait(for: [completionCalled], timeout: 1.0)
        request.cancel()

        XCTAssertEqual(completionCallCount, 1)
    }
}
