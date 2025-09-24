//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import CloudKit

/// An interface for receiving data from the sync engine.
@MainActor
public protocol TKSyncEngineDelegate: AnyObject {
    /// Represents a deleted record with its identifier and type information.
    typealias TKDeletion = (recordID: String, recordType: String)
    
    /// Represents a synchronization conflict between client and server versions of a record.
    typealias TKConflict = (clientRecord: CKRecord, serverRecord: CKRecord)
    
    /// Called when the iCloud account status changes.
    /// - Parameters:
    ///   - engine: The sync engine.
    ///   - accountStatus: The new iCloud account status.
    func syncEngine(_ engine: TKSyncEngine, didChangeAccountStatus accountStatus: CKAccountStatus)
    
    /// Called when the sync engine stops after encountering an unrecoverable error or reaching the retry limit.
    /// - Parameters:
    ///   - engine: The sync engine.
    ///   - error: The error that caused the engine to stop.
    func syncEngine(_ engine: TKSyncEngine, didStopWithError error: Error)
    
    /// Called when the server change token is updated after a successful fetch operation.
    /// - Parameters:
    ///   - engine: The sync engine.
    ///   - changeToken: The new server change token, or `nil` if expired.
    func syncEngine(_ engine: TKSyncEngine, didUpdateChangeToken changeToken: CKServerChangeToken?)
    
    /// Called when modified records are successfully fetched from iCloud.
    /// - Parameters:
    ///   - engine: The sync engine.
    ///   - modifications: An array of modified records.
    ///
    /// > Important: You should persist ``TKRecord/metadata`` for each record when this method is called.
    func syncEngine(_ engine: TKSyncEngine, didFetchModifications modifications: [TKRecord])
    
    /// Called when deleted records are successfully fetched from iCloud.
    /// - Parameters:
    ///   - engine: The sync engine.
    ///   - deletions: An array of deletions, each containing a record ID and a record type.
    func syncEngine(_ engine: TKSyncEngine, didFetchDeletions deletions: [TKDeletion])
    
    /// Called when fetching specific records fails.
    /// - Parameters:
    ///   - engine: The sync engine.
    ///   - failedIDs: A dictionary mapping record IDs to their corresponding errors.
    func syncEngine(_ engine: TKSyncEngine, fetchDidFailFor failedIDs: [String: Error])
    
    /// Called when local modifications are successfully sent to iCloud.
    /// - Parameters:
    ///   - engine: The sync engine.
    ///   - modifiedRecords: An array of modified records.
    ///
    /// > Important: You should persist ``TKRecord/metadata`` for each record when this method is called.
    func syncEngine(_ engine: TKSyncEngine, didSendModifications modifiedRecords: [TKRecord])
    
    /// Called when local deletions are successfully sent to iCloud.
    /// - Parameters:
    ///   - engine: The sync engine.
    ///   - deletedIDs: An array of deleted IDs.
    ///
    /// > CloudKit APIs do not provide deleted records types.
    func syncEngine(_ engine: TKSyncEngine, didSendDeletions deletedIDs: [String])
    
    /// Called when sending specific records fails.
    /// - Parameters:
    ///   - engine: The sync engine.
    ///   - failedIDs: A dictionary mapping record IDs to their corresponding errors.
    func syncEngine(_ engine: TKSyncEngine, sendDidFailFor failedIDs: [String: Error])
    
    /// Called when a conflict is detected between client and server versions of a record.
    /// You must return the record that should be used.
    /// - Parameters:
    ///   - engine: The sync engine.
    ///   - conflict: A tuple containing the client and server versions of the conflicting record.
    /// - Returns: The record that should be used to resolve the conflict
    /// (may be one of the provided records or a merged version).
    func syncEngine(_ engine: TKSyncEngine, shouldResolveConflict conflict: TKConflict) -> CKRecord
}
