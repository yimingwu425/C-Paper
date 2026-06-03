import Collections
import Foundation

struct DownloadQueue<Element>: Sendable where Element: Sendable {
    private var items = Deque<Element>()

    init(_ items: [Element] = []) {
        self.items = Deque(items)
    }

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    mutating func dequeue() -> Element? {
        items.popFirst()
    }

    mutating func enqueue(_ item: Element) {
        items.append(item)
    }

    mutating func append(contentsOf newItems: [Element]) {
        items.append(contentsOf: newItems)
    }

    mutating func removeAll() {
        items.removeAll()
    }
}
