//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import XCTest
@testable import TakeoffKit

final class TKOperationQueueTests: XCTestCase {
    func testSingleConcurrentOperation() async {
        let queue = TKOperationQueue(maxConcurrentOperationCount: 1)
        let testStartTime = Date()
        let operationDuration: TimeInterval = 0.1
        
        await withTaskGroup(of: TimeInterval.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    await queue.run {
                        let operationStartTime = Date()
                        try? await Task.sleep(nanoseconds: UInt64(operationDuration * 1_000_000_000))
                        return operationStartTime.timeIntervalSince(testStartTime)
                    }
                }
            }
        }
        
        let totalTestDuration = Date().timeIntervalSince(testStartTime)
        let expectedMinDuration = operationDuration * 5
        XCTAssertGreaterThanOrEqual(totalTestDuration, expectedMinDuration)
    }
    
    func testThreeConcurrentOperations() async {
        let queue = TKOperationQueue(maxConcurrentOperationCount: 3)
        let testStartTime = Date()
        let operationDuration: TimeInterval = 0.2
        
        await withTaskGroup(of: TimeInterval.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    await queue.run {
                        let operationStartTime = Date()
                        try? await Task.sleep(nanoseconds: UInt64(operationDuration * 1_000_000_000))
                        return operationStartTime.timeIntervalSince(testStartTime)
                    }
                }
            }
        }
        
        let totalTestDuration = Date().timeIntervalSince(testStartTime)
        let expectedMinDuration = operationDuration * 2
        let expectedMaxDuration = operationDuration * 3
        
        XCTAssertGreaterThanOrEqual(totalTestDuration, expectedMinDuration)
        XCTAssertLessThan(totalTestDuration, expectedMaxDuration)
    }
}
