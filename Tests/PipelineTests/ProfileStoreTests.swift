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
        XCTAssertEqual(profile.hotkeyModifiers, "control+option")
        XCTAssertEqual(profile.correctionWindowSecs, 10)
    }

    func testWriteAndReadProfile() throws {
        let store = ProfileStore(fileURL: profileURL)
        var profile = ProfileStore.Profile()
        profile.vocab = ["cube cuttle": "kubectl"]
        profile.hotkeyModifiers = "option"
        profile.correctionWindowSecs = 15

        try store.write(profile)

        let readProfile = try store.read()
        XCTAssertEqual(readProfile.vocab["cube cuttle"], "kubectl")
        XCTAssertEqual(readProfile.hotkeyModifiers, "option")
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

    // MARK: - Snippets

    func testDefaultSnippetsEmpty() throws {
        let store = ProfileStore(fileURL: profileURL)
        let profile = try store.read()
        XCTAssertTrue(profile.snippets.isEmpty)
    }

    func testAddAndReadSnippet() throws {
        let store = ProfileStore(fileURL: profileURL)
        try store.addSnippet(trigger: "sign off", expansion: "Best,\nShivam")

        let profile = try store.read()
        XCTAssertEqual(profile.snippets["sign off"], "Best,\nShivam")
    }

    func testUpdateExistingSnippet() throws {
        let store = ProfileStore(fileURL: profileURL)
        try store.addSnippet(trigger: "my email", expansion: "a@x.com")
        try store.addSnippet(trigger: "my email", expansion: "b@x.com")

        let profile = try store.read()
        XCTAssertEqual(profile.snippets["my email"], "b@x.com")
    }

    func testRemoveSnippet() throws {
        let store = ProfileStore(fileURL: profileURL)
        try store.addSnippet(trigger: "my email", expansion: "a@x.com")
        try store.removeSnippet(trigger: "my email")

        let profile = try store.read()
        XCTAssertNil(profile.snippets["my email"])
    }

    func testRemoveMissingSnippetIsNoOp() throws {
        let store = ProfileStore(fileURL: profileURL)
        XCTAssertNoThrow(try store.removeSnippet(trigger: "nope"))
    }

    func testSnippetRoundTripViaWrite() throws {
        let store = ProfileStore(fileURL: profileURL)
        var profile = ProfileStore.Profile()
        profile.snippets = ["my address": "123 Main St\nSpringfield"]
        try store.write(profile)

        let readBack = try store.read()
        XCTAssertEqual(readBack.snippets["my address"], "123 Main St\nSpringfield")
    }

    // MARK: - Cleanup / remove_fillers

    func testDefaultRemoveFillersFalse() throws {
        let store = ProfileStore(fileURL: profileURL)
        let profile = try store.read()
        XCTAssertFalse(profile.removeFillers)
    }

    func testSetRemoveFillers() throws {
        let store = ProfileStore(fileURL: profileURL)
        try store.setRemoveFillers(true)
        XCTAssertTrue(try store.read().removeFillers)

        try store.setRemoveFillers(false)
        XCTAssertFalse(try store.read().removeFillers)
    }

    // MARK: - Comment preservation (the load-bearing invariant)

    func testWritePreservesComments() throws {
        // Seed a file with a load-bearing learned-correction comment.
        let seed = """
        # ~/.bak-bak/profile.toml
        [vocab]
        # learned 2026-06-08T10:23:11Z
        "cube cuttle" = "kubectl"

        [cleanup]
        remove_fillers = false
        """
        try seed.write(to: profileURL, atomically: true, encoding: .utf8)

        let store = ProfileStore(fileURL: profileURL)
        // Mutate via a couple of comment-preserving ops.
        try store.addSnippet(trigger: "my email", expansion: "a@x.com")
        try store.setRemoveFillers(true)

        let raw = try String(contentsOf: profileURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("# learned 2026-06-08T10:23:11Z"), "learned comment must survive")
        XCTAssertTrue(raw.contains("# ~/.bak-bak/profile.toml"), "header comment must survive")

        let profile = try store.read()
        XCTAssertEqual(profile.vocab["cube cuttle"], "kubectl")
        XCTAssertEqual(profile.snippets["my email"], "a@x.com")
        XCTAssertTrue(profile.removeFillers)
    }

    func testWritePreservesUnknownCleanupKeys() throws {
        // Phase 2 will add more [cleanup] keys; our writes must not drop them.
        let seed = """
        [cleanup]
        remove_fillers = false
        future_phase2_key = "do not drop me"
        """
        try seed.write(to: profileURL, atomically: true, encoding: .utf8)

        let store = ProfileStore(fileURL: profileURL)
        try store.setRemoveFillers(true)

        let raw = try String(contentsOf: profileURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("future_phase2_key"), "unknown [cleanup] key must survive")
        XCTAssertTrue(raw.contains("do not drop me"))
        XCTAssertTrue(try store.read().removeFillers)
    }

    // MARK: - Regressions

    func testFirstWriteWithNoFileDoesNotDeadlock() throws {
        // Used to re-take the same NSLock inside write() and hang forever.
        let store = ProfileStore(fileURL: profileURL)
        try store.addVocabEntry(heard: "nicks", intended: "Nginx")
        try store.addSnippet(trigger: "my email", expansion: "a@x.com")
        let profile = try store.read()
        XCTAssertEqual(profile.vocab["nicks"], "Nginx")
        XCTAssertEqual(profile.snippets["my email"], "a@x.com")
    }

    func testLearnedCorrectionShowsUpInRecentCorrections() throws {
        let store = ProfileStore(fileURL: profileURL)
        let date = ISO8601DateFormatter().date(from: "2026-10-16T09:30:00Z")!
        try store.addVocabEntry(heard: "cube cuttle", intended: "kubectl", learnedAt: date)
        try store.addVocabEntry(heard: "nicks", intended: "Nginx")

        let recent = try store.recentCorrections()
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.heard, "cube cuttle")
        XCTAssertEqual(recent.first?.intended, "kubectl")
        XCTAssertEqual(recent.first?.timestamp, "2026-10-16T09:30:00Z")
    }

    func testRemoveVocabEntryKeepsOtherComments() throws {
        let seed = """
        # my notes
        [vocab]
        # learned 2026-06-08T10:23:11Z
        "cube cuttle" = "kubectl"
        "nicks" = "Nginx"
        """
        try seed.write(to: profileURL, atomically: true, encoding: .utf8)

        let store = ProfileStore(fileURL: profileURL)
        try store.removeVocabEntry(heard: "cube cuttle")

        let raw = try String(contentsOf: profileURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("# my notes"))
        XCTAssertFalse(raw.contains("# learned 2026-06-08T10:23:11Z"), "the removed entry's learned comment goes with it")
        XCTAssertEqual(try store.read().vocab, ["nicks": "Nginx"])
    }

    func testFullWriteKeepsCommentsAndApiKey() throws {
        let seed = """
        # header
        [general]
        api_key = "sk-keep"
        [vocab]
        # learned 2026-06-08T10:23:11Z
        "cube cuttle" = "kubectl"
        "old" = "gone"
        """
        try seed.write(to: profileURL, atomically: true, encoding: .utf8)

        let store = ProfileStore(fileURL: profileURL)
        var profile = try store.read()
        profile.vocab.removeValue(forKey: "old")
        profile.soundEnabled = false
        try store.write(profile)

        let raw = try String(contentsOf: profileURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("# header"))
        XCTAssertTrue(raw.contains("# learned 2026-06-08T10:23:11Z"))
        XCTAssertEqual(try store.getApiKey(), "sk-keep")
        let reread = try store.read()
        XCTAssertEqual(reread.vocab, ["cube cuttle": "kubectl"])
        XCTAssertFalse(reread.soundEnabled)
    }

    func testMultilineSnippetBodyIsNotMistakenForTableOrKey() throws {
        let seed = #"""
        [snippets]
        "address" = """
        [not a table]
        flat = 4B
        """

        [vocab]
        "nicks" = "Nginx"
        """#
        try seed.write(to: profileURL, atomically: true, encoding: .utf8)

        let store = ProfileStore(fileURL: profileURL)
        try store.addSnippet(trigger: "flat", expansion: "should be a new snippet")
        try store.addVocabEntry(heard: "cube cuttle", intended: "kubectl")

        let profile = try store.read()
        XCTAssertEqual(profile.snippets["address"], "[not a table]\nflat = 4B\n")
        XCTAssertEqual(profile.snippets["flat"], "should be a new snippet")
        XCTAssertEqual(profile.vocab["cube cuttle"], "kubectl")
    }

    func testValuesWithQuotesAndNewlinesRoundTrip() throws {
        let store = ProfileStore(fileURL: profileURL)
        try store.addSnippet(trigger: "sign off", expansion: "Best,\n\"Shivam\" \\ team")
        XCTAssertEqual(try store.read().snippets["sign off"], "Best,\n\"Shivam\" \\ team")
    }

    // MARK: - First run

    func testDefaultTemplateParsesToDefaults() throws {
        let store = ProfileStore(fileURL: profileURL)
        XCTAssertTrue(try store.createDefaultIfMissing())
        let profile = try store.read()
        XCTAssertEqual(profile.hotkeyModifiers, "control+option")
        XCTAssertEqual(profile.recordingMode, "hold")
        XCTAssertEqual(profile.correctionWindowSecs, 10)
        XCTAssertFalse(profile.removeFillers)
        XCTAssertTrue(profile.vocab.isEmpty)
        XCTAssertTrue(profile.snippets.isEmpty)
    }

    func testCreateDefaultNeverOverwrites() throws {
        // Regression: re-running `bak-bak setup` used to wipe the profile.
        let store = ProfileStore(fileURL: profileURL)
        try store.addVocabEntry(heard: "nicks", intended: "Nginx")
        try store.addSnippet(trigger: "my email", expansion: "a@x.com")

        XCTAssertFalse(try store.createDefaultIfMissing())
        try store.setApiKey("sk-new")

        let profile = try store.read()
        XCTAssertEqual(profile.vocab["nicks"], "Nginx")
        XCTAssertEqual(profile.snippets["my email"], "a@x.com")
        XCTAssertEqual(try store.getApiKey(), "sk-new")
    }
}
