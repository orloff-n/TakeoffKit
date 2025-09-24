//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import CloudKit

/// A persistent data model that can be synced with CloudKit.
///
/// Types conforming to the this protocol can be converted to `CKRecord`
/// for synchronization with ``TKSyncEngine``.
///
/// ## Example
/// A Realm data model:
///
/// ```swift
/// final class Folder: TKSyncable {
///     @Persisted(primaryKey: true) var id: ObjectId
///     @Persisted var index: Int
///     @Persisted var name: String
///     @Persisted(originProperty: "folder") var accounts: LinkingObjects<Account>
///
///     // TKSyncable conformance:
///     @Persisted var tkMetadata: Data?
///     var tkRecordID: String { id.stringValue }
///     var tkProperties: [String: TKSyncableValue] { [
///         "index": .value(index),
///         "name": .encryptedValue(name)
///     ] }
/// }
/// ```
///
/// > SeeAlso: ``TKRecord`` for updating existing data models.
public protocol TKSyncable {
    /// CloudKit record type name associated with the data model.
    ///
    /// Specifies the `recordType` of `CKRecord` instances created from a ``TKSyncable`` type.
    /// By default, returns the name of the conforming type, but can be overridden to provide
    /// a custom name.
    ///
    /// ## Examples
    /// - `"Note"`
    /// - `"Folder"`
    /// - `"Account"`
    static var tkRecordType: String { get }
    
    /// A stable and unique identifier for each CloudKit record.
    ///
    /// Specifies the `CKRecord.ID` of a `CKRecord` created from a ``TKSyncable`` instance.
    /// This value must be unique and immutable. Ideally, it should be a string representation of
    /// a `UUID` or Realm's `ObjectId`.
    ///
    /// > Important:
    /// > It is strongly recommended that this identifier reference an existing unique identifier
    /// > stored within the data model. You will need it to match fetched CloudKit records with
    /// > their local counterparts.
    var tkRecordID: String { get }
    
    /// Data model properties to be synced with CloudKit.
    ///
    /// A dictionary representation of the data model's properties used for `CKRecord` conversion.
    ///
    /// ### Keys
    /// Keys correspond to CloudKit record field names. Each key:
    /// - Must **not** begin with an underscore (`_`)
    /// - Can contain only ASCII letters, numbers and the underscore character
    /// - Must be **no longer than** 255 characters
    ///
    /// > Warning: Failure to meet these requirements will result in an exception.
    ///
    /// ### Values
    /// Values are wrapped in ``TKSyncableValue`` for convenience and type safety.
    ///
    /// ## Example
    /// ```swift
    /// var tkProperties: [String: TKSyncableValue] { [
    ///     "index": .value(index),
    ///     "folder": .reference(folder, onReferenceDeleted: .noAction),
    ///     "icon": .asset(fileURL: iconURL),
    ///     "note": .encryptedValue(note),
    ///     "type": .encryptedValue(type.rawValue) // Enum
    /// ] }
    /// ```
    var tkProperties: [String: TKSyncableValue] { get }
    
    /// CloudKit record metadata that needs to be persisted.
    ///
    /// Contains encoded `CKRecord` system fields such as `recordChangeTag` and
    /// `modificationDate`, which are essential for change tracking and conflict resolution.
    /// Since these fields are managed exclusively by CloudKit, any record modifications require
    /// initializing the record with the metadata from its last known version in order for iCloud to
    /// accept the changes.
    ///
    /// > Important:
    /// > This value must be nil when a new instance is first created. Then you should update and
    /// persist this metadata whenever records are fetched or modified.
    ///
    /// > Warning:
    /// > Missing or outdated metadata will cause all subsequent modifications to fail with
    /// > `serverRecordChanged` error, as iCloud will treat them as conflicts.
    ///
    /// To keep the metadata up-to-date:
    /// 1. Implement ``TKSyncEngineDelegate`` methods:
    ///    - ``TKSyncEngineDelegate/syncEngine(_:didFetchModifications:)``
    ///    - ``TKSyncEngineDelegate/syncEngine(_:didSendModifications:)``
    /// 2. Lookup the corresponding ``TKSyncable`` instance for each ``TKRecord`` by its identifier
    /// 3. Assign record's ``TKRecord/metadata`` to this property
    /// 4. Persist the changes to your local database
    var tkMetadata: Data? { get set }
}

public extension TKSyncable {
    static var tkRecordType: String { "\(Self.self)" }
}

// MARK: - Internal
extension TKSyncable {
    func convertToCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let record = restoreOrCreateRecord(zoneID: zoneID)
        
        for (key, value) in tkProperties {
            switch value {
            case .value(let value):
                record[key] = value
            case .encryptedValue(let value):
                record.encryptedValues[key] = value
            case .asset(let fileURL):
                record[key] = fileURL.map(CKAsset.init)
            case .reference(let referencedObject, let deleteAction):
                record[key] = referencedObject.map {
                    CKRecord.Reference(
                        recordID: CKRecord.ID(recordName: $0.tkRecordID),
                        action: deleteAction.referenceAction
                    )
                }
            }
        }
        
        return record
    }
    
    private func restoreOrCreateRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        if let metadata = tkMetadata,
           let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: metadata) {
            unarchiver.requiresSecureCoding = true
            if let restoredRecord = CKRecord(coder: unarchiver) {
                return restoredRecord
            }
        }
        
        let recordID = CKRecord.ID(recordName: tkRecordID, zoneID: zoneID)
        return CKRecord(recordType: Self.tkRecordType, recordID: recordID)
    }
}
