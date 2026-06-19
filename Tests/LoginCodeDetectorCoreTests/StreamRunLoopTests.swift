import Foundation
import XCTest
@testable import LoginCodeDetectorCore

final class StreamRunLoopTests: XCTestCase {
    func testScheduleAndUnscheduleMultipleStreamsDoesNotDeadlock() {
        let input = InputStream(data: Data())
        let output = OutputStream.toMemory()

        StreamRunLoop.shared.schedule(input)
        StreamRunLoop.shared.schedule(output)
        StreamRunLoop.shared.unschedule(input)
        StreamRunLoop.shared.unschedule(output)
    }
}
