import Foundation

/// A lock-protected, bounded buffer. When full, the oldest unprotected element is evicted first.
final class MemoryBuffer<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [Element] = []
    private let capacity: Int
    private let isProtected: @Sendable (Element) -> Bool
    private let order: @Sendable (Element, Element) -> Bool

    init(
        capacity: Int,
        isProtected: @escaping @Sendable (Element) -> Bool = { _ in false },
        order: @escaping @Sendable (Element, Element) -> Bool
    ) {
        self.capacity = max(1, capacity)
        self.isProtected = isProtected
        self.order = order
    }

    func append(_ element: Element) {
        lock.locked {
            elements.append(element)
            guard elements.count > capacity else { return }
            if let index = elements.firstIndex(where: { !isProtected($0) }) {
                elements.remove(at: index)
            } else {
                elements.removeFirst()
            }
        }
    }

    /// Returns the elements in display order (see `order`).
    func snapshot() -> [Element] {
        lock.locked { elements.sorted(by: order) }
    }

    /// Changes the first element matching `predicate`. Returns whether one was found.
    @discardableResult
    func modify(where predicate: (Element) -> Bool, _ change: (inout Element) -> Void) -> Bool {
        lock.locked {
            guard let index = elements.firstIndex(where: predicate) else { return false }
            change(&elements[index])
            return true
        }
    }

    func removeAll() {
        lock.locked { elements.removeAll() }
    }
}
