import Foundation

public protocol Logger: AutoMockable {
    func verbose(_ message: String)
    func debug(_ message: String)
    func info(_ message: String)
    func warning(_ message: String)
    func error(_ message: String)
}

// sourcery: InjectRegister = "Logger"
public class ConsoleLogger: Logger {
    private let prefix = "[Cio]"

    public func verbose(_ message: String) {
        print("\(prefix) Verbose: \(message)")
    }

    public func debug(_ message: String) {
        print("\(prefix) Debug: \(message)")
    }

    public func info(_ message: String) {
        print("\(prefix) Info: \(message)")
    }

    public func warning(_ message: String) {
        print("\(prefix) Warning: \(message)")
    }

    public func error(_ message: String) {
        print("\(prefix) Error: \(message)")
    }
}
