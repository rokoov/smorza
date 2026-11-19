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
