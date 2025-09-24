//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

/// A queue that manages concurrent async tasks with a limit on simultaneous execution.
actor TKOperationQueue {
    private let maxConcurrentOperationCount: Int
    private var operationCount = 0
    private var queue = [CheckedContinuation<Void, Never>]()
    
    init(maxConcurrentOperationCount: Int = 1) {
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
    }
    
    func run<Value: Sendable>(_ operation: @Sendable () async throws -> Value) async rethrows -> Value {
        await hold()
        
        do {
            let result = try await operation()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }
    
    private func hold() async {
        if operationCount < maxConcurrentOperationCount {
            operationCount += 1
            return
        }
        
        await withCheckedContinuation { continuation in
            queue.append(continuation)
        }
    }
    
    private func release() {
        operationCount -= 1
        
        if !queue.isEmpty {
            operationCount += 1
            queue.removeFirst().resume()
        }
    }
}
