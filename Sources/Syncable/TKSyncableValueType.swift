//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import CloudKit

/// A type that can be stored as a `CKRecord` value.
///
/// Types conforming to the ``TKSyncableValueType`` protocol are compatible with CloudKit synchronization
/// and can be used as associated values in ``TKSyncableValue/value(_:)`` and ``TKSyncableValue/encryptedValue(_:)``.
///
/// > Note:
/// > This protocol does not include `CKAsset` and `CKRecord.Reference`, although they are compatible.
/// > For assets and references, use ``TKSyncableValue/asset(fileURL:)`` and
/// > ``TKSyncableValue/reference(_:onReferenceDeleted:)`` respectively.
public protocol TKSyncableValueType: CKRecordValueProtocol {}

extension Bool: TKSyncableValueType {}
extension Int: TKSyncableValueType {}
extension Int8: TKSyncableValueType {}
extension Int16: TKSyncableValueType {}
extension Int32: TKSyncableValueType {}
extension Int64: TKSyncableValueType {}
extension UInt: TKSyncableValueType {}
extension UInt8: TKSyncableValueType {}
extension UInt16: TKSyncableValueType {}
extension UInt32: TKSyncableValueType {}
extension UInt64: TKSyncableValueType {}
extension Float: TKSyncableValueType {}
extension Double: TKSyncableValueType {}
extension NSNumber: TKSyncableValueType {}
extension String: TKSyncableValueType {}
extension NSString: TKSyncableValueType {}
extension Date: TKSyncableValueType {}
extension NSDate: TKSyncableValueType {}
extension Data: TKSyncableValueType {}
extension NSData: TKSyncableValueType {}
extension CLLocation: TKSyncableValueType {}
extension Array: TKSyncableValueType where Element: TKSyncableValueType {}
