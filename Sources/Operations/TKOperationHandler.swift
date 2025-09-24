//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import CloudKit

/// A class that handles all communications with iCloud and regulates the execution of operations.
final class TKOperationHandler: Sendable {
    private let container: CKContainer
    private let savePolicy: CKModifyRecordsOperation.RecordSavePolicy
    private let queue = TKOperationQueue()
    private let throttle: Throttle
    
    private var database: CKDatabase { container.privateCloudDatabase }
    
    init(configuration: TKSyncEngineConfiguration) {
        if let containerID = configuration.containerID {
            container = CKContainer(identifier: containerID)
        } else {
            container = .default()
        }
        throttle = .init(
            min: configuration.minOperationThrottle,
            max: configuration.maxOperationThrottle
        )
        savePolicy = configuration.recordSavePolicy
    }
    
    // MARK: Operations
    func fetch(
        _ operation: TKFetchOperation, zoneID: CKRecordZone.ID
    ) async -> Result<TKFetchOperation.Response, Error> {
        await enqueue {
            do {
                let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: operation.changeToken)
                
                TKLogger.log(.operationHandler, message: "Fetch operation succeeded")
                await throttle.adjust()
                return .success(
                    TKFetchOperation.Response(
                        modifications: result.modificationResultsByID,
                        deletions: result.deletions,
                        changeToken: result.changeToken,
                        moreComing: result.moreComing
                    )
                )
            } catch {
                TKLogger.log(.operationHandler, level: .error, message: "Fetch operation failed: \(error)")
                await throttle.adjust(for: error)
                return .failure(error)
            }
        }
    }
    
    func send(_ operation: TKSendOperation) async -> Result<TKSendOperation.Response, Error> {
        await enqueue {
            do {
                let (rawModified, rawDeleted) = try await database.modifyRecords(
                    saving: operation.modifications,
                    deleting: operation.deletions,
                    savePolicy: savePolicy
                )
                
                var modifiedRecords = [CKRecord]()
                var deletedIDs = [CKRecord.ID]()
                var conflictingIDs = [CKRecord.ID: Error]()
                var failedIDs = [CKRecord.ID: Error]()
                
                for (recordID, result) in rawModified {
                    switch result {
                    case .success(let record):
                        modifiedRecords.append(record)
                    case .failure(let error):
                        if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                            conflictingIDs[recordID] = error
                        } else {
                            failedIDs[recordID] = error
                        }
                    }
                }
                
                for (recordID, result) in rawDeleted {
                    switch result {
                    case .success:
                        deletedIDs.append(recordID)
                    case .failure(let error):
                        failedIDs[recordID] = error
                    }
                }
                
                TKLogger.log(.operationHandler, message: "Send operation succeeded")
                await throttle.adjust()
                return .success(TKSendOperation.Response(
                    modifiedRecords: modifiedRecords,
                    deletedIDs: deletedIDs,
                    conflictingIDs: conflictingIDs,
                    failedIDs: failedIDs
                ))
            } catch {
                TKLogger.log(.operationHandler, level: .error, message: "Send operation failed: \(error)")
                await throttle.adjust(for: error)
                return .failure(error)
            }
        }
    }
    
    func createZone(with zoneID: CKRecordZone.ID) async -> Result<Bool, Error> {
        do {
            let isAlreadyCreated = try await enqueue {
                do {
                    _ = try await database.recordZone(for: zoneID)
                    TKLogger.log(.operationHandler, message: "Zone already exists")
                    return true
                } catch CKError.zoneNotFound, CKError.userDeletedZone, CKError.unknownItem {
                    return false
                }
            }
            
            await throttle.adjust()
            
            if isAlreadyCreated {
                TKLogger.log(.operationHandler, message: "Create zone operation succeeded")
                return .success(true)
            }
            
            return try await enqueue {
                try await database.save(CKRecordZone(zoneID: zoneID))
                
                TKLogger.log(.operationHandler, message: "Create zone operation succeeded")
                await throttle.adjust()
                return .success(true)
            }
        } catch {
            TKLogger.log(.operationHandler, message: "Create zone operation failed: \(error)")
            await throttle.adjust(for: error)
            return .failure(error)
        }
    }
    
    func subscribe(_ operation: TKSubscribeOperation) async -> Result<Bool, Error> {
        do {
            let isAlreadySubscribed = try await enqueue {
                do {
                    _ = try await database.subscription(for: operation.subscriptionID)
                    TKLogger.log(.operationHandler, message: "Subscription already exists")
                    return true
                } catch CKError.zoneNotFound, CKError.userDeletedZone, CKError.unknownItem {
                    return false
                }
            }
            
            await throttle.adjust()
            
            if isAlreadySubscribed {
                TKLogger.log(.operationHandler, message: "Subscribe operation succeeded")
                return .success(true)
            }
            
            return try await enqueue {
                let subscription = CKRecordZoneSubscription(
                    zoneID: operation.zoneID, subscriptionID: operation.subscriptionID
                )
                let notificationInfo = CKSubscription.NotificationInfo()
                notificationInfo.shouldSendContentAvailable = true
                subscription.notificationInfo = notificationInfo
                
                try await database.save(subscription)
                
                TKLogger.log(.operationHandler, message: "Subscribe operation succeeded")
                await throttle.adjust()
                return .success(true)
            }
        } catch {
            TKLogger.log(.operationHandler, message: "Subscribe operation failed: \(error)")
            await throttle.adjust(for: error)
            return .failure(error)
        }
    }
    
    // MARK: Enqueue operations
    private func enqueue<Value: Sendable>(_ operation: @Sendable () async throws -> Value) async rethrows -> Value {
        let now = DispatchTime.now()
        let next = await throttle.nextOperationDeadline
        
        if now < next {
            let sleepNanoseconds = next.uptimeNanoseconds - now.uptimeNanoseconds
            try? await Task.sleep(nanoseconds: sleepNanoseconds)
        }
        
        return try await queue.run {
            try await operation()
        }
    }
}

// MARK: - Throttle
extension TKOperationHandler {
    /// This actor isolates the mutable state of ``TKOperationHandler``.
    private actor Throttle {
        private let minThrottle: TimeInterval
        private let maxThrottle: TimeInterval
        
        var currentThrottle: TimeInterval
        var nextOperationDeadline: DispatchTime = .now()
        
        init(min: TimeInterval, max: TimeInterval) {
            self.minThrottle = min
            self.maxThrottle = max
            self.currentThrottle = min
        }
        
        func adjust(for error: Error? = nil) {
            let previousThrottle = currentThrottle
            
            if let error {
                guard let error = error as? CKError else { return }
                
                currentThrottle = error.retryAfterSeconds ?? min(currentThrottle * 2, maxThrottle)
                
                if currentThrottle != previousThrottle {
                    let messsage = "Throttling increased to \(currentThrottle) seconds. Error code: \(error.code)"
                    TKLogger.log(.operationHandler, message: messsage)
                }
            } else {
                currentThrottle = max(currentThrottle / 2, minThrottle)
                
                if currentThrottle != previousThrottle {
                    TKLogger.log(.operationHandler, message: "Throttling decreased to \(currentThrottle) seconds")
                }
            }
            
            nextOperationDeadline = .now() + currentThrottle
        }
    }
}
