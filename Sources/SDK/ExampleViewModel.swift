protocol ExampleViewModel: AutoMockable {
    func callNetwork(_ onComplete: @escaping () -> Void)
}

// sourcery: InjectRegister = "ExampleViewModel"
class AppExampleViewModel: ExampleViewModel {
    let exampleRepository: ExampleRepository

    init(exampleRepository: ExampleRepository) {
        self.exampleRepository = exampleRepository
    }

    func callNetwork(_ onComplete: @escaping () -> Void) {
        exampleRepository.callNetwork(onComplete)
    }
}
