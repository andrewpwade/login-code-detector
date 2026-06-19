import Foundation
import XCTest
@testable import LoginCodeDetectorCore

final class CodeExtractorTests: XCTestCase {
    private let extractor = CodeExtractor()

    func testDetectsLinkedInStyleStandaloneCode() {
        let body = """
        Enter the 6-digit code below to verify your identity and regain access to your LinkedIn account.

        471966
        """

        let result = extractor.detect(in: body).first

        XCTAssertEqual(result?.code, "471966")
        XCTAssertGreaterThanOrEqual(result?.score ?? 0, 90)
    }

    func testDetectsOneTimeCodeWithDigitsLanguage() {
        let body = """
        Enter these 6 digits where you requested your one-time code:

        752192
        """

        let result = extractor.detect(in: body).first

        XCTAssertEqual(result?.code, "752192")
        XCTAssertGreaterThanOrEqual(result?.score ?? 0, 90)
    }

    func testDetectsPasscodeWithLeadingZero() {
        let body = """
        Sign in with this one-time passcode

        Use this code to sign in to your Indeed account

        029029
        """

        let result = extractor.detect(in: body).first

        XCTAssertEqual(result?.code, "029029")
        XCTAssertGreaterThanOrEqual(result?.score ?? 0, 90)
    }

    func testExtractsCodeFromHTML() {
        let html = """
        <html><body><p>Use this code to sign in:</p><table><tr><td><strong>123456</strong></td></tr></table></body></html>
        """

        let text = HTMLTextExtractor.text(from: html)
        let result = extractor.detect(in: text).first

        XCTAssertEqual(result?.code, "123456")
    }

    func testDetectsChatGPTTemporaryLoginCodeFromHTML() {
        let html = """
        <table class="defanged6-main">
          <tbody><tr>
            <td>
              <p>Enter this temporary verification code to continue:</p>
              <p style="font-family:Menlo;font-size:24px;background-color:rgb(243, 243, 243);">

                841576

              </p>
              <p>
                If you were not trying to log in to ChatGPT, please
                <a href="https://u20216706.ct.sendgrid.net/ls/click?upn=u001.IQLfsj4kk-2BK7JhymNusRMmfwoG2v3nTgHW39">reset your password</a>.
              </p>
            </td>
          </tr></tbody>
        </table>
        """
        let event = MailEvent(
            uid: 1,
            sender: "noreply@tm.openai.com",
            subject: "Your temporary ChatGPT login code",
            receivedAt: Date(),
            plainTextBody: html,
            htmlBody: html
        )

        let result = extractor.bestCode(in: event)

        XCTAssertEqual(result?.code, "841576")
        XCTAssertGreaterThanOrEqual(result?.score ?? 0, 90)
    }

    func testNormalizesGroupedCode() {
        let body = "Your verification code is\n123-456"

        let result = extractor.detect(in: body).first

        XCTAssertEqual(result?.code, "123456")
    }

    func testSuppressesOrderNumbers() {
        let body = """
        Thanks for your order.
        Order number 471966
        Total $12.50
        """

        let result = extractor.detect(in: body).first

        XCTAssertLessThan(result?.score ?? 0, 70)
    }

    func testDoesNotCrashWhenMessageContainsIndexChangingUnicode() {
        let body = """
        İstanbul account security message
        Enter this temporary verification code to continue:

        841576
        """

        let result = extractor.detect(in: body).first

        XCTAssertEqual(result?.code, "841576")
    }

    func testExtractsCodeFromMultipartMessageWithFoldedHeaders() {
        let raw = """
        From: Example <noreply@example.com>
        Subject: Your verification
        Content-Type: multipart/alternative;
         boundary="XYZ"

        --XYZ
        Content-Type: text/plain; charset="utf-8"

        Your verification code is

        654321
        --XYZ
        Content-Type: text/html; charset="utf-8"

        <html><body><p>Your verification code is</p><p><strong>654321</strong></p></body></html>
        --XYZ--
        """

        let event = MailEvent(
            uid: 2,
            sender: "Example <noreply@example.com>",
            subject: "Your verification",
            receivedAt: Date(),
            plainTextBody: raw,
            htmlBody: nil
        )

        let result = extractor.bestCode(in: event)

        XCTAssertEqual(result?.code, "654321")
        XCTAssertGreaterThanOrEqual(result?.score ?? 0, 90)
    }

    func testExtractsCodeFromHtmlOnlyMultipartMessage() {
        let raw = """
        From: Example <noreply@example.com>
        Subject: Your login code
        Content-Type: multipart/alternative; boundary="ABC"

        --ABC
        Content-Type: text/plain; charset="utf-8"

        If you cannot read this message, view it in HTML.
        --ABC
        Content-Type: text/html; charset="utf-8"

        <html><body><p>Your login code is</p><p>112233</p></body></html>
        --ABC--
        """

        let event = MailEvent(
            uid: 3,
            sender: "Example <noreply@example.com>",
            subject: "Your login code",
            receivedAt: Date(),
            plainTextBody: raw,
            htmlBody: nil
        )

        let result = extractor.bestCode(in: event)

        XCTAssertEqual(result?.code, "112233")
        XCTAssertGreaterThanOrEqual(result?.score ?? 0, 90)
    }
}
