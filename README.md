# 🛫 TakeoffKit

![Main branch build & test status](https://github.com/orloff-n/TakeoffKit/actions/workflows/swift.yml/badge.svg)

TakeoffKit is a Swift library that simplifies synchronizing local data using CloudKit, abstracting away numerous CloudKit complexities like `CKRecord` conversion, rate limiting, error handling and many more. It provides a sync engine similar to Apple's [`CKSyncEngine`](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5), but with more granular control and better backward compatibility.

The sync engine is designed to work with any local persistence framework – CoreData, SwiftData, Realm, etc.

## Features
### 🚀 Modern, yet compatible
Built with modern async/await APIs and Swift 6 ready, but still offering iOS 15 compatibility.

### ⚙️ Event-driven architecture
Designed as a [Mealy machine](https://en.wikipedia.org/wiki/Mealy_machine), the sync engine's state and actions are determined by a finite set of events, resulting in predictable and traceable behavior.

### ✅ Robust error handling
Automatically handles recoverable CloudKit errors and retries failed operations. If a non-recoverable error occurs, the sync engine stops and notifies its delegate.

### 🔎 Observable state
The sync engine's state properties can be monitored for better UI/UX or debugging.

### 📦 Developer-friendly package
No external dependencies and comprehensive documentation.

## Requirements
- iOS 15.0+, macOS 12.0+, tvOS 15.0+, visionOS 1.0+, watchOS 8.0+
- Swift 5.5+ (visionOS requires Swift 5.9+)

## Installation
Add a dependency using Swift Package Manager:
1. In Xcode select `File → Add Package Dependencies...`
2. Enter the repository URL: `https://github.com/orloff-n/TakeoffKit.git`
3. Select a dependency rule and add the package to your project

## Usage
> [!NOTE]
> Read the full documentation [here](https://swiftpackageindex.com/orloff-n/TakeoffKit/main/documentation).

### Prerequisite
Ensure that your app is [configured to use CloudKit](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app).

### 1. Prepare your data models
Conform your data models to `TKSyncable` protocol. An example for Realm:
```swift
final class Folder: TKSyncable {
    @Persisted(primaryKey: true) var id: ObjectId
    @Persisted var index: Int
    @Persisted var name: String
    @Persisted(originProperty: "folder") var accounts: LinkingObjects<Account>


    // TKSyncable conformance:
    @Persisted var tkMetadata: Data?
    var tkRecordID: String { id.stringValue }
    var tkProperties: [String: TKSyncableValue] { [
        "index": .value(index),
        "name": .encryptedValue(name)
    ] }
}
```

### 2. Initialize the sync engine
Create a configuration and initialize `TKSyncEngine` with it:
```swift
let config = TKSyncEngineConfiguration(
    containerID: "iCloud.com.example.MyApp",
    zoneName: "MyDataZone",
    subscriptionID: "MySubscription"
)

let engine = TKSyncEngine(configuration: config)
```

### 3. Set a delegate
Conform one of your classes to `TKSyncEngineDelegate` and implement these methods:
```swift
extension YourDelegate: TKSyncEngineDelegate {
    func syncEngine(_ engine: TKSyncEngine, didStopWithError error: any Error) {
        // Handle errors
    }
    
    func syncEngine(_ engine: TKSyncEngine, didChangeAccountStatus accountStatus: CKAccountStatus) {
        // React to account status changes
    }
    
    func syncEngine(_ engine: TKSyncEngine, didUpdateChangeToken changeToken: CKServerChangeToken?) {
        // Persist the received token
    }
    
    func syncEngine(_ engine: TKSyncEngine, didFetchModifications modifications: [TKRecord]) {
        // Persist changes
    }
    
    func syncEngine(_ engine: TKSyncEngine, didFetchDeletions deletions: [(recordID: String, recordType: String)]) {
        // Persist changes
    }
    
    func syncEngine(_ engine: TKSyncEngine, fetchDidFailFor failedIDs: [String : any Error]) {
        // Handle per-record errors
    }
    
    func syncEngine(_ engine: TKSyncEngine, didSendModifications modifiedRecords: [TKRecord]) {
        // Update local items (e.g. mark them as synced)
    }
    
    func syncEngine(_ engine: TKSyncEngine, didSendDeletions deletedIDs: [String]) {
        // Update local items (e.g. hard delete them)
    }
    
    func syncEngine(_ engine: TKSyncEngine, sendDidFailFor failedIDs: [String : any Error]) {
        // Handle per-record errors
    }
    
    func syncEngine(_ engine: TKSyncEngine, shouldResolveConflict conflict: TKConflict) -> CKRecord {
        // Implement your conflict resolution logic. Example:
        if let clientDate = conflict.clientRecord.modificationDate,
           let serverDate = conflict.serverRecord.modificationDate {
            return clientDate > serverDate ? conflict.clientRecord : conflict.serverRecord
        }
        
        return conflict.clientRecord
    }
}
```

Assign the sync engine's delegate:
```swift
engine.delegate = self
```

### 4. Start the sync engine
Call `start()` on `TKSyncEngine` to start performing CloudKit operations:
```swift
engine.start() // Start syncing

// Send changes
engine.sendChanges(modify: modifiedItems, delete: deletedIDs)

// Fetch changes
engine.fetchChanges(token: lastChangeToken)
```

> [!TIP]
> You can call `fetchChanges(token:)` and `sendChanges(modify:delete:)` at any time. These operations will be added to the queue, but they will not be performed unless the sync engine is running and the required conditions are met.

### 5. Handle remote notifications
For real-time updates, register the app for remote notifications and handle them in `AppDelegate`:
```swift
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any]) async -> UIBackgroundFetchResult {
        // Filter CloudKit notifications by subscriptionID (should match TKSyncEngineConfiguration)
        if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
           notification.subscriptionID == "MySubscription" {
            // Fetch changes and return the appropriate UIBackgroundFetchResult
        }
        
        // Other notifications
        return .noData
    }
}
```

## Limitations
> [!IMPORTANT]
> The following CloudKit features are not supported:
> - Public databases
> - Record sharing
> - Multiple record zones & subscriptions

## Acknowledgments
The event-driven architecture and state management were heavily inspired by [CloudSyncSession](https://github.com/ryanashcraft/CloudSyncSession).

At first, I merely considered forking it just to update its deprecated CloudKit APIs. But the more I dug into its codebase, the more I felt the need to write my own implementation. Here's what I've done differently:
- Built the entire engine with modern async/await syntax, replacing deprecated CloudKit APIs and ensuring full compatibility with Swift 6 strict concurrency mode
- Added an abstraction layer for bidirectional conversion between local data models and CloudKit records, reducing boilerplate while maintaining flexibility
- Removed the middleware pattern in favor of a straightforward private method call chain for improved logic clarity and code readability
- Simplified event handling - there are fewer events, they contain less data and they are never replaced, which makes it much easier to trace the processing flow
- Optimized queue management - operations remain in the queue until they finish successfully or are replaced with other operations, eliminating unnecessary state changes
- Implemented a delegate pattern instead of Combine publishers for better convenience and easier integration

Yet, CloudSyncSession is one of the best CloudKit libraries available. Many thanks to Ryan Ashcraft for creating and open-sourcing such an excellent project.

## License
TakeoffKit is released under the MIT License. See [LICENSE](LICENSE) for details.
