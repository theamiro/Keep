import Foundation

final class InMemoryLoggingSource: LoggingSource, @unchecked Sendable {
    static let shared = InMemoryLoggingSource()

    private var store: [String: Log] = [:]
    private let queue = DispatchQueue(label: "com.keep.memory", attributes: .concurrent)

    private init() {}

    func store(_ log: Log) {
        performBarrier {
            store[log.id] = log
        }
    }

    func update(log: Log) {
        performBarrier {
            store[log.id] = log
        }
    }

    func deleteLog(withID id: String) {
        performBarrier {
            store.removeValue(forKey: id)
        }
    }

    func flush(completion: () -> Void) {
        performBarrier {
            store.removeAll()
            completion()
        }
    }

    func fetch() -> [Log] {
        queue.sync {
            let logs = Array(store.values)
            return logs.sorted { lhs, rhs in
                if lhs.pinned != rhs.pinned {
                    return lhs.pinned && !rhs.pinned
                }
                return lhs.timestamp > rhs.timestamp
            }
        }
    }

    private func performBarrier(_ block: () -> Void) {
        queue.sync(flags: .barrier, execute: block)
    }
}
