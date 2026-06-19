import XCTest
@testable import LoginCodeDetectorCore

final class HTMLTextExtractorTests: XCTestCase {
    func testTextRemovesScriptAndStyleContent() {
        let html = """
        <html>
          <head>
            <style>.otp { letter-spacing: 2px; }</style>
            <script>window.code = "999999"</script>
          </head>
          <body>
            <p>Your verification code is</p>
            <div class="otp">123456</div>
          </body>
        </html>
        """

        let result = HTMLTextExtractor.text(from: html)

        XCTAssertTrue(result.contains("Your verification code is"))
        XCTAssertTrue(result.contains("123456"))
        XCTAssertFalse(result.contains("999999"))
        XCTAssertFalse(result.contains("letter-spacing"))
    }

    func testTextDecodesEntitiesAndPreservesBlockBoundaries() {
        let html = """
        <p>Use&nbsp;this code&nbsp;to sign in:</p><p>654321</p><br><div>Thanks &amp; welcome</div>
        """

        let result = HTMLTextExtractor.text(from: html)

        XCTAssertTrue(result.contains("654321"))
        XCTAssertTrue(result.contains("Thanks & welcome"))
        XCTAssertFalse(result.contains("&amp;"))
    }
}
