import Foundation

/// Inherit in a UIViewController subclass to avoid having an automatic screenview event tracked for it.
/// Currently only being used internally. `public` only because multiple SDK modules use it.
public protocol DoNotTrackScreenViewEvent {}
