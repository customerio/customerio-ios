import Foundation

/// Backport of `AsyncStream.makeStream()` for iOS 13+.
///
/// `AsyncStream.makeStream()` was introduced in iOS 17 and provides a way to create
/// an AsyncStream and access its continuation separately. This is useful when you need
/// to set up resources that require the continuation before returning the stream.
///
/// This backport provides the same functionality for older iOS versions.
enum AsyncStreamBackport {
    /// Creates an AsyncStream and returns both the stream and its continuation separately.
    ///
    /// This allows setup code to access the continuation before the stream is consumed,
    /// enabling synchronous setup patterns that avoid race conditions.
    ///
    /// Example:
    /// ```swift
    /// func connect() -> AsyncStream<Event> {
    ///     let (stream, continuation) = AsyncStreamBackport.makeStream(of: Event.self)
    ///
    ///     // Use continuation immediately for setup
    ///     let handler = EventHandler(continuation: continuation)
    ///     self.connection = Connection(handler: handler)
    ///     self.connection.start()
    ///
    ///     return stream
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - elementType: The type of elements in the stream.
    ///   - bufferingPolicy: The buffering policy for the stream. Defaults to `.unbounded`.
    /// - Returns: A tuple containing the stream and its continuation.
    static func makeStream<Element>(
        of elementType: Element.Type = Element.self,
        bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded
    ) -> (stream: AsyncStream<Element>, continuation: AsyncStream<Element>.Continuation) {
        // Capture the continuation from the closure using an optional variable
        var continuation: AsyncStream<Element>.Continuation?

        let stream = AsyncStream<Element>(bufferingPolicy: bufferingPolicy) { cont in
            // This closure is called synchronously during AsyncStream initialization
            continuation = cont
        }

        // By the time AsyncStream's init returns, the closure has executed
        // and continuation is guaranteed to be set
        guard let continuation = continuation else {
            // This should never happen - the closure is called synchronously
            fatalError("AsyncStream continuation was not set during initialization")
        }

        return (stream, continuation)
    }
}
