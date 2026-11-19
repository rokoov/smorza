import CoreAudio
import Foundation

/// A Core Audio call that returned an error status.
struct CoreAudioError: LocalizedError {
    let operation: String
    let status: OSStatus

    var errorDescription: String? {
        "\(operation) failed (\(fourCharacterCode(UInt32(bitPattern: status))))"
    }
}

/// Core Audio packs four characters into its codes ('who?'); anything else stays a number.
func fourCharacterCode(_ value: UInt32) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> UInt32($0)) }
    guard bytes.allSatisfy({ (32..<127).contains($0) }) else { return String(Int32(bitPattern: value)) }
    return "'\(String(decoding: bytes, as: UTF8.self))'"
}

/// Throws a `CoreAudioError` naming `operation` unless `status` is `noErr`.
func check(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(operation: operation(), status: status) }
}
