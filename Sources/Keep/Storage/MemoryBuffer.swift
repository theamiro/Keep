import Foundation

/// A lock-protected, bounded buffer. When full, the oldest unprotected element is evicted first. With a `byteBudget`,
/// the oldest unprotected elements are also evicted until the summed `cost` of what is kept fits the budget.
final class MemoryBuffer<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [Element] = []
    private var keptCost = 0
    private let capacity: Int
    private let byteBudget: Int?
    private let cost: @Sendable (Element) -> Int
    private let isProtected: @Sendable (Element) -> Bool
    private let order: @Sendable (Element, Element) -> Bool

    init(
        capacity: Int,
        isProtected: @escaping @Sendable (Element) -> Bool = { _ in false },
        order: @escaping @Sendable (Element, Element) -> Bool,
        byteBudget: Int? = nil,
        cost: @escaping @Sendable (Element) -> Int = { _ in 0 }
    ) {
        self.capacity = max(1, capacity)
        self.isProtected = isProtected
        self.order = order
        self.byteBudget = byteBudget
        self.cost = cost
    }

    func append(_ element: Element) {
        lock.locked {
            elements.append(element)
            keptCost += cost(element)
            evictOverflow()
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
            let before = cost(elements[index])
            change(&elements[index])
            keptCost += cost(elements[index]) - before
            return true
        }
    }

    func removeAll() {
        lock.locked {
            elements.removeAll()
            keptCost = 0
        }
    }

    /// Evicts until the count and byte limits hold. The newest element is kept even when it alone exceeds the budget.
    private func evictOverflow() {
        while elements.count > capacity || (elements.count > 1 && exceedsBudget) {
            let index = elements.firstIndex(where: { !isProtected($0) }) ?? 0
            keptCost -= cost(elements.remove(at: index))
        }
    }

    private var exceedsBudget: Bool {
        guard let byteBudget else { return false }
        return keptCost > byteBudget
    }
}
