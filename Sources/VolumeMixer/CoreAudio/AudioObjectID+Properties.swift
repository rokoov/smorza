import CoreAudio
import Foundation

extension AudioObjectPropertyAddress {
    init(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) {
        self.init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}

/// Typed access to the properties of a Core Audio object.
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

    func readBool(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> Bool {
        ((try? read(selector, scope: scope, initial: UInt32(0))) ?? 0) != 0
    }

    func readString(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> String {
        var address = AudioObjectPropertyAddress(selector, scope: scope)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, pointer)
        }
        try check(status, describe("Reading", selector))
        guard let value else {
            throw CoreAudioError(operation: describe("Reading", selector), status: kAudioHardwareUnspecifiedError)
        }
        // The HAL hands back a retained CFString.
        return value.takeRetainedValue() as String
    }

    func readObjectIDs(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(selector, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size), describe("Sizing", selector))
        let capacity = Int(size) / MemoryLayout<AudioObjectID>.size
        guard capacity > 0 else { return [] }
        var objectIDs = [AudioObjectID](repeating: .unknown, count: capacity)
        try check(AudioObjectGetPropertyData(self, &address, 0, nil, &size, &objectIDs), describe("Reading", selector))
        return Array(objectIDs.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    func write<Value>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        value: Value
    ) throws {
        var address = AudioObjectPropertyAddress(selector, scope: scope)
        let size = UInt32(MemoryLayout<Value>.size)
        let status = withUnsafePointer(to: value) { pointer in
            AudioObjectSetPropertyData(self, &address, 0, nil, size, pointer)
        }
        try check(status, describe("Writing", selector))
    }

    func isSettable(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> Bool {
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
