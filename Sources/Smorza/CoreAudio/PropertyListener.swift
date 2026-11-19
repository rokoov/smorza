import CoreAudio
import Foundation

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
