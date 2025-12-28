import Foundation

public struct QueueTaskRunResults: Codable, Equatable {
    public var totalRuns: Int

    enum CodingKeys: String, CodingKey {
        case totalRuns = "total_runs"
    }
}
