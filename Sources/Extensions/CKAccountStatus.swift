//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import CloudKit

extension CKAccountStatus: @retroactive CustomDebugStringConvertible {
    /// A string representation of `CKAccountStatus` useful for logging.
    public var debugDescription: String {
        switch self {
        case .available:
            "Available"
        case .couldNotDetermine:
            "Could not determine"
        case .noAccount:
            "No account"
        case .restricted:
            "Restricted"
        case .temporarilyUnavailable:
            "Temporarily unavailable"
        @unknown default:
            "Unknown"
        }
    }
}
