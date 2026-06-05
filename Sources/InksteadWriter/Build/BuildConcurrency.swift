import Foundation

enum BuildConcurrency {
    private static let workerEnvironmentKey = "INKSTEAD_WRITER_WORKERS"
    private static let defaultWorkerLimit = 12

    static func workerCount(
        for itemCount: Int,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int {
        guard itemCount > 0 else { return 0 }
        let configured = environment[workerEnvironmentKey]
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .map { max(1, $0) }
        let limit = configured ?? min(max(1, ProcessInfo.processInfo.activeProcessorCount), defaultWorkerLimit)
        return min(itemCount, limit)
    }

    static func run<Element: Sendable>(
        _ items: [Element],
        body: @escaping @Sendable (Element) throws -> Void
    ) throws {
        guard items.count > 1 else {
            if let item = items.first {
                try body(item)
            }
            return
        }

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = workerCount(for: items.count)
        let errors = ParallelErrorBox()
        for item in items {
            queue.addOperation {
                do {
                    try body(item)
                } catch {
                    errors.setIfEmpty(error)
                }
            }
        }
        queue.waitUntilAllOperationsAreFinished()

        if let firstError = errors.firstError {
            throw firstError
        }
    }

    static func map<Element: Sendable, Output: Sendable>(
        _ items: [Element],
        transform: @escaping @Sendable (Element) throws -> Output
    ) throws -> [Output] {
        guard items.count > 1 else {
            if let item = items.first {
                return [try transform(item)]
            }
            return []
        }

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = workerCount(for: items.count)
        let errors = ParallelErrorBox()
        let results = ParallelResultsBox<Output>(count: items.count)
        for (index, item) in items.enumerated() {
            queue.addOperation {
                do {
                    results.set(try transform(item), at: index)
                } catch {
                    errors.setIfEmpty(error)
                }
            }
        }
        queue.waitUntilAllOperationsAreFinished()

        if let firstError = errors.firstError {
            throw firstError
        }
        return try results.values()
    }
}

private final class ParallelErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?

    var firstError: Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }

    func setIfEmpty(_ error: Error) {
        lock.lock()
        if storedError == nil {
            storedError = error
        }
        lock.unlock()
    }
}

private final class ParallelResultsBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [Value?]

    init(count: Int) {
        self.storedValues = Array(repeating: nil, count: count)
    }

    func set(_ value: Value, at index: Int) {
        lock.lock()
        storedValues[index] = value
        lock.unlock()
    }

    func values() throws -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        var output: [Value] = []
        output.reserveCapacity(storedValues.count)
        for value in storedValues {
            guard let value else {
                throw InksteadWriterError.io("Parallel work did not produce a result.")
            }
            output.append(value)
        }
        return output
    }
}
