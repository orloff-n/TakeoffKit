//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import CloudKit

/// The events that the sync engine reacts to.
enum TKSyncEngineEvent: CustomDebugStringConvertible {
    /// Starts the engine.
    case start
    
    /// Stops the engine.
    case stop(Error? = nil)
    
    /// Signals a change of the iCloud account status.
    case accountStatusChanged(CKAccountStatus)
    
    /// Adds an operation to the queue.
    case operationEnqueued(TKOperation)
    
    /// Indicates that the current operation has succeeded and returns its response.
    case operationSucceeded(TKOperation.Response)
    
    /// Indicates that the current operation has failed and returns the error.
    case operationFailed(Error)
    
    /// Indicates that the current operation should be scheduled for retry.
    case operationRetry(CKError)
    
    /// Replaces the current operation with other operation(s).
    case operationReplaced(with: [TKOperation])
    
    /// A string representation of the event useful for logging.
    var debugDescription: String {
        switch self {
        case .start:
            "Start"
        case .stop(let error):
            "Stop (\(error?.localizedDescription ?? "by request"))"
        case .accountStatusChanged(let status):
            "Account status changed (\(status.debugDescription))"
        case .operationEnqueued(let operation):
            "Operation added to queue (\(operation.debugDescription))"
        case .operationSucceeded(let response):
            "Operation succeeded (\(response.debugDescription))"
        case .operationFailed(let error):
            "Operation failed (\(error.localizedDescription))"
        case .operationRetry(let ckError):
            "Operation will be retried in \(ckError.retryAfterSeconds ?? 0) seconds"
        case .operationReplaced(let operations):
            "Operation replaced with \(operations.count) operation(s)"
        }
    }
}
