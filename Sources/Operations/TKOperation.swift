//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import CloudKit

/// A type-safe wrapper for operations.
enum TKOperation: Equatable, CustomDebugStringConvertible {
    /// A type-safe wrapper for responses that operations return.
    enum Response: CustomDebugStringConvertible {
        case createZone(Bool)
        case subscribe(Bool)
        case send(TKSendOperation.Response)
        case fetch(TKFetchOperation.Response)
        
        var debugDescription: String {
            switch self {
            case .createZone(let success):
                success ? "Created zone" : "Failed to create zone"
            case .subscribe(let success):
                success ? "Subscribed" : "Failed to subscribe"
            case .send(let response):
                response.debugDescription
            case .fetch(let response):
                response.debugDescription
            }
        }
    }
    
    case createZone(CKRecordZone.ID)
    case subscribe(TKSubscribeOperation)
    case send(TKSendOperation)
    case fetch(TKFetchOperation)
    
    var debugDescription: String {
        switch self {
        case .createZone(let zoneID):
            "Create zone '\(zoneID.zoneName)'"
        case .subscribe(let operation):
            operation.debugDescription
        case .send(let operation):
            operation.debugDescription
        case .fetch:
            "Fetch"
        }
    }
}

/// The protocol that all operation structs must conform to.
protocol TKOperationProtocol: Equatable {
    var id: UUID { get }
}

/// A representation of "create subscription" operation.
struct TKSubscribeOperation: TKOperationProtocol, CustomDebugStringConvertible {
    let id = UUID()
    let zoneID: CKRecordZone.ID
    let subscriptionID: String
    
    var debugDescription: String {
        "Subscribe to zone '\(zoneID.zoneName)' with subscription ID '\(subscriptionID)'"
    }
}

/// A representation of "send changes" operation.
struct TKSendOperation: TKOperationProtocol, CustomDebugStringConvertible {
    /// Returns modifications, deletions, IDs that triggered a `serverRecordChanged` error (conflicts)
    /// and IDs that triggered other errors.
    struct Response: CustomDebugStringConvertible {
        let modifiedRecords: [CKRecord]
        let deletedIDs: [CKRecord.ID]
        let conflictingIDs: [CKRecord.ID: Error]
        let failedIDs: [CKRecord.ID: Error]
        
        var debugDescription: String {
            let conflicts = conflictingIDs.isEmpty ? "" : ", \(conflictingIDs.count) conflicts"
            let failures = failedIDs.isEmpty ? "" : ", \(failedIDs.count) failed (error != serverRecordChanged)"
            return "Modified \(modifiedRecords.count) records, deleted \(deletedIDs.count) records"
            + conflicts + failures
        }
    }
    
    let id = UUID()
    let modifications: [CKRecord]
    let deletions: [CKRecord.ID]
    
    var debugDescription: String {
        "Modify \(modifications.count) records, delete \(deletions.count) records"
    }
}

/// A representation of "fetch changes" operation.
struct TKFetchOperation: TKOperationProtocol {
    /// Returns modifications, deletions, a change token and a `moreComing` flag if the response is not complete.
    struct Response: CustomDebugStringConvertible {
        let modifications: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, Error>]
        let deletions: [CKDatabase.RecordZoneChange.Deletion]
        let changeToken: CKServerChangeToken
        let moreComing: Bool
        
        var debugDescription: String {
            let more = moreComing ? " (more coming)" : ""
            return "Fetched \(modifications.count) records to save, \(deletions.count) records to delete" + more
        }
    }
    
    let id = UUID()
    let changeToken: CKServerChangeToken?
}
