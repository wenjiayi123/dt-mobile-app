import Foundation

/// Returns true when an installed application was rebuilt after the currently
/// running process started. LaunchServices otherwise activates that stale
/// process even though the app bundle on disk already contains a newer shell.
func requiresFreshApplicationLaunch(
    launchDate: Date?,
    executableModifiedAt: Date?,
    tolerance: TimeInterval = 0.5
) -> Bool {
    guard let executableModifiedAt else { return false }
    guard let launchDate else { return true }
    return executableModifiedAt.timeIntervalSince(launchDate) > tolerance
}
