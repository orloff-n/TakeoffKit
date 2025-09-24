//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import CloudKit

/// An object that manages the synchronization of local data with CloudKit.
///
/// This is the core object of TakeoffKit. It provides a simple interface for local data
/// synchronization, abstracting numerous CloudKit complexities like record conversion,
/// error handling, rate limits and so on.
///
/// ## Usage
/// To use the sync engine:
/// 1. Conform your data models to ``TKSyncable``.
/// 2. Initialize the engine, specifying a ``TKSyncEngineConfiguration``.
/// 3. Provide a ``delegate``, implementing ``TKSyncEngineDelegate``.
/// 4. Call ``start()`` to start the engine.
///
/// You can call ``fetchChanges(token:)`` and ``sendChanges(modify:delete:)``
/// at any time. These operations will be added to the queue, but they will not be performed
/// unless the sync engine is running and the required conditions are met.
///
/// > SeeAlso: ``TKSyncEngineState/Queue`` for queue management.
///
/// ## Limitations
/// > Important: The following CloudKit features are not supported:
/// > - Public databases
/// > - Record sharing
/// > - Multiple record zones & subscriptions
///
/// ## Multithreading
/// This class is marked with `@MainActor` to enable ``state`` publishing and make ``delegate``
/// a variable rather than an `init()` argument.
///
/// All internal operations are performed as background tasks.
///
/// ## Example
/// ```swift
/// let config = TKSyncEngineConfiguration(
///     containerID: "iCloud.com.example.MyApp",
///     zoneName: "MyDataZone",
///     subscriptionID: "MySubscription"
/// )
///
/// let engine = TKSyncEngine(configuration: config)
/// engine.delegate = self
/// engine.start()
///
/// // Send changes
/// engine.sendChanges(modify: modifiedItems, delete: deletedIDs)
///
/// // Fetch changes
/// engine.fetchChanges(token: lastChangeToken)
/// ```
@MainActor
public final class TKSyncEngine {
    /// The sync engine’s state.
    public let state = TKSyncEngineState()
    
    /// The sync engine’s delegate.
    public weak var delegate: TKSyncEngineDelegate?
    
    private let operationHandler: TKOperationHandler
    private let container: CKContainer
    private let zoneID: CKRecordZone.ID
    private let subscriptionID: String
    private let maxRetryAttempts: Int
    private let maxRecordsPerOperation: Int
    
    /// Creates a sync engine with the specified configuration.
    /// - Parameter configuration: The settings of the sync engine.
    public init(configuration: TKSyncEngineConfiguration) {
        operationHandler = TKOperationHandler(configuration: configuration)
        
        if let containerID = configuration.containerID {
            container = CKContainer(identifier: containerID)
        } else {
            container = .default()
        }
        
        if let zoneName = configuration.zoneName {
            zoneID = CKRecordZone.ID(zoneName: zoneName)
        } else {
            zoneID = CKRecordZone.default().zoneID
        }
        
        subscriptionID = configuration.subscriptionID ?? configuration.zoneName ?? "takeoffkit.subscription"
        maxRetryAttempts = configuration.maxRetryAttempts
        maxRecordsPerOperation = configuration.maxRecordsPerOperation
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(getAccountStatus),
            name: .CKAccountChanged,
            object: nil
        )
        
        if configuration.checkAccountStatusOnInit {
            getAccountStatus()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: Public methods
    /// Starts the sync engine, allowing it to perform operations.
    public func start() {
        dispatch(event: .start)
    }
    
    /// Stops the sync engine, aborting any operations.
    ///
    /// > Warning:
    /// If you stop the engine while an operation is in progress, its response will not be processed.
    public func stop() {
        dispatch(event: .stop())
    }
    
    /// Resets the sync engine's state.
    ///
    /// > Warning: This will remove all operations from the queue.
    public func reset() {
        state.reset()
    }
    
    /// Fetches remote changes from iCloud.
    /// - Parameter token: The current change token.
    public func fetchChanges(token: CKServerChangeToken?) {
        dispatch(event: .operationEnqueued(.fetch(.init(changeToken: token))))
    }
    
    /// Sends locals changes to iCloud.
    /// - Parameters:
    ///   - instancesToModify: An array of ``TKSyncable`` instances to modify.
    ///   - idsToDelete: An array of ``TKSyncable/tkRecordID``
    ///   (equals to `recordName` of `CKRecord.ID`) to delete.
    public func sendChanges(modify instancesToModify: [TKSyncable], delete idsToDelete: [String]) {
        let modifications = instancesToModify.map { $0.convertToCKRecord(zoneID: zoneID) }
        let deletions = idsToDelete.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
        
        if modifications.count + deletions.count <= maxRecordsPerOperation {
            dispatch(event: .operationEnqueued(.send(
                TKSendOperation(modifications: modifications, deletions: deletions)
            )))
        } else {
            let splitModifications = modifications.chunked(into: maxRecordsPerOperation)
            let splitDeletions = deletions.chunked(into: maxRecordsPerOperation)
            
            splitModifications.forEach { modifications in
                dispatch(event: .operationEnqueued(.send(TKSendOperation(modifications: modifications, deletions: []))))
            }
            
            splitDeletions.forEach { deletions in
                dispatch(event: .operationEnqueued(.send(TKSendOperation(modifications: [], deletions: deletions))))
            }
        }
    }
    
    // MARK: Private methods
    private func dispatch(event: TKSyncEngineEvent) {
        Task(priority: .background) {
            TKLogger.log(.syncEngine, message: "Dispatched event: \(event.debugDescription)")
            
            let previousOperation = state.currentOperation
            state.update(with: event)
            
            switch event {
            case .start:
                await prepareForSyncing()
            case .stop(let error):
                if let error {
                    delegate?.syncEngine(self, didStopWithError: error)
                }
            case .accountStatusChanged(let status):
                delegate?.syncEngine(self, didChangeAccountStatus: status)
            case .operationSucceeded(let response):
                handleSuccess(response)
            case .operationFailed(let error):
                await handleFailure(error)
            case .operationRetry(let ckError):
                await scheduleRetry(ckError)
            default:
                break
            }
            
            if let currentOperation = state.currentOperation, currentOperation != previousOperation {
                Task(priority: .background) {
                    await perform(currentOperation)
                }
            }
        }
    }
    
    private func prepareForSyncing() async {
        if !state.isZoneAvailable {
            dispatch(event: .operationEnqueued(.createZone(zoneID)))
        }
        
        if !state.isSubscribed {
            dispatch(event: .operationEnqueued(.subscribe(.init(zoneID: zoneID, subscriptionID: subscriptionID))))
        }
        
        if state.accountStatus != .available {
            await getAccountStatusAsync()
        }
    }
    
    private func getAccountStatusAsync() async {
        do {
            let status = try await container.accountStatus()
            dispatch(event: .accountStatusChanged(status))
        } catch {
            TKLogger.log(.syncEngine, level: .error, message: "Unable to check account status: \(error)")
        }
    }
    
    @objc private nonisolated func getAccountStatus() {
        Task(priority: .background) {
            await getAccountStatusAsync()
        }
    }
    
    private func perform(_ operation: TKOperation) async {
        switch operation {
        case .createZone(let id):
            let result = await operationHandler.createZone(with: id)
            switch result {
            case .success(let success):
                dispatch(event: .operationSucceeded(.createZone(success)))
            case .failure(let error):
                dispatch(event: .operationFailed(error))
            }
        case .subscribe(let operation):
            let result = await operationHandler.subscribe(operation)
            switch result {
            case .success(let success):
                dispatch(event: .operationSucceeded(.subscribe(success)))
            case .failure(let error):
                dispatch(event: .operationFailed(error))
            }
        case .send(let operation):
            let result = await operationHandler.send(operation)
            switch result {
            case .success(let response):
                dispatch(event: .operationSucceeded(.send(response)))
            case .failure(let error):
                dispatch(event: .operationFailed(error))
            }
        case .fetch(let operation):
            let result = await operationHandler.fetch(operation, zoneID: zoneID)
            switch result {
            case .success(let response):
                dispatch(event: .operationSucceeded(.fetch(response)))
            case .failure(let error):
                dispatch(event: .operationFailed(error))
            }
        }
    }
    
    private func handleSuccess(_ response: TKOperation.Response) {
        guard state.isRunning else {
            TKLogger.log(.syncEngine, level: .debug,
                         message: "Operation execution aborted due to stop signal.")
            return
        }
        
        switch response {
        case .send(let response):
            handleSendOperationResponse(response)
        case .fetch(let response):
            handleFetchOperationResponse(response)
        default:
            break
        }
    }
    
    private func handleSendOperationResponse(_ response: TKSendOperation.Response) {
        delegate?.syncEngine(self, didSendModifications: response.modifiedRecords.map { TKRecord(from: $0) })
        delegate?.syncEngine(self, didSendDeletions: response.deletedIDs.map(\.recordName))
        
        if !response.conflictingIDs.isEmpty {
            let resolvedRecords = resolveConflicts(for: response.conflictingIDs)
            let newOperation = TKSendOperation(modifications: resolvedRecords, deletions: [])
            dispatch(event: .operationReplaced(with: [.send(newOperation)]))
        }
        
        if !response.failedIDs.isEmpty {
            let failures = response.failedIDs.reduce(into: [:]) { result, item in
                result[item.key.recordName] = item.value
            }
            delegate?.syncEngine(self, sendDidFailFor: failures)
        }
    }
    
    private func resolveConflicts(for conflicts: [CKRecord.ID: Error]) -> [CKRecord] {
        var resolvedRecords = [CKRecord]()
        
        for (id, error) in conflicts {
            guard let ckError = error as? CKError,
                  ckError.code == .serverRecordChanged,
                  let serverRecord = ckError.serverRecord,
                  let clientRecord = ckError.clientRecord else {
                TKLogger.log(.syncEngine, level: .error,
                             message: "Failed to process conflicting record with ID: \(id.recordName)")
                continue
            }
            
            let chosenRecord = delegate?.syncEngine(
                self, shouldResolveConflict: (clientRecord, serverRecord)
            ) ?? clientRecord
            
            if chosenRecord == serverRecord {
                resolvedRecords.append(serverRecord)
            } else {
                serverRecord.clearFields()
                serverRecord.copyFields(from: chosenRecord)
                resolvedRecords.append(serverRecord)
            }
        }
        
        return resolvedRecords
    }
    
    private func handleFetchOperationResponse(_ response: TKFetchOperation.Response) {
        delegate?.syncEngine(self, didUpdateChangeToken: response.changeToken)
        
        let deletions = response.deletions.map { ($0.recordID.recordName, $0.recordType) }
        delegate?.syncEngine(self, didFetchDeletions: deletions)
        
        let rawModifications = response.modifications
        var modifications = [TKRecord]()
        var failures = [String: Error]()
        
        for (id, result) in rawModifications {
            switch result {
            case .success(let modification):
                modifications.append(TKRecord(from: modification.record))
            case .failure(let error):
                failures[id.recordName] = error
            }
        }
        
        delegate?.syncEngine(self, didFetchModifications: modifications)
        
        if !failures.isEmpty {
            delegate?.syncEngine(self, fetchDidFailFor: failures)
            
            TKLogger.log(
                .syncEngine,
                level: .error,
                message: "Failed to fetch \(failures.count) modifications"
            )
        }
    }
    
    private func handleFailure(_ error: Error) async {
        guard state.isRunning else {
            TKLogger.log(.syncEngine, level: .debug,
                         message: "Operation execution aborted due to stop signal.")
            return
        }
        
        guard let error = error as? CKError else {
            dispatch(event: .stop(error))
            return
        }
        
        switch error.code {
        case .internalError,
                .badContainer,
                .badDatabase,
                .missingEntitlement,
                .notAuthenticated,
                .permissionFailure,
                .invalidArguments,
                .serverRejectedRequest,
                .incompatibleVersion,
                .constraintViolation,
                .referenceViolation,
                .batchRequestFailed,
                .quotaExceeded,
                .managedAccountRestricted:
            dispatch(event: .stop(error))
        case .networkUnavailable,
                .networkFailure,
                .serviceUnavailable,
                .zoneBusy,
                .requestRateLimited,
                .serverResponseLost:
            dispatch(event: .operationRetry(error))
        case .zoneNotFound, .userDeletedZone:
            dispatch(event: .operationEnqueued(.createZone(zoneID)))
            dispatch(event: .operationEnqueued(.subscribe(.init(zoneID: zoneID, subscriptionID: subscriptionID))))
        case .changeTokenExpired:
            switch state.currentOperation {
            case .fetch:
                delegate?.syncEngine(self, didUpdateChangeToken: nil)
                dispatch(event: .operationReplaced(with: [.fetch(.init(changeToken: nil))]))
            default:
                dispatch(event: .stop(error))
            }
        case .limitExceeded:
            switch state.currentOperation {
            case .send(let operation):
                guard operation.modifications.count > 1 else {
                    dispatch(event: .stop(error))
                    return
                }
                
                let (modifications1, modifications2) = operation.modifications.halved()
                let (deletions1, deletions2) = operation.deletions.halved()
                let firstHalf = TKOperation.send(.init(modifications: modifications1, deletions: deletions1))
                let secondHalf = TKOperation.send(.init(modifications: modifications2, deletions: deletions2))
                dispatch(event: .operationReplaced(with: [secondHalf, firstHalf]))
            default:
                dispatch(event: .stop(error))
            }
        case .accountTemporarilyUnavailable:
            dispatch(event: .accountStatusChanged(.temporarilyUnavailable))
        case .unknownItem,
                .assetFileNotFound,
                .assetFileModified,
                .assetNotAvailable,
                .serverRecordChanged:
            TKLogger.log(
                .syncEngine,
                level: .fault,
                message:
                    "Encountered error '\(error)' which is expected to occur in per record results. Please investigate."
            )
            dispatch(event: .stop(error))
        case .resultsTruncated,
                .partialFailure,
                .tooManyParticipants,
                .alreadyShared,
                .participantMayNeedVerification,
                .operationCancelled:
            TKLogger.log(
                .syncEngine,
                level: .fault,
                message: "Encountered error '\(error)' which should not normally happen. Please investigate."
            )
            dispatch(event: .stop(error))
        default:
            TKLogger.log(
                .syncEngine,
                level: .fault,
                message: "Encountered unknown error '\(error)'. Please investigate."
            )
            dispatch(event: .stop(error))
        }
    }
    
    private func scheduleRetry(_ ckError: CKError) async {
        guard state.retryCount < maxRetryAttempts else {
            dispatch(event: .stop(ckError))
            return
        }
        
        Task(priority: .background) {
            guard let operation = state.currentOperation else { return }
            
            if let delay = ckError.retryAfterSeconds {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            
            await perform(operation)
        }
    }
}
