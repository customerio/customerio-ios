// sourcery: InjectRegister = "ExampleViewModel"
class ExampleViewModel {
    let exampleRepository: ExampleRepository

    init(exampleRepository: ExampleRepository) {
        self.exampleRepository = exampleRepository
    }

    func callNetwork(_ onComplete: () -> Void) {
        exampleRepository.callNetwork(onComplete)
    }
}
