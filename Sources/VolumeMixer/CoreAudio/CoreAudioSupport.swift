import CoreAudio
import Foundation

struct CoreAudioError: LocalizedError {
    let operation: String
    let status: OSStatus

    var errorDescription: String? { "\(operation) failed (\(fourCharacterCode(UInt32(bitPattern: status))))" }
}

func fourCharacterCode(_ value: UInt32) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> UInt32($0)) }
    guard bytes.allSatisfy({ (32..<127).contains($0) }) else { return String(Int32(bitPattern: value)) }
    return "'\(String(decoding: bytes, as: UTF8.self))'"
}

func check(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(operation: operation(), status: status) }
}

extension AudioObjectPropertyAddress {
    init(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) {
        self.init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    var isKnown: Bool { self != .unknown }

    func read<Value>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        initial: Value
    ) throws -> Value {
        var address = AudioObjectPropertyAddress(selector, scope: scope)
        var value = initial
        var size = UInt32(MemoryLayout<Value>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, pointer)
        }
        try check(status, describe("Reading", selector))
        return value
    }

    func readBool(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
        ((try? read(selector, scope: scope, initial: UInt32(0))) ?? 0) != 0
    }

    func readString(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> String {
        var address = AudioObjectPropertyAddress(selector, scope: scope)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, pointer)
        }
        try check(status, describe("Reading", selector))
        guard let value else { throw CoreAudioError(operation: describe("Reading", selector), status: kAudioHardwareUnspecifiedError) }
        // The HAL hands back a retained CFString.
        return value.takeRetainedValue() as String
    }

    func readObjectIDs(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(selector, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size), describe("Sizing", selector))
        let capacity = Int(size) / MemoryLayout<AudioObjectID>.size
        guard capacity > 0 else { return [] }
        var objectIDs = [AudioObjectID](repeating: .unknown, count: capacity)
        try check(AudioObjectGetPropertyData(self, &address, 0, nil, &size, &objectIDs), describe("Reading", selector))
        return Array(objectIDs.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    func write<Value>(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, value: Value) throws {
        var address = AudioObjectPropertyAddress(selector, scope: scope)
        let size = UInt32(MemoryLayout<Value>.size)
        let status = withUnsafePointer(to: value) { pointer in
            AudioObjectSetPropertyData(self, &address, 0, nil, size, pointer)
        }
        try check(status, describe("Writing", selector))
    }

    func isSettable(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
        var address = AudioObjectPropertyAddress(selector, scope: scope)
        guard AudioObjectHasProperty(self, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(self, &address, &settable) == noErr && settable.boolValue
    }

    func streamCount(scope: AudioObjectPropertyScope) -> Int {
        (try? readObjectIDs(kAudioDevicePropertyStreams, scope: scope).count) ?? 0
    }

    private func describe(_ verb: String, _ selector: AudioObjectPropertySelector) -> String {
        "\(verb) \(fourCharacterCode(selector)) of audio object \(self)"
    }
}

/// Marks the first `count` input streams of an aggregate device unused for one IO callback. They are
/// the output device's own inputs (a headset microphone), which come before the tap's stream, so
/// starting the callback never opens the microphone or drops Bluetooth headphones to call quality.
func ignoreInputStreams(_ count: Int, of aggregateID: AudioObjectID, procID: AudioDeviceIOProcID) {
    guard count > 0 else { return }
    let streamCount = count + 1
    let flagsOffset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn) ?? 12
    let size = flagsOffset + streamCount * MemoryLayout<UInt32>.size
    let storage = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment)
    defer { storage.deallocate() }

    let usage = storage.bindMemory(to: AudioHardwareIOProcStreamUsage.self, capacity: 1)
    usage.pointee.mIOProc = unsafeBitCast(procID, to: UnsafeMutableRawPointer.self)
    usage.pointee.mNumberStreams = UInt32(streamCount)
    let flags = (storage + flagsOffset).bindMemory(to: UInt32.self, capacity: streamCount)
    for index in 0..<streamCount {
        flags[index] = index < count ? 0 : 1
    }

    var address = AudioObjectPropertyAddress(kAudioDevicePropertyIOProcStreamUsage, scope: kAudioObjectPropertyScopeInput)
    let status = AudioObjectSetPropertyData(aggregateID, &address, 0, nil, UInt32(size), storage)
    if status != noErr {
        log.error("Could not mark device inputs unused: \(fourCharacterCode(UInt32(bitPattern: status)), privacy: .public)")
    }
}

/// One flag the IO thread raises and the main thread reads. A single aligned word cannot tear.
final class SignalFlag {
    private let storage: UnsafeMutablePointer<UInt32>

    init() {
        storage = .allocate(capacity: 1)
        storage.initialize(to: 0)
    }

    deinit { storage.deallocate() }

    var isRaised: Bool { storage.pointee != 0 }

    func raise() { storage.pointee = 1 }
}

/// One Core Audio property listener, removed when invalidated or released.
final class PropertyListener {
    private let objectID: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let queue: DispatchQueue
    private let block: AudioObjectPropertyListenerBlock
    private var isRegistered = false

    init(
        _ objectID: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        queue: DispatchQueue = .main,
        handler: @escaping () -> Void
    ) {
        self.objectID = objectID
        self.queue = queue
        address = AudioObjectPropertyAddress(selector, scope: scope)
        block = { _, _ in handler() }
        isRegistered = AudioObjectAddPropertyListenerBlock(objectID, &address, queue, block) == noErr
    }

    deinit { invalidate() }

    func invalidate() {
        guard isRegistered else { return }
        isRegistered = false
        // Fails harmlessly when the object (a process that quit) is already gone.
        AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, block)
    }
}
