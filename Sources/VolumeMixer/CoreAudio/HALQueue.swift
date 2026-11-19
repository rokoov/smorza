import Foundation

/// Runs Core Audio calls that can block on their own queue. Creating an IO callback waits on
/// coreaudiod, which can take seconds while it first checks a new build or tears down the routes
/// of a mixer that just quit; on the main thread that wait froze the app's launch.
enum HALQueue {
    private static let queue = DispatchQueue(label: "com.rokoov.volumemixer.hal", qos: .userInitiated)

    static func run<Value>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }
}
