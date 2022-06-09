import Foundation

public class Mocks {
    public static var shared: Mocks = .init()

    private var mocks: [Mock] = []
    private init() {}

    public func add(mock: Mock) {
        mocks.append(mock)
    }

    public func resetAll() {
        mocks.forEach {
            $0.resetMock()
        }
    }
}

public protocol Mock {
    func resetMock()
}
