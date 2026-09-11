import Testing

/// Parent for every suite that reads or overrides `DIGraphShared.shared`.
///
/// `GeofenceBootstrap.wireMonitor` resolves that graph when its chained task *runs*, not when it is
/// called, and `GeofenceModule.initialize()` fires one without awaiting it. Two such suites running
/// in parallel therefore wire one suite's mocks from the other suite's task. `.serialized` on this
/// parent applies to every nested suite, so they take turns.
@Suite(.serialized)
enum SharedDIGraphSuites {}
