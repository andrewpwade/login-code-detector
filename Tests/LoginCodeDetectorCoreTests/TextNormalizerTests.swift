import XCTest
@testable import LoginCodeDetectorCore

final class TextNormalizerTests: XCTestCase {
    func testNormalizeStandardizesLineEndingsCollapsesBlankRunsAndTrimsEdges() {
        let input = "\r\n  One \rThree  \n\n\n Four \r\n"

        let result = TextNormalizer.normalize(input)

        XCTAssertEqual(result, "One\nThree\nFour")
    }
}
