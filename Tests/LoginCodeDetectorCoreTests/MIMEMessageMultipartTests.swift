import XCTest
@testable import LoginCodeDetectorCore

final class MIMEMessageMultipartTests: XCTestCase {
    func testNestedMultipartFindsHtmlBodyInsideAlternativeSection() {
        let raw = """
        Content-Type: multipart/mixed; boundary="outer"

        --outer
        Content-Type: text/plain; charset="utf-8"

        Plain fallback
        --outer
        Content-Type: multipart/alternative; boundary="inner"

        --inner
        Content-Type: text/plain; charset="utf-8"

        Alternative plain
        --inner
        Content-Type: text/html; charset="utf-8"

        <html><body><p>Your code is</p><p><strong>777888</strong></p></body></html>
        --inner--
        --outer--
        """

        let message = MIMEMessage(raw: raw)

        XCTAssertEqual(message.plainTextBody, "Plain fallback")
        XCTAssertEqual(message.htmlBody, "<html><body><p>Your code is</p><p><strong>777888</strong></p></body></html>")
    }

    func testSinglePartHtmlBodyIsExposedWhenTopLevelContentTypeMatches() {
        let raw = """
        Content-Type: text/html; charset="utf-8"

        <html><body><p>Code:</p><p>123123</p></body></html>
        """

        let message = MIMEMessage(raw: raw)

        XCTAssertEqual(message.plainTextBody, "<html><body><p>Code:</p><p>123123</p></body></html>")
        XCTAssertEqual(message.htmlBody, "<html><body><p>Code:</p><p>123123</p></body></html>")
    }

    func testDecodesBase64TextPart() {
        let raw = """
        Content-Type: text/plain; charset="utf-8"
        Content-Transfer-Encoding: base64

        WW91ciBjb2RlIGlzIDEyMzQ1Ng==
        """

        let message = MIMEMessage(raw: raw)

        XCTAssertEqual(message.plainTextBody, "Your code is 123456")
    }

    func testDecodesQuotedPrintableTextPart() {
        let raw = """
        Content-Type: text/plain; charset="utf-8"
        Content-Transfer-Encoding: quoted-printable

        Your code is 123=34=35=
        6
        """

        let message = MIMEMessage(raw: raw)

        XCTAssertEqual(message.plainTextBody, "Your code is 123456")
    }

    func testBoundaryTextInsideBodyDoesNotSplitPart() {
        let raw = """
        Content-Type: multipart/alternative; boundary="inner"

        --inner
        Content-Type: text/plain; charset="utf-8"

        Your code is 123456 and this text mentions --inner inline.
        --inner--
        """

        let message = MIMEMessage(raw: raw)

        XCTAssertEqual(message.plainTextBody, "Your code is 123456 and this text mentions --inner inline.")
    }
}
