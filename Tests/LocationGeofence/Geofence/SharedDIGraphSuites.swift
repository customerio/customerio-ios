import Testing

/// Parent for every suite that touches `DIGraphShared.shared`; `.serialized` covers nested suites.
/// `initialize()` resolves the graph in an unawaited task, so parallel suites wire each other's mocks.
@Suite(.serialized)
enum SharedDIGraphSuites {}
