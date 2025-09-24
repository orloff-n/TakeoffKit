//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import CloudKit

/// An object that manages the sync engine’s state.
///
/// Contains information such as enqueued operations, iCloud account status and various
/// boolean flags, which is critical for regulating the behaviour of ``TKSyncEngine``
/// and is updated internally based on a series of previously dispatched events.
///
/// Available properties are read-only and intended solely for debugging and monitoring purposes.
@MainActor
public final class TKSyncEngineState: ObservableObject {
    /// Operation queues managed by the sync engine.
    ///
    /// ``TKSyncEngine`` processes operations sequentially through multiple specialized queues,
    /// each handling a specific type of CloudKit operation. The engine switches between the queues
    /// based on their priority and whether the current state allows a specific type of operation
    /// to be performed.
    ///
    /// `CaseIterable` conformance ensures that the queues are always processed
    /// in the same order as listed in the enum:
    /// 1. `createZone` – record zone creation
    /// 2. `subscribe` – record zone subscription creation
    /// 3. `send` – sending changes
    /// 4. `fetch` – fetching changes
    ///
    /// None of the queues are allowed if ``TKSyncEngineState/isRunning`` is set to `false`
    /// or ``TKSyncEngineState/accountStatus`` is not equal to `available`.
    /// `send` and `fetch` queues are enabled only after ``TKSyncEngineState/isZoneAvailable``
    /// and ``TKSyncEngineState/isSubscribed`` are set to `true`.
    ///
    /// > SeeAlso: ``TKSyncEngineState`` for the sync engine's state properties.
    ///
    /// Each case provides a formatted `String` representation suitable for UI presentation
    /// (e.g. a debug screen).
    public enum Queue: String, CaseIterable, Sendable {
        case createZone = "Creating record zone"
        case subscribe = "Subscribing to zone changes"
        case send = "Sending changes"
        case fetch = "Fetching changes"
    }
    
    /// Current active queue of the sync engine.
    @Published public private(set) var currentQueue: Queue?
    
    /// The number of operations in all queues waiting to be performed.
    @Published public private(set) var pendingOperationsCount = 0
    
    /// Last successfully completed fetch operation date.
    @Published public private(set) var lastFetchedDate: Date?
    
    /// Last successfully completed send operation date.
    @Published public private(set) var lastSentDate: Date?
    
    /// Current iCloud account status.
    @Published public private(set) var accountStatus: CKAccountStatus?
    
    /// Indicates whether the engine is allowed to perform any operations.
    @Published public private(set) var isRunning = false
    
    /// Indicates whether the `CKRecordZone` is available.
    @Published public private(set) var isZoneAvailable = false
    
    /// Indicates whether a `CKRecordZoneSubscription` has been created.
    @Published public private(set) var isSubscribed = false
    
    /// Indicates how many times the current operation has been retried.
    @Published public private(set) var retryCount = 0
    
    /// The error that caused the current operation to retry.
    @Published public private(set) var retryReason: Error?
    
    private var createZoneQueue = [CKRecordZone.ID]()
    private var subscribeQueue = [TKSubscribeOperation]()
    private var sendQueue = [TKSendOperation]()
    private var fetchQueue = [TKFetchOperation]()
    
    // MARK: Update state
    /// Updates the state based on the dispatched event.
    func update(with event: TKSyncEngineEvent) {
        switch event {
        case .start:
            isRunning = true
            updateCurrentQueue()
        case .stop:
            isRunning = false
            updateCurrentQueue()
        case .accountStatusChanged(let status):
            accountStatus = status
            updateCurrentQueue()
        case .operationEnqueued(let operation):
            enqueue(operation)
            updateCurrentQueue()
        case .operationSucceeded(let response):
            retryCount = 0
            retryReason = nil
            dequeueCurrentOperation()
            
            switch response {
            case .createZone(let success):
                isZoneAvailable = success
            case .subscribe(let success):
                isSubscribed = success
            case .send:
                lastSentDate = Date()
            case .fetch(let response):
                if response.moreComing {
                    enqueuePrioritized(.fetch(TKFetchOperation(changeToken: response.changeToken)))
                } else {
                    lastFetchedDate = Date()
                }
            }
            
            updateCurrentQueue()
        case .operationFailed:
            break // Failures dispatch other events - no changes are necessary
        case .operationRetry(let error):
            retryCount += 1
            retryReason = error
        case .operationReplaced(let operations):
            retryCount = 0
            retryReason = nil
            dequeueCurrentOperation()
            operations.forEach(enqueuePrioritized)
            updateCurrentQueue()
        }
    }
    
    /// Resets the state.
    func reset() {
        currentQueue = nil
        pendingOperationsCount = 0
        lastFetchedDate = nil
        lastSentDate = nil
        accountStatus = nil
        isRunning = false
        isZoneAvailable = false
        isSubscribed = false
        retryCount = 0
        retryReason = nil
        createZoneQueue.removeAll()
        subscribeQueue.removeAll()
        sendQueue.removeAll()
        fetchQueue.removeAll()
    }
    
    // MARK: Queue logic
    /// The current operation that is, or is to be, performed.
    var currentOperation: TKOperation? {
        switch currentQueue {
        case .createZone:
            if let operation = createZoneQueue.first {
                return .createZone(operation)
            }
        case .subscribe:
            if let operation = subscribeQueue.first {
                return .subscribe(operation)
            }
        case .send:
            if let operation = sendQueue.first {
                return .send(operation)
            }
        case .fetch:
            if let operation = fetchQueue.first {
                return .fetch(operation)
            }
        default:
            return nil
        }
        return nil
    }
    
    /// The queues from which the engine is allowed to perform operations.
    private var enabledQueues: Set<Queue> {
        var enabledQueues = Set<Queue>()
        
        if !isRunning || accountStatus != .available {
            return enabledQueues
        }
        
        enabledQueues.formUnion([.createZone, .subscribe])
        
        if isZoneAvailable && isSubscribed {
            enabledQueues.formUnion([.send, .fetch])
        }
        
        return enabledQueues
    }
    
    /// Updates the active queue.
    private func updateCurrentQueue() {
        currentQueue = Queue.allCases
            .filter { enabledQueues.contains($0) }
            .first { queue in
                switch queue {
                case .createZone:
                    !createZoneQueue.isEmpty
                case .subscribe:
                    !subscribeQueue.isEmpty
                case .send:
                    !sendQueue.isEmpty
                case .fetch:
                    !fetchQueue.isEmpty
                }
            }
        
        pendingOperationsCount = countQueueLength()
    }
    
    /// Counts the number of operations in all queues.
    private func countQueueLength() -> Int {
        Queue.allCases.reduce(into: 0) { result, queue in
            switch queue {
            case .createZone:
                result += createZoneQueue.count
            case .subscribe:
                result += subscribeQueue.count
            case .send:
                result += sendQueue.count
            case .fetch:
                result += fetchQueue.count
            }
        }
    }
    
    /// Adds an operation to the end of the appropriate queue.
    private func enqueue(_ operationType: TKOperation) {
        switch operationType {
        case .createZone(let operation):
            createZoneQueue.append(operation)
        case .subscribe(let operation):
            subscribeQueue.append(operation)
        case .send(let operation):
            sendQueue.append(operation)
        case .fetch(let operation):
            fetchQueue.append(operation)
        }
    }
    
    /// Adds an operation to the beginning of the appropriate queue.
    private func enqueuePrioritized(_ operationType: TKOperation) {
        switch operationType {
        case .createZone(let operation):
            createZoneQueue = [operation] + createZoneQueue
        case .subscribe(let operation):
            subscribeQueue = [operation] + subscribeQueue
        case .send(let operation):
            sendQueue = [operation] + sendQueue
        case .fetch(let operation):
            fetchQueue = [operation] + fetchQueue
        }
    }
    
    /// Removes the current operation from the queue.
    private func dequeueCurrentOperation() {
        switch currentOperation {
        case .createZone:
            createZoneQueue.removeFirst()
        case .subscribe:
            subscribeQueue.removeFirst()
        case .send:
            sendQueue.removeFirst()
        case .fetch:
            fetchQueue.removeFirst()
        case nil:
            break
        }
    }
}
