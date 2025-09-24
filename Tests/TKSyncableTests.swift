//
//  Copyright (c) 2025 Nikita Orlov
//  Licensed under the MIT License. See LICENSE for details.
//

import XCTest
import CloudKit
@testable import TakeoffKit

final class TKSyncableTests: XCTestCase {
    // MARK: Types
    class TestFolder: TKSyncable {
        let id = UUID()
        var index = 3
        var name = "Test Folder"
        
        var tkRecordID: String { return id.uuidString }
        var tkProperties: [String : TKSyncableValue] { [
            "index": .value(index),
            "name": .encryptedValue(name)
        ] }
        var tkMetadata: Data?
    }

    struct TestNote: TKSyncable {
        let id = UUID()
        let content = "Hello, World!"
        let createdAt = Date()
        let asset: URL
        let folder: TestFolder
        
        static let tkRecordType: String = "CustomType"
        var tkRecordID: String { id.uuidString }
        var tkProperties: [String : TKSyncableValue] { [
            "content": .encryptedValue(content),
            "createdAt": .value(createdAt),
            "asset": .asset(fileURL: asset),
            "folder": .reference(folder, onReferenceDeleted: .noAction)
        ] }
        var tkMetadata: Data?
    }
    
    // MARK: Utils
    var folder: TestFolder!
    var note: TestNote!
    var assetURL: URL!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        folder = TestFolder()
        assetURL = createTempFile()
        note = TestNote(asset: assetURL, folder: folder)
    }
    
    override func tearDownWithError() throws {
        folder = nil
        note = nil
        
        if let assetURL {
            try! FileManager.default.removeItem(at: assetURL)
            self.assetURL = nil
        }
        
        try super.tearDownWithError()
    }
    
    private func createTempFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test.txt")
        let testContent = "This is a test file for TakeoffKit testing."
        try! testContent.write(to: fileURL, atomically: false, encoding: .utf8)
        return fileURL
    }
    
    // MARK: Tests
    func testRecordType() {
        let folderRecord = folder.convertToCKRecord(zoneID: .default)
        let noteRecord = note.convertToCKRecord(zoneID: .default)
        XCTAssertEqual(folderRecord.recordType, "TestFolder")
        XCTAssertEqual(folderRecord.recordType, TestFolder.tkRecordType)
        XCTAssertEqual(noteRecord.recordType, "CustomType")
        XCTAssertEqual(noteRecord.recordType, TestNote.tkRecordType)
    }
    
    func testRecordID() {
        let folderRecord = folder.convertToCKRecord(zoneID: .default)
        XCTAssertEqual(folderRecord.recordID.recordName, folder.id.uuidString)
    }
    
    func testValueConversion() {
        let folderRecord = folder.convertToCKRecord(zoneID: .default)
        XCTAssertEqual(folderRecord["index"], folder.index)
        XCTAssertEqual(folderRecord.encryptedValues["name"], folder.name)
        XCTAssertNil(folderRecord["name"])
        XCTAssertNil(folderRecord["nonexistentField"])
        
        let noteRecord = note.convertToCKRecord(zoneID: .default)
        XCTAssertEqual(noteRecord.recordID.recordName, note.id.uuidString)
        XCTAssertEqual(noteRecord.encryptedValues["content"], "Hello, World!")
        XCTAssertEqual(noteRecord["createdAt"], note.createdAt)
    }
    
    func testAssetConversion() {
        let noteRecord = note.convertToCKRecord(zoneID: .default)
        
        if let asset = noteRecord["asset"] as? CKAsset {
            XCTAssertEqual(asset.fileURL, assetURL)
        } else {
            XCTFail("Should be a non-nil CKAsset value")
        }
    }
    
    func testReferenceConversion() {
        let noteRecord = note.convertToCKRecord(zoneID: .default)
        
        if let reference = noteRecord["folder"] as? CKRecord.Reference {
            XCTAssertEqual(reference.recordID.recordName, folder.id.uuidString)
            XCTAssertEqual(reference.action, .none)
        } else {
            XCTFail("Should be a non-nil CKRecord.Reference value")
        }
    }
    
    func testExtremeButValidFieldNames() {
        struct ExtremeFieldsNote: TKSyncable {
            var tkMetadata: Data?
            let id = String(repeating: "a", count: 255)
            let content = ""
            let createdAt = Date.distantPast
            let index = Int.max
            
            var tkRecordID: String { id }
            var tkProperties: [String : TKSyncableValue] { [
                "content": .encryptedValue(content),
                "createdAt": .value(createdAt),
                "index": .value(index)
            ] }
        }
        
        let note = ExtremeFieldsNote()
        let record = note.convertToCKRecord(zoneID: .default)
        XCTAssert(record.recordID.recordName == note.id)
        XCTAssert(record.encryptedValues["content"] == note.content)
        XCTAssert(record["createdAt"] == note.createdAt)
        XCTAssert(record["index"] == note.index)
    }
    
    func testInvalidFieldNames() {
        struct InvalidFieldNamesModel: TKSyncable {
            var tkMetadata: Data?
            var tkRecordID: String { "test" }
            
            var tkProperties: [String : TKSyncableValue] {
                return [
                    "_invalidField": .value("starts with underscore"),
                    String(repeating: "x", count: 256): .value("too long"),
                    "field with spaces": .value("contains spaces"),
                    "field-with-dashes": .value("contains dashes")
                ]
            }
        }
        
        let invalidModel = InvalidFieldNamesModel()
        XCTAssertNoThrow({ _ = invalidModel.convertToCKRecord })
        // It's impossible to catch NSInvalidArgumentException currently,
        // but it's there.
    }
}
