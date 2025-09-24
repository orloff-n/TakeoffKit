//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import XCTest
import CloudKit
@testable import TakeoffKit

final class TKSyncStateQueueTests: XCTestCase, @unchecked Sendable {
    @MainActor var syncState = TKSyncEngineState()
    
    func testQueuePriority() async throws {
        await syncState.update(with: .start)
        await syncState.update(with: .accountStatusChanged(.available))
        
        let fetchOp = TKFetchOperation(changeToken: nil)
        let sendOp = TKSendOperation(modifications: [], deletions: [])
        let subscribeOp = TKSubscribeOperation(zoneID: CKRecordZone.ID(zoneName: "TestZone"), subscriptionID: "test")
        let createZoneOp = CKRecordZone.ID(zoneName: "TestZone")
        
        await syncState.update(with: .operationEnqueued(.fetch(fetchOp)))
        await syncState.update(with: .operationEnqueued(.send(sendOp)))
        await syncState.update(with: .operationEnqueued(.subscribe(subscribeOp)))
        await syncState.update(with: .operationEnqueued(.createZone(createZoneOp)))
        
        let currentQueue1 = await syncState.currentQueue
        XCTAssertEqual(currentQueue1, .createZone)
        
        await syncState.update(with: .operationSucceeded(.createZone(true)))
        
        let currentQueue2 = await syncState.currentQueue
        XCTAssertEqual(currentQueue2, .subscribe)
        
        await syncState.update(with: .operationSucceeded(.subscribe(true)))
        
        let currentQueue3 = await syncState.currentQueue
        XCTAssertEqual(currentQueue3, .send)
        
        let sendResponse = TKSendOperation.Response(modifiedRecords: [], deletedIDs: [], conflictingIDs: [:], failedIDs: [:])
        await syncState.update(with: .operationSucceeded(.send(sendResponse)))
        
        let currentQueue4 = await syncState.currentQueue
        XCTAssertEqual(currentQueue4, .fetch)
    }
    
    func testEnabledQueues() async throws {
        await syncState.update(with: .start)
        await syncState.update(with: .accountStatusChanged(.available))
        
        let sendOp = TKSendOperation(modifications: [], deletions: [])
        let fetchOp = TKFetchOperation(changeToken: nil)
        
        await syncState.update(with: .operationEnqueued(.send(sendOp)))
        await syncState.update(with: .operationEnqueued(.fetch(fetchOp)))
        
        let currentQueue1 = await syncState.currentQueue
        XCTAssertNil(currentQueue1)
        
        let createZoneOp = CKRecordZone.ID(zoneName: "TestZone")
        await syncState.update(with: .operationEnqueued(.createZone(createZoneOp)))
        await syncState.update(with: .operationSucceeded(.createZone(true)))
        
        let currentQueue2 = await syncState.currentQueue
        XCTAssertNil(currentQueue2)
        
        let subscribeOp = TKSubscribeOperation(zoneID: CKRecordZone.ID(zoneName: "TestZone"), subscriptionID: "test")
        await syncState.update(with: .operationEnqueued(.subscribe(subscribeOp)))
        await syncState.update(with: .operationSucceeded(.subscribe(true)))
        
        let currentQueue3 = await syncState.currentQueue
        XCTAssertEqual(currentQueue3, .send)
    }
    
    func testAccountStatusRestrictions() async throws {
        await syncState.update(with: .start)
        
        let createZoneOp = CKRecordZone.ID(zoneName: "TestZone")
        await syncState.update(with: .operationEnqueued(.createZone(createZoneOp)))
        
        let currentQueue1 = await syncState.currentQueue
        XCTAssertNil(currentQueue1)
        
        await syncState.update(with: .accountStatusChanged(.noAccount))
        let currentQueue2 = await syncState.currentQueue
        XCTAssertNil(currentQueue2)
        
        await syncState.update(with: .accountStatusChanged(.available))
        let currentQueue4 = await syncState.currentQueue
        XCTAssertEqual(currentQueue4, .createZone)
    }
    
    func testIsRunningRestrictions() async throws {
        await syncState.update(with: .accountStatusChanged(.available))
        
        let createZoneOp = CKRecordZone.ID(zoneName: "TestZone")
        await syncState.update(with: .operationEnqueued(.createZone(createZoneOp)))
        
        let isRunning1 = await syncState.isRunning
        let currentQueue1 = await syncState.currentQueue
        XCTAssertFalse(isRunning1)
        XCTAssertNil(currentQueue1)
        
        await syncState.update(with: .start)
        let isRunning2 = await syncState.isRunning
        let currentQueue2 = await syncState.currentQueue
        XCTAssertTrue(isRunning2)
        XCTAssertEqual(currentQueue2, .createZone)
        
        await syncState.update(with: .stop())
        let isRunning3 = await syncState.isRunning
        let currentQueue3 = await syncState.currentQueue
        XCTAssertFalse(isRunning3)
        XCTAssertNil(currentQueue3)
    }
    
    func testPendingOperationsCount() async throws {
        let pendingCount1 = await syncState.pendingOperationsCount
        XCTAssertEqual(pendingCount1, 0)
        
        await syncState.update(with: .operationEnqueued(.createZone(CKRecordZone.ID(zoneName: "Zone1"))))
        let pendingCount2 = await syncState.pendingOperationsCount
        XCTAssertEqual(pendingCount2, 1)
        
        await syncState.update(with: .operationEnqueued(.createZone(CKRecordZone.ID(zoneName: "Zone2"))))
        let pendingCount3 = await syncState.pendingOperationsCount
        XCTAssertEqual(pendingCount3, 2)
        
        await syncState.update(with: .operationEnqueued(.subscribe(TKSubscribeOperation(zoneID: CKRecordZone.ID(zoneName: "Zone1"), subscriptionID: "sub1"))))
        let pendingCount4 = await syncState.pendingOperationsCount
        XCTAssertEqual(pendingCount4, 3)
        
        await syncState.update(with: .start)
        await syncState.update(with: .accountStatusChanged(.available))
        
        await syncState.update(with: .operationSucceeded(.createZone(true)))
        let pendingCount5 = await syncState.pendingOperationsCount
        XCTAssertEqual(pendingCount5, 2)
    }
    
    func testCurrentOperation() async throws {
        await syncState.update(with: .start)
        await syncState.update(with: .accountStatusChanged(.available))
        
        let currentOp1 = await syncState.currentOperation
        XCTAssertNil(currentOp1)
        
        let zoneID = CKRecordZone.ID(zoneName: "TestZone")
        await syncState.update(with: .operationEnqueued(.createZone(zoneID)))
        
        let currentOp2 = await syncState.currentOperation
        if case let .createZone(currentZoneID) = currentOp2 {
            XCTAssertEqual(currentZoneID, zoneID)
        } else {
            XCTFail("Expected createZone operation")
        }
        
        await syncState.update(with: .operationSucceeded(.createZone(true)))
        
        let currentOp3 = await syncState.currentOperation
        XCTAssertNil(currentOp3)
    }
    
    func testStateUpdatesOnSuccess() async throws {
        let isZoneAvailable1 = await syncState.isZoneAvailable
        let isSubscribed1 = await syncState.isSubscribed
        
        XCTAssertFalse(isZoneAvailable1)
        XCTAssertFalse(isSubscribed1)
        
        await syncState.update(with: .operationSucceeded(.createZone(true)))
        let isZoneAvailable2 = await syncState.isZoneAvailable
        XCTAssertTrue(isZoneAvailable2)
        
        await syncState.update(with: .operationSucceeded(.createZone(false)))
        let isZoneAvailable3 = await syncState.isZoneAvailable
        XCTAssertFalse(isZoneAvailable3)
        
        await syncState.update(with: .operationSucceeded(.subscribe(true)))
        let isSubscribed2 = await syncState.isSubscribed
        XCTAssertTrue(isSubscribed2)
    }
    
    func testEmptyQueues() async throws {
        await syncState.update(with: .start)
        await syncState.update(with: .accountStatusChanged(.available))
        await syncState.update(with: .operationSucceeded(.createZone(true)))
        await syncState.update(with: .operationSucceeded(.subscribe(true)))
        
        let currentQueue = await syncState.currentQueue
        let currentOperation = await syncState.currentOperation
        let pendingCount = await syncState.pendingOperationsCount
        XCTAssertNil(currentQueue)
        XCTAssertNil(currentOperation)
        XCTAssertEqual(pendingCount, 0)
    }
    
    func testMultipleOperationsInSameQueue() async throws {
        await syncState.update(with: .start)
        await syncState.update(with: .accountStatusChanged(.available))
        
        let zone1 = CKRecordZone.ID(zoneName: "Zone1")
        let zone2 = CKRecordZone.ID(zoneName: "Zone2")
        let zone3 = CKRecordZone.ID(zoneName: "Zone3")
        
        await syncState.update(with: .operationEnqueued(.createZone(zone1)))
        await syncState.update(with: .operationEnqueued(.createZone(zone2)))
        await syncState.update(with: .operationEnqueued(.createZone(zone3)))
        
        let pendingCount1 = await syncState.pendingOperationsCount
        XCTAssertEqual(pendingCount1, 3)
        
        let currentOp1 = await syncState.currentOperation
        if case let .createZone(currentZoneID) = currentOp1 {
            XCTAssertEqual(currentZoneID, zone1)
        } else {
            XCTFail("Expected createZone operation with zone1")
        }
        
        await syncState.update(with: .operationSucceeded(.createZone(true)))
        
        let pendingCount2 = await syncState.pendingOperationsCount
        XCTAssertEqual(pendingCount2, 2)
        
        let currentOp2 = await syncState.currentOperation
        if case let .createZone(currentZoneID) = currentOp2 {
            XCTAssertEqual(currentZoneID, zone2)
        } else {
            XCTFail("Expected createZone operation with zone2")
        }
    }
    
    func testReset() async throws {
        await syncState.update(with: .start)
        await syncState.update(with: .accountStatusChanged(.available))
        await syncState.update(with: .operationEnqueued(.createZone(CKRecordZone.ID(zoneName: "TestZone"))))
        await syncState.update(with: .operationSucceeded(.createZone(true)))
        await syncState.update(with: .operationEnqueued(.subscribe(TKSubscribeOperation(zoneID: CKRecordZone.ID(zoneName: "TestZone"), subscriptionID: "test"))))
        await syncState.update(with: .operationSucceeded(.subscribe(true)))
        await syncState.update(with: .operationEnqueued(.send(TKSendOperation(modifications: [], deletions: []))))
        await syncState.update(with: .operationRetry(CKError(.networkFailure)))
        
        let beforeReset = (
            currentQueue: await syncState.currentQueue,
            accountStatus: await syncState.accountStatus,
            retryCount: await syncState.retryCount,
            isRunning: await syncState.isRunning,
            isZoneAvailable: await syncState.isZoneAvailable,
            isSubscribed: await syncState.isSubscribed,
            pendingOperationsCount: await syncState.pendingOperationsCount
        )
        
        XCTAssertEqual(beforeReset.currentQueue, .send)
        XCTAssertEqual(beforeReset.accountStatus, .available)
        XCTAssertEqual(beforeReset.retryCount, 1)
        XCTAssertTrue(beforeReset.isRunning)
        XCTAssertTrue(beforeReset.isZoneAvailable)
        XCTAssertTrue(beforeReset.isSubscribed)
        XCTAssertEqual(beforeReset.pendingOperationsCount, 1)
        
        await syncState.reset()
        
        let afterReset = (
            currentQueue: await syncState.currentQueue,
            accountStatus: await syncState.accountStatus,
            retryCount: await syncState.retryCount,
            isRunning: await syncState.isRunning,
            isZoneAvailable: await syncState.isZoneAvailable,
            isSubscribed: await syncState.isSubscribed,
            pendingOperationsCount: await syncState.pendingOperationsCount,
            currentOperation: await syncState.currentOperation
        )
        
        XCTAssertNil(afterReset.currentQueue)
        XCTAssertNil(afterReset.accountStatus)
        XCTAssertEqual(afterReset.retryCount, 0)
        XCTAssertFalse(afterReset.isRunning)
        XCTAssertFalse(afterReset.isZoneAvailable)
        XCTAssertFalse(afterReset.isSubscribed)
        XCTAssertEqual(afterReset.pendingOperationsCount, 0)
        XCTAssertNil(afterReset.currentOperation)
    }
    
    func testOperationReplaced() async throws {
        let sendOp = TKSendOperation(modifications: [], deletions: [])
        
        await syncState.update(with: .start)
        await syncState.update(with: .accountStatusChanged(.available))
        await syncState.update(with: .operationSucceeded(.createZone(true)))
        await syncState.update(with: .operationSucceeded(.subscribe(true)))
        
        await syncState.update(with: .operationEnqueued(.send(sendOp)))
        let pendingCount1 = await syncState.pendingOperationsCount
        XCTAssertEqual(pendingCount1, 1)
        
        await syncState.update(with: .operationReplaced(with: [.send(sendOp), .send(sendOp)]))
        let pendingCount2 = await syncState.pendingOperationsCount
        XCTAssertEqual(pendingCount2, 2)
    }
    
    func testOperationReplacedResetsRetryCount() async throws {
        await syncState.update(with: .start)
        await syncState.update(with: .accountStatusChanged(.available))
        await syncState.update(with: .operationSucceeded(.createZone(true)))
        await syncState.update(with: .operationSucceeded(.subscribe(true)))
        await syncState.update(with: .operationEnqueued(.send(TKSendOperation(modifications: [], deletions: []))))
        await syncState.update(with: .operationRetry(CKError(.networkFailure)))
        await syncState.update(with: .operationRetry(CKError(.networkFailure)))
        
        let retryCount1 = await syncState.retryCount
        XCTAssertEqual(retryCount1, 2)
        
        let replacements = [TKOperation.fetch(TKFetchOperation(changeToken: nil))]
        await syncState.update(with: .operationReplaced(with: replacements))
        let retryCount2 = await syncState.retryCount
        XCTAssertEqual(retryCount2, 0)
    }
}
