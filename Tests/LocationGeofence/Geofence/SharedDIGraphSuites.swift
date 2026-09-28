import Testing

/// Parent for every suite that reads or overrides `DIGraphShared.shared`.
///
/// `GeofenceBootstrap.wireMonitor` resolves the graph when its chained task runs, not when it is
/// called, and `GeofenceModule.initialize()` fires one without awaiting it, so two such suites in
/// parallel wire each other's mocks. `.serialized` here applies to every nested suite.
@Suite(.serialized)
enum SharedDIGraphSuites {}
