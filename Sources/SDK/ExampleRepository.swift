protocol ExampleRepository: AutoMockable {
    func callNetwork(_ onComplete: @escaping () -> Void)
}

// sourcery: InjectRegister = "ExampleRepository"
class AppExampleRepository: ExampleRepository {
    func callNetwork(_ onComplete: @escaping () -> Void) {
        onComplete()
    }
}
