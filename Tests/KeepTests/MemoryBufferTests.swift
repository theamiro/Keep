import Foundation
import Testing

@testable import Keep

@Suite("Memory buffer")
struct MemoryBufferTests {
    @Test func evictsOldestWhenFull() {
        let buffer = MemoryBuffer<Int>(capacity: 2, order: { $0 < $1 })
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        #expect(buffer.snapshot() == [2, 3])
    }

    @Test func protectedElementsSurviveEviction() {
        let buffer = MemoryBuffer<Int>(capacity: 2, isProtected: { $0 == 1 }, order: { $0 < $1 })
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        #expect(buffer.snapshot() == [1, 3])
    }

    @Test func modifyChangesOnlyTheMatchingElement() {
        let buffer = MemoryBuffer<Int>(capacity: 5, order: { $0 < $1 })
        buffer.append(1)
        buffer.append(2)
        let found = buffer.modify(where: { $0 == 2 }) { $0 = 20 }
        #expect(found)
        #expect(buffer.snapshot() == [1, 20])
        #expect(buffer.modify(where: { $0 == 99 }) { _ in } == false)
    }

    @Test func concurrentAppendsAreAllKept() {
        let buffer = MemoryBuffer<Int>(capacity: 10000, order: { $0 < $1 })
        DispatchQueue.concurrentPerform(iterations: 1000) { buffer.append($0) }
        #expect(buffer.snapshot().count == 1000)
    }
}
