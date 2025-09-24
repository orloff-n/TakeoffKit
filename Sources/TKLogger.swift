//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import OSLog

/// A custom logger for this library.
enum TKLogger {
    /// Each category represents the part of the library that is the source of the log message.
    enum Category: String {
        case syncEngine = "SyncEngine"
        case operationHandler = "OperationHandler"
    }
    
    /// A common subsystem for the whole library.
    private static let subsystem = "orloffn.takeoffkit"
    
    /// Logs the message adding a formatted category, date and time to make it much more useful in the Xcode console.
    static func log(_ category: Category, level: OSLogType = .debug, message: String) {
        let date = Date().formatted(date: .omitted, time: .standard)
        Logger(subsystem: subsystem, category: category.rawValue)
            .log(level: level, "[\(date) – \(category.rawValue)] \(message)")
    }
}
