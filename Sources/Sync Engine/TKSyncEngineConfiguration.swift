//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import CloudKit

/// An object that contains sync engine settings.
public struct TKSyncEngineConfiguration {
    /// The identifier of a CloudKit container.
    ///
    /// Required to initialize a `CKContainer`. If `nil`, the sync engine will use your app's default container.
    public var containerID: String?
    
    /// The name of a CloudKit record zone.
    ///
    /// Required to initialize a `CKRecordZone`. If `nil`, the sync engine will use the default zone.
    public var zoneName: String?
    
    /// The identifier of a CloudKit record zone subscription.
    ///
    /// Required to initialize a `CKRecordZoneSubscription`. If `nil`, the sync engine will try to fall back
    /// on ``zoneName``. If that value is also `nil`, the sync engine will provide the default identifier.
    public var subscriptionID: String?
    
    /// The maximum number of retry attempts for failed operations. The default value is 5.
    public var maxRetryAttempts: Int = 5
    
    /// The maximum number of records per operation. The default value is 400.
    public var maxRecordsPerOperation: Int = 400
    
    /// The maximum delay (in seconds) between operations. The default value is 64.
    public var maxOperationThrottle: TimeInterval = 64
    
    /// The minimum delay (in seconds) between operations. The default value is 1.
    public var minOperationThrottle: TimeInterval = 1
    
    /// Whether the sync engine should check the iCloud account status upon initialization.
    /// The default value is true.
    public var checkAccountStatusOnInit: Bool = true
    
    /// The save policy for record modifications. The default value is `.ifServerRecordUnchanged`,
    /// which prevents overwriting server changes.
    public var recordSavePolicy: CKModifyRecordsOperation.RecordSavePolicy = .ifServerRecordUnchanged
    
    /// Creates a new configuration instance.
    /// - Parameters:
    ///   - containerID: The identifier of a CloudKit container. Specify `nil` to use your app's default container.
    ///   - zoneName: The name of a CloudKit record zone. Specify `nil` to use the default zone.
    ///   - subscriptionID: The identifier of a CloudKit record zone subscription. Specify `nil`
    ///   to fallback to `zoneName` or to the default identifier (if `zoneName` is also `nil`).
    public init(containerID: String? = nil, zoneName: String? = nil, subscriptionID: String? = nil) {
        self.containerID = containerID
        self.zoneName = zoneName
        self.subscriptionID = subscriptionID
    }
}
