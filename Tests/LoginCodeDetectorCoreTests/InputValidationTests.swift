import XCTest
@testable import LoginCodeDetectorCore

final class InputValidationTests: XCTestCase {
    func testSanitizeMailboxesTrimsDeduplicatesAndDropsControlCharacters() {
        let result = IMAPInputValidation.sanitizeMailboxes([
            " INBOX ",
            "inbox",
            "Codes",
            "Bad\nMailbox",
            " ",
            "\tAlerts\t"
        ])

        XCTAssertEqual(result, ["INBOX", "Codes", "Alerts"])
    }

    func testQuoteIMAPStringEscapesBackslashesAndQuotes() throws {
        let result = try IMAPInputValidation.quoteIMAPString(#"a\b"c"#, field: "username")

        XCTAssertEqual(result, #""a\\b\"c""#)
    }

    func testValidateHostRejectsWhitespaceAndControlCharacters() {
        XCTAssertNoThrow(try IMAPInputValidation.validateHost("imap.example.com"))
        XCTAssertThrowsError(try IMAPInputValidation.validateHost("imap.example.com\n"))
        XCTAssertThrowsError(try IMAPInputValidation.validateHost("imap example.com"))
    }
}
