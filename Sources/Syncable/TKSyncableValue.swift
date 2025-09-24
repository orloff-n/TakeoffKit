//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import CloudKit

/// A type-safe wrapper for syncing data model properties with CloudKit.
public enum TKSyncableValue {
    /// Constants that indicate the behavior when deleting a referenced record.
    ///
    /// A wrapper for `CKRecord.ReferenceAction` to eliminate the need for importing CloudKit
    /// just for a single enumeration.
    public enum DeleteAction {
        /// When the referenced record is deleted, this record remains unchanged and contains a dangling pointer
        case noAction
        
        /// When the referenced record is deleted, this record is also deleted
        case deleteSelf
        
        /// The case mapped to `CKRecord.ReferenceAction`.
        var referenceAction: CKRecord.ReferenceAction {
            switch self {
            case .noAction:
                    .none
            case .deleteSelf:
                    .deleteSelf
            }
        }
    }
    
    /// A value that will be synced with CloudKit without end-to-end encryption.
    ///
    /// The associated value type must conform to ``TKSyncableValueType`` to ensure CloudKit compatibility.
    ///
    /// > SeeAlso: ``TKSyncableValueType`` for the complete list of types supported by CloudKit.
    case value(TKSyncableValueType?)
    
    /// A value that will be synced with CloudKit using end-to-end encryption.
    ///
    /// The associated value type must conform to ``TKSyncableValueType`` to ensure CloudKit compatibility.
    ///
    /// > SeeAlso: ``TKSyncableValueType`` for the complete list of types supported by CloudKit.
    case encryptedValue(TKSyncableValueType?)
    
    /// A file asset that will be uploaded to CloudKit as a `CKAsset`.
    ///
    /// Use this case for any data large enough to be stored as an asset rather than a direct value.
    case asset(fileURL: URL?)
    
    /// A reference to another ``TKSyncable`` instance.
    ///
    /// Use this case to create relationships between model instances, similar to foreign keys
    /// in relational databases. The reference will be stored as a `CKRecord.Reference`.
    ///
    /// > Note: References do not support CloudKit end-to-end encryption.
    case reference(TKSyncable?, onReferenceDeleted: DeleteAction)
}
