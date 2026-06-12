import Foundation
import XCTest
@testable import InksteadWriter

final class BuildConcurrencyTests: XCTestCase {
    private struct FirstError: Error {}
    private struct SecondError: Error {}

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    func testMapPreservesInputOrder() throws {
        let items = Array(0..<100)
        XCTAssertEqual(try BuildConcurrency.map(items) { $0 * 2 }, items.map { $0 * 2 })
    }

    func testRunReportsFirstErrorNotLaterOnes() {
        let items = Array(0..<32)
        XCTAssertThrowsError(try BuildConcurrency.run(items) { item in
            if item == 0 {
                throw FirstError()
            }
            Thread.sleep(forTimeInterval: 0.05)
            throw SecondError()
        }) { error in
            XCTAssertTrue(error is FirstError, "expected the first failure to win, got \(error)")
        }
    }

    func testRunCancelsRemainingWorkAfterFirstError() {
        let items = Array(0..<400)
        let executed = Counter()
        XCTAssertThrowsError(try BuildConcurrency.run(items) { item in
            executed.increment()
            if item == 0 {
                throw FirstError()
            }
            Thread.sleep(forTimeInterval: 0.01)
        })
        XCTAssertLessThan(executed.value, items.count, "remaining operations should be cancelled after the first error")
    }

    func testMapThrowsFirstErrorInsteadOfPartialResults() {
        XCTAssertThrowsError(try BuildConcurrency.map(Array(0..<64)) { item -> Int in
            if item == 0 {
                throw FirstError()
            }
            Thread.sleep(forTimeInterval: 0.005)
            return item
        }) { error in
            XCTAssertTrue(error is FirstError, "expected the first failure to win, got \(error)")
        }
    }
}
