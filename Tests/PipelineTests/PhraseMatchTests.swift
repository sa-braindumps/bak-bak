import XCTest
@testable import Pipeline

/// The model writes the same words differently from one dictation to the
/// next. These strings are what gpt-4o-mini-transcribe actually returned in
/// testing on Oct 16, 2026.
final class PhraseMatchTests: XCTestCase {

    func testVocabMatchesHyphenatedAndJoinedForms() {
        let vocab = ["bug bug": "Bak-Bak"]
        XCTAssertEqual(Substitutor.apply("Merge it into the Bug-Bug repo.", vocab: vocab), "Merge it into the Bak-Bak repo.")
        XCTAssertEqual(Substitutor.apply("Merge it into the bugbug repo.", vocab: vocab), "Merge it into the Bak-Bak repo.")
        XCTAssertEqual(Substitutor.apply("Open the BugBug dashboard.", vocab: vocab), "Open the Bak-Bak dashboard.")
        XCTAssertEqual(Substitutor.apply("Merge it into the bug bug repo.", vocab: vocab), "Merge it into the Bak-Bak repo.")
    }

    func testHyphenatedKeyMatchesSpacedText() {
        XCTAssertEqual(Substitutor.apply("check the sign off flow", vocab: ["sign-off": "signoff"]), "check the signoff flow")
    }

    func testStillWholeWordsOnly() {
        XCTAssertEqual(Substitutor.apply("debugbug and bugbugs", vocab: ["bug bug": "Bak-Bak"]), "debugbug and bugbugs")
        XCTAssertEqual(Substitutor.apply("picnicks", vocab: ["nicks": "Nginx"]), "picnicks")
    }

    func testSnippetTriggerIgnoresHyphens() {
        let snippets = ["my sign off": "Cheers"]
        XCTAssertEqual(SnippetExpander.apply("My sign-off.", snippets: snippets), "Cheers")
        XCTAssertEqual(SnippetExpander.apply("my signoff", snippets: snippets), "Cheers")
        XCTAssertEqual(SnippetExpander.apply("my sign off is ready", snippets: snippets), "my sign off is ready")
    }

    func testCorrectionAcceptsHyphenatedLastText() {
        // Without this you couldn't teach "bug bug" → Bak-Bak at all.
        let correction = CorrectionGrammar.parse("No, bug bug is Bak-Bak.", lastText: "Merge it into the Bug-Bug repo after review.")
        XCTAssertEqual(correction?.heard, "bug bug")
        XCTAssertEqual(correction?.intended, "Bak-Bak")
        XCTAssertEqual(Substitutor.apply("Merge it into the Bug-Bug repo after review.", vocab: ["bug bug": "Bak-Bak"]),
                       "Merge it into the Bak-Bak repo after review.")
    }
}
