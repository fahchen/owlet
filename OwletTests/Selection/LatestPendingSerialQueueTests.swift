import Foundation
import Synchronization
import Testing

@testable import Owlet

struct LatestPendingSerialQueueTests {
    /// While one job runs, only the newest submitted job is kept pending.
    @Test func keepsOneRunningAndLatestPending() {
        let worker = LatestPendingSerialQueue()
        let ran = Mutex<[Int]>([])
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        worker.submit {
            started.signal()
            release.wait()
            ran.withLock { $0.append(1) }
        }
        started.wait()
        for n in 2...4 {
            worker.submit {
                ran.withLock { $0.append(n) }
                done.signal()
            }
        }
        release.signal()
        _ = done.wait(timeout: .now() + 1)
        worker.submit { done.signal() }
        _ = done.wait(timeout: .now() + 1)
        #expect(ran.withLock { $0 } == [1, 4])
    }
}
