import Foundation

/// Background multicore search for maybe-Class-IV rules (R-S).
///
/// Unlike the Python reference (which needs processes to escape the GIL),
/// Swift threads achieve true multicore parallelism, so workers are plain
/// threads. Each generates and screens its own random rules, pushing hits
/// into a bounded queue; when the queue is full workers block on the put
/// (R-S2), costing no CPU until a candidate is taken.
final class BoundedQueue<Element>: @unchecked Sendable {
    private let capacity: Int
    private var items: [Element] = []
    private let condition = NSCondition()

    init(capacity: Int) {
        self.capacity = capacity
    }

    /// Blocking put with timeout; returns false on timeout so callers can
    /// re-check their stop flag (R-S5).
    func put(_ item: Element, timeout: TimeInterval) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while items.count >= capacity {
            if !condition.wait(until: deadline) { return false }
        }
        items.append(item)
        return true
    }

    /// Non-blocking: take everything, waking blocked putters.
    func drainAll() -> [Element] {
        condition.lock()
        defer { condition.unlock() }
        let out = items
        items.removeAll()
        condition.broadcast()
        return out
    }
}

public final class CandidateSearch: @unchecked Sendable {
    public let workerCount: Int
    private let queue = BoundedQueue<String>(capacity: 32)
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var stopRequested = false
    private var started = false

    public init(workers: Int? = nil) {
        // Leave a core for the UI (R-S1).
        workerCount = workers
            ?? max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
    }

    private var stopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopRequested
    }

    public func start() {
        lock.lock()
        started = true
        lock.unlock()
        for _ in 0..<workerCount {
            DispatchQueue.global(qos: .utility).async(group: group) { [self] in
                var rng = Xoshiro256()  // per-worker OS-entropy seed; streams differ
                while !stopped {
                    let rule = Rule.random(using: &rng)
                    if Classifier.evaluate(rule, using: &rng).maybeIV {
                        while !stopped {
                            if queue.put(rule.id, timeout: 0.25) { break }
                        }
                    }
                }
            }
        }
    }

    /// Candidates found since the last drain (may be empty).
    public func drain() -> [Rule] {
        queue.drainAll().compactMap { try? Rule(id: $0) }
    }

    /// Safe to call even if start() never was (R-S5).
    public func stop() {
        lock.lock()
        stopRequested = true
        let wasStarted = started
        lock.unlock()
        if wasStarted {
            _ = group.wait(timeout: .now() + 2)
        }
    }
}
