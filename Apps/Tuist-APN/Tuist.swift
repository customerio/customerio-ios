import ProjectDescription

// Enables Tuist registry integration (registry.tuist.io).
// Required for --replace-scm-with-registry to actually route through a registry
// instead of silently falling back to Git with "no registry configured" warnings.
let tuist = Tuist(
    fullHandle: "customerio/customerio-ios"
)
