public class Example {
    let exampleViewModel: ExampleViewModel = DI.shared.inject(.exampleViewModel)

    public func add(_ num1: Int, _ num2: Int) -> Int {
        num1 + num2
    }

    public func performNetworkCall() {
        exampleViewModel.callNetwork {
            print("Network call done!")
        }
    }
}
