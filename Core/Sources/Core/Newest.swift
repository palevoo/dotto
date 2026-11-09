import Foundation

/// The newest word on one thing wins, whatever order the words arrive in. A mark remembers
/// the event that set it and takes a newer event's word, never an older one's, so the fold
/// reaches the same state from any order of arrival. Labels, names, links, done and loop
/// receipts are all marks of this kind; the rest of the mark is read through it as if it
/// were the value itself.
@dynamicMemberLookup
public struct Newest<Value: Hashable & Sendable>: Hashable, Sendable {
    /// The event that set the value.
    public private(set) var id: ULID
    public private(set) var value: Value

    public init(_ value: Value, by id: ULID) {
        self.id = id
        self.value = value
    }

    /// Takes the word if its event is newer than the one that set the mark. Says whether it did.
    @discardableResult
    public mutating func take(_ value: Value, by id: ULID) -> Bool {
        guard id > self.id else { return false }
        self.id = id
        self.value = value
        return true
    }

    public subscript<T>(dynamicMember keyPath: KeyPath<Value, T>) -> T {
        value[keyPath: keyPath]
    }
}

extension Dictionary {
    /// Marks a key with a word, if the mark has nothing yet or the word is newer. Says
    /// whether the word now stands.
    @discardableResult
    public mutating func mark<V>(_ key: Key, _ value: V, by id: ULID) -> Bool where Value == Newest<V> {
        if var mark = self[key] {
            let taken = mark.take(value, by: id)
            self[key] = mark
            return taken
        }
        self[key] = Newest(value, by: id)
        return true
    }
}
