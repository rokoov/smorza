import Foundation

/// The System Audio Recording permission. macOS has no public API for it: it asks the first time
/// a tap starts, and a denied tap delivers silence without an error. TCC's private preflight call
/// is the only way to tell the two apart.
enum AudioCapturePermission: String {
    case authorized
    case denied
    case undetermined

    static var canCheck: Bool { preflight != nil }

    static func current() -> AudioCapturePermission {
        guard let preflight else { return .undetermined }
        switch preflight("kTCCServiceAudioCapture" as CFString, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .undetermined
        }
    }

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int

    private static let preflight: Preflight? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW),
              let symbol = dlsym(handle, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(symbol, to: Preflight.self)
    }()
}
