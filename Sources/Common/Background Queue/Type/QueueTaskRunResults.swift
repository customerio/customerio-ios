import Foundation

public struct QueueTaskRunResults: Codable, Equatable {
    let totalRuns: Int

    enum CodingKeys: String, CodingKey {
        case totalRuns = "total_runs"
    }
}
