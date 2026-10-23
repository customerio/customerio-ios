import Foundation
import Testing

struct GeofenceTaskLintRuleTests {
    @Test
    func regex_givenTaskExpressions_expectSpawnsOnly() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 {
            root.deleteLastPathComponent()
        }
        let config = try String(contentsOf: root.appendingPathComponent(".swiftlint.yml"), encoding: .utf8)
        let line = try #require(config.components(separatedBy: "\n").first { $0.contains("    regex:") })
        let literal = line.components(separatedBy: "regex: ")[1]
        let pattern = try JSONDecoder().decode(String.self, from: Data(literal.utf8))
        let regex = try NSRegularExpression(pattern: pattern)
        let cases: [(String, Bool)] = [
            ("Task { work() }", true),
            ("Task<Void, Never> { work() }", true),
            ("Task<\nVoid,\nNever\n> { work() }", true),
            ("Task\n.detached { work() }", true),
            ("Task . detached { work() }", true),
            ("Task<Result<A, B>, Never> { work() }", true),
            ("Task<(@Sendable () -> Void)?, Never>.init(operation: work)", true),
            ("Task.init(operation: work)", true),
            ("Task.immediate { work() }", true),
            ("func spawn() -> Task<Void, Never> { task }", false),
            ("var task: Task<Result<A, B>, Never> { stored }", false),
            ("var task: Task<Void, Never>?", false),
            ("await task.value", false),
            ("Task.yield()", false),
            ("taskSpawner.spawn { work() }", false)
        ]
        for (source, expected) in cases {
            let matched = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil
            #expect(matched == expected, "Unexpected task rule match for: \(source)")
        }
    }
}
