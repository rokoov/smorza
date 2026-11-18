import AppKit

/// The app a row in the mixer stands for. Every process with the same key shares one slider.
struct AppIdentity: Equatable {
    let key: String
    let name: String
    let icon: NSImage
}
