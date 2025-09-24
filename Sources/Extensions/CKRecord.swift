//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import CloudKit

extension CKRecord {
    /// Clears all record fields.
    func clearFields() {
        encryptedValues.allKeys().forEach { encryptedValues[$0] = nil }
        allKeys().forEach { self[$0] = nil }
    }
    
    /// Copies the fields from another record into the record.
    func copyFields(from record: CKRecord) {
        let encryptedKeys = Set(record.encryptedValues.allKeys())
        let regularKeys = record.allKeys().filter { !encryptedKeys.contains($0) }
        encryptedKeys.forEach { encryptedValues[$0] = record.encryptedValues[$0] }
        regularKeys.forEach { self[$0] = record[$0] }
    }
}
