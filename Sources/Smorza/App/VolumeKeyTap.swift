import AppKit
import CoreGraphics
import IOKit.hidsystem

/// Catches the volume keys while Control is held, through a session event tap, and lets every other
/// key through untouched. Creating it needs the Accessibility permission.
@MainActor
final class VolumeKeyTap {
    enum Key {
        case up
        case down
        case mute
    }

    /// NX_SYSDEFINED: media and other special keys arrive as this event type.
    private static let systemDefinedType: UInt32 = 14
    /// The system-defined subtype that carries media key presses.
    private static let mediaKeySubtype: Int16 = 8
    /// Key state in a media key event's data: 0xA is down, 0xB is up.
    private static let keyDownState = 0xA

    private let handler: (_ key: Key, _ isFine: Bool) -> Void
    private var machPort: CFMachPort?
    private var source: CFRunLoopSource?

    /// Nil when the system refuses the tap, which means the permission is missing.
    init?(handler: @escaping (_ key: Key, _ isFine: Bool) -> Void) {
        self.handler = handler
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(1 << Self.systemDefinedType),
                callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    let tap = Unmanaged<VolumeKeyTap>.fromOpaque(context).takeUnretainedValue()
                    // The tap's run loop source sits on the main run loop.
                    return MainActor.assumeIsolated { tap.handle(type: type, event: event) }
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else { return nil }
        machPort = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func invalidate() {
        if let machPort {
            CGEvent.tapEnable(tap: machPort, enable: false)
            CFMachPortInvalidate(machPort)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        machPort = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system switches off a tap that is slow or interrupted; switch it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let machPort {
                CGEvent.tapEnable(tap: machPort, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == Self.systemDefinedType,
            event.flags.contains(.maskControl),
            let mediaEvent = NSEvent(cgEvent: event),
            mediaEvent.subtype.rawValue == Self.mediaKeySubtype,
            let key = Self.key(forCode: Int32((mediaEvent.data1 & 0xFFFF_0000) >> 16))
        else { return Unmanaged.passUnretained(event) }

        if (mediaEvent.data1 & 0xFF00) >> 8 == Self.keyDownState {
            handler(key, event.flags.contains(.maskShift))
        }
        // Both the press and the release are kept from the system, so its own volume stays put.
        return nil
    }

    private static func key(forCode code: Int32) -> Key? {
        switch code {
        case NX_KEYTYPE_SOUND_UP: .up
        case NX_KEYTYPE_SOUND_DOWN: .down
        case NX_KEYTYPE_MUTE: .mute
        default: nil
        }
    }
}
