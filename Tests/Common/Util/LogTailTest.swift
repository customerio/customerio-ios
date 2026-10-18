// Contract: cio-sdk-tools `verify push` parses log tails built this way (its `docs/verify-contract.md`).
// Changing the separator, the order, or the encoding, or renaming an `ev` or a key, breaks it.

@testable import CioInternalCommon
import Foundation
import SharedTests
import Testing

struct LogTailTest {
    // MARK: make

    @Test
    func make_givenFields_expectEventFirstThenKeysInGivenOrder() {
        let tail = LogTail.make("push.opened", ["id": "dgS_abc", "title": "Hi"])

        #expect(tail == " || ev=push.opened id=dgS_abc title=Hi")
    }

    @Test
    func make_givenNoFields_expectEventOnly() {
        #expect(LogTail.make("sdk.state") == " || ev=sdk.state")
    }

    @Test
    func make_givenNilValue_expectKeyOmitted() {
        let tail = LogTail.make("push.clicked", ["cio": "false", "id": nil])

        #expect(tail == " || ev=push.clicked cio=false")
    }

    // MARK: encode

    @Test
    func encode_givenPercentPipeAndWhitespace_expectUppercaseUtf8Escapes() {
        #expect(LogTail.encode("a b|c%d\te\nf\rg") == "a%20b%7Cc%25d%09e%0Af%0Dg")
    }

    @Test
    func encode_givenNonAsciiWhitespace_expectEachUtf8ByteEscaped() {
        // No-break space and ideographic space.
        #expect(LogTail.encode("a\u{00A0}b\u{3000}c") == "a%C2%A0b%E3%80%80c")
    }

    @Test
    func encode_givenOtherCharacters_expectLiteral() {
        let value = "dgS_a=b,c:d/é?x=1&y#"

        #expect(LogTail.encode(value) == value)
    }

    // MARK: orNone

    @Test
    func orNone_givenNilOrEmpty_expectNone() {
        #expect(LogTail.orNone(nil) == "none")
        #expect(LogTail.orNone("") == "none")
        #expect(LogTail.orNone("abc") == "abc")
    }

    // MARK: reading it back

    @Test
    func reader_givenSentenceContainingSeparator_expectLastSeparatorSplits() {
        let sentence = "Handling a || b"
        let url = "https://example.com/a || b"

        let reader = LogTailReader(sentence + LogTail.make("push.deep_link", ["url": url]))

        #expect(reader?.sentence == sentence)
        #expect(reader?.event == "push.deep_link")
        #expect(reader?.values["url"] == url)
    }

    @Test
    func reader_givenAwkwardValues_expectEachDecodesToItself() {
        let values = ["dgS_abc==", "a=b=c", "100% | done", "line\nbreak", "tab\there", "", "é ü"]

        for value in values {
            let reader = LogTailReader("x" + LogTail.make("ev.test", ["v": value, "after": "1"]))

            #expect(reader?.keys == ["ev", "v", "after"])
            #expect(reader?.values["v"] == value)
            #expect(reader?.values["after"] == "1")
        }
    }
}
