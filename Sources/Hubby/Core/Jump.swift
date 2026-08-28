import Foundation

/// What a jump actually achieved, best first. The UI collapses on anything
/// that landed, shakes on `.failed`, and offers the Accessibility grant
/// when `.needsAccessibility` says a better landing was possible.
enum JumpResolution {
    /// Landed on the precise thread (deep link) or its exact window.
    case exactThread
    /// Raised a best-guess window of the right app.
    case window
    /// Only the app could be activated.
    case appActivated
    /// The app was activated, but an exact landing exists behind the
    /// Accessibility permission Hubby doesn't hold yet.
    case needsAccessibility
    /// Nothing to activate (app not installed).
    case failed
}
