import Foundation

/// Dedicated thread and run loop for Foundation stream scheduling.
/// Keeping streams off the main run loop avoids coupling IMAP network progress to UI event processing.
final class StreamRunLoop: NSObject, @unchecked Sendable {
    static let shared = StreamRunLoop()

    private let ready = DispatchSemaphore(value: 0)
    private let initLock = NSLock()
    private var isReady = false
    private var runLoop: RunLoop?
    private lazy var thread: Thread = {
        let thread = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = .current
            self.setReady()
            while !Thread.current.isCancelled {
                self.runLoop?.run(mode: .default, before: .distantFuture)
            }
        }
        thread.name = "LoginCodeDetectorCore.StreamRunLoop"
        thread.start()
        return thread
    }()

    func schedule(_ stream: Stream) {
        _ = thread
        waitUntilReady()
        perform(#selector(scheduleStream(_:)), on: thread, with: stream, waitUntilDone: true)
    }

    func unschedule(_ stream: Stream) {
        _ = thread
        waitUntilReady()
        perform(#selector(unscheduleStream(_:)), on: thread, with: stream, waitUntilDone: true)
    }

    @objc private func scheduleStream(_ stream: Stream) {
        stream.schedule(in: .current, forMode: .default)
    }

    @objc private func unscheduleStream(_ stream: Stream) {
        stream.remove(from: .current, forMode: .default)
    }

    private func setReady() {
        initLock.lock()
        isReady = true
        initLock.unlock()
        ready.signal()
    }

    private func waitUntilReady() {
        initLock.lock()
        let readyNow = isReady
        initLock.unlock()
        if !readyNow {
            ready.wait()
        }
    }
}
