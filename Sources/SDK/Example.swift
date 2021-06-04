public class Example {
    let exampleViewModel: ExampleViewModel = DI.shared.inject(.exampleViewModel)

    var numberTimesNetworkCalled = 0

    public func add(_ num1: Int, _ num2: Int) -> Int {
        num1 + num2
    }

    public func performNetworkCall() {
        exampleViewModel.callNetwork { [weak self] in
            self?.numberTimesNetworkCalled += 1
            print("Network call done!")
        }
    }
}
