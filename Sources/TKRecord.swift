//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import CloudKit

/// A convenient wrapper for records received from CloudKit.
///
/// `TKRecord` encapsulates data from a `CKRecord` in a format optimized for updating local
/// data model instances. It combines both regular and encrypted record properties into a single dictionary
/// and encodes record's system fields as a `Data` object, reducing boilerplate and making
/// ``TKSyncable`` instance updates almost effortless.
///
/// These records are delivered through ``TKSyncEngineDelegate`` methods such as
/// ``TKSyncEngineDelegate/syncEngine(_:didFetchModifications:)`` and
/// ``TKSyncEngineDelegate/syncEngine(_:didSendModifications:)``.
///
/// > SeeAlso: ``TKSyncable`` for data model requirements.
public struct TKRecord {
    /// CloudKit record type name.
    ///
    /// Mirrors the `recordType` property of the original `CKRecord` and matches the
    /// ``TKSyncable/tkRecordType`` of the associated data model.
    ///
    /// Use this value to determine the type of local object to update or create.
    public let type: String
    
    /// The unique identifier of the CloudKit record.
    ///
    /// Corresponds to the `recordName` of the original `CKRecord.ID` and matches the
    /// ``TKSyncable/tkRecordID`` of the associated data model.
    ///
    /// Use this identifier to retrieve the corresponding local object from your database for updates.
    /// If no object is found, create a new instance with this identifier.
    public let id: String
    
    /// A dictionary containing all CloudKit record field values.
    ///
    /// Combines both regular and encrypted fields from the original `CKRecord` into a single dictionary
    /// for convenient access. The keys in this dictionary correspond to the field names provided in the
    /// ``TKSyncable/tkProperties`` of the associated data model.
    ///
    /// You need to cast the values to the appropriate types as defined in your data model.
    public let properties: [String: Any]
    
    /// Encoded system fields of a CloudKit record.
    ///
    /// > Important: See ``TKSyncable/tkMetadata`` for important details regarding this property.
    public let metadata: Data
    
    /// Initializes the object from a `CKRecord`
    init(from record: CKRecord) {
        type = record.recordType
        id = record.recordID.recordName
        
        let encryptedKeys = Set(record.encryptedValues.allKeys())
        let regularKeys = record.allKeys().filter { !encryptedKeys.contains($0) }
        var result: [String: Any] = record.dictionaryWithValues(forKeys: regularKeys)
        encryptedKeys.forEach { key in
            result[key] = record.encryptedValues[key]
        }
        properties = result
        
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        metadata = archiver.encodedData
    }
}
