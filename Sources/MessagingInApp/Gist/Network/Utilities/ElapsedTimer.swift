import CioInternalCommon
import Foundation

class ElapsedTimer {
    private let logger: Logger = DIGraphShared.shared.logger
    private var title: String?
    private var startTime: CFAbsoluteTime?

    func start(title: String) {
        self.title = title
        startTime = CFAbsoluteTimeGetCurrent()
    }

    func end() {
        guard let startTime = startTime, let title = title else {
            return
        }
        let timeElapsed = ((CFAbsoluteTimeGetCurrent() - startTime) * 1000).rounded() / 1000.0
        logger.logWithModuleTag("\(title) timer elapsed in \(timeElapsed) seconds", level: .info)
        self.startTime = nil
    }
}
