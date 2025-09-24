# ``TakeoffKit``

A modern CloudKit sync engine for any local database.

## Overview

TakeoffKit is a Swift library that simplifies synchronizing local data using CloudKit, abstracting numerous CloudKit complexities like `CKRecord` conversion, rate limiting, error handling and many more. It provides a sync engine similar to Apple's [`CKSyncEngine`](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5), but with more granular control and better backward compatibility.

The sync engine is designed to work with any local persistence framework – CoreData, SwiftData, Realm, etc.

> See `README.md` for installation and usage, `LICENSE` for licensing details.

## Topics

### Sync engine

- ``TKSyncEngine``
- ``TKSyncEngineConfiguration``
- ``TKSyncEngineDelegate``
- ``TKSyncEngineState``

### Data models

- ``TKSyncable``
- ``TKSyncableValue``
- ``TKSyncableValueType``
- ``TKRecord``
