import XCTest
@testable import Pipeline

/// Inputs are what gpt-4o-mini-transcribe returned for Hinglish speech
/// (macOS "Lekha" / "Rishi" voices) on Oct 16, 2026.
final class HinglishRomanizerTests: XCTestCase {

    private func check(_ devanagari: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(HinglishRomanizer.romanize(devanagari), expected, file: file, line: line)
    }

    func testRealTranscripts() {
        check("कल सुबह दस बजे मीटिंग है, कृपया रिपोर्ट भेज दीजिए।",
              "kal subah das baje meeting hai, kripya report bhej deejie.")
        check("कल मीटिंग है, डेक भेज देना और डिप्लॉयमेंट वाला इश्यू फिक्स कर देना।",
              "kal meeting hai, deck bhej dena aur deployment vala issue fix kar dena.")
        check("क्या, कल का डेमो रेडी है क्या यार? क्लाइंट को लिंक भेज दूँ प्लीज़।",
              "kya, kal ka demo ready hai kya yar? client ko link bhej doon please.")
    }

    func testFinalSilentA() {
        check("कल", "kal")
        check("भेज", "bhej")
        check("न", "na")  // a one-syllable word keeps its vowel
    }

    func testMedialSilentA() {
        check("करता", "karta")
        check("समझ गया", "samajh gaya")
        check("कमल", "kamal")
    }

    func testNasalsAndLongVowels() {
        check("हूँ", "hoon")
        check("अभी", "abhi")
        check("ठीक है", "theek hai")
    }

    func testNonDevanagariPassesThrough() {
        check("Please push the latest build.", "Please push the latest build.")
        check("", "")
    }

    func testMixedScript() {
        check("kubectl वाला issue", "kubectl vala issue")
    }
}
