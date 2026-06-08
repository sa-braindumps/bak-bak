import XCTest
@testable import Pipeline

final class ProfileStoreTests: XCTestCase {

    var tempDir: URL!
    var profileURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        profileURL = tempDir.appendingPathComponent("profile.toml")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testDefaultProfileWhenNoFile() throws {
        let store = ProfileStore(fileURL: profileURL)
        let profile = try store.read()
        XCTAssertTrue(profile.vocab.isEmpty)
        XCTAssertEqual(profile.hotkeyTrigger, "option")
        XCTAssertEqual(profile.correctionWindowSecs, 10)
    }

    func testWriteAndReadProfile() throws {
        let store = ProfileStore(fileURL: profileURL)
        var profile = ProfileStore.Profile()
        profile.vocab = ["cube cuttle": "kubectl"]
        profile.hotkeyTrigger = "option"
        profile.correctionWindowSecs = 15

        try store.write(profile)

        let readProfile = try store.read()
        XCTAssertEqual(readProfile.vocab["cube cuttle"], "kubectl")
        XCTAssertEqual(readProfile.hotkeyTrigger, "option")
        XCTAssertEqual(readProfile.correctionWindowSecs, 15)
    }

    func testAddVocabEntry() throws {
        let store = ProfileStore(fileURL: profileURL)
        try store.addVocabEntry(heard: "nicks", intended: "Nginx")

        let profile = try store.read()
        XCTAssertEqual(profile.vocab["nicks"], "Nginx")
    }

    func testAddMultipleVocabEntries() throws {
        let store = ProfileStore(fileURL: profileURL)
        try store.addVocabEntry(heard: "nicks", intended: "Nginx")
        try store.addVocabEntry(heard: "cube cuttle", intended: "kubectl")

        let profile = try store.read()
        XCTAssertEqual(profile.vocab.count, 2)
        XCTAssertEqual(profile.vocab["nicks"], "Nginx")
        XCTAssertEqual(profile.vocab["cube cuttle"], "kubectl")
    }

    func testUpdateExistingVocabEntry() throws {
        let store = ProfileStore(fileURL: profileURL)
        try store.addVocabEntry(heard: "nicks", intended: "Nginx")
        try store.addVocabEntry(heard: "nicks", intended: "NGINX")

        let profile = try store.read()
        XCTAssertEqual(profile.vocab["nicks"], "NGINX")
    }

    func testApiKeyOperations() throws {
        let store = ProfileStore(fileURL: profileURL)
        try store.setApiKey("sk-test123")

        let key = try store.getApiKey()
        XCTAssertEqual(key, "sk-test123")
    }

    func testGetApiKeyWhenNotSet() throws {
        let store = ProfileStore(fileURL: profileURL)
        let key = try store.getApiKey()
        XCTAssertNil(key)
    }

    func testRecentCorrectionsWhenNoFile() throws {
        let store = ProfileStore(fileURL: profileURL)
        let corrections = try store.recentCorrections()
        XCTAssertTrue(corrections.isEmpty)
    }
}
