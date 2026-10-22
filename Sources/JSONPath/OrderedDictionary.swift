/// A dictionary that remembers the order in which keys were inserted.
///
/// Arazzo documents are frequently authored by hand, and the order of map entries
/// (outputs, components, JSON Schema properties, ...) carries meaning for readers.
/// `OrderedDictionary` preserves that order through decoding and encoding whenever
/// the underlying decoder exposes keys in document order (YAML via Yams does).
///
/// Equality and hashing are **order-insensitive**, matching JSON object semantics.
public struct OrderedDictionary<Key: Hashable, Value> {
    public private(set) var keys: [Key]
    private var storage: [Key: Value]

    public init() {
        keys = []
        storage = [:]
    }

    /// Creates an ordered dictionary from a sequence of pairs. Later duplicates win
    /// but keep the position of the first occurrence.
    public init<S: Sequence>(_ elements: S) where S.Element == (Key, Value) {
        self.init()
        for (key, value) in elements { self[key] = value }
    }

    public var values: [Value] { keys.map { storage[$0]! } }
    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }

    public subscript(key: Key) -> Value? {
        get { storage[key] }
        set {
            if let newValue {
                if storage.updateValue(newValue, forKey: key) == nil {
                    keys.append(key)
                }
            } else {
                removeValue(forKey: key)
            }
        }
    }

    @discardableResult
    public mutating func removeValue(forKey key: Key) -> Value? {
        guard let value = storage.removeValue(forKey: key) else { return nil }
        keys.removeAll { $0 == key }
        return value
    }

    public func contains(key: Key) -> Bool { storage[key] != nil }

    /// The stored key equal to `key` and its value. (Swift `String` equality is canonical-equivalence
    /// based; callers that need code-point equality compare the returned key.)
    func entry(forKey key: Key) -> (key: Key, value: Value)? {
        guard let index = storage.index(forKey: key) else { return nil }
        return storage[index]
    }

    public func mapValues<T>(_ transform: (Value) throws -> T) rethrows -> OrderedDictionary<Key, T> {
        var result = OrderedDictionary<Key, T>()
        for key in keys { result[key] = try transform(storage[key]!) }
        return result
    }

    public func compactMapValues<T>(_ transform: (Value) throws -> T?) rethrows -> OrderedDictionary<Key, T> {
        var result = OrderedDictionary<Key, T>()
        for key in keys {
            if let value = try transform(storage[key]!) { result[key] = value }
        }
        return result
    }

    public func filter(_ isIncluded: ((key: Key, value: Value)) throws -> Bool) rethrows -> OrderedDictionary {
        var result = OrderedDictionary()
        for element in self where try isIncluded(element) { result[element.key] = element.value }
        return result
    }

    /// An unordered view of the contents.
    public var dictionary: [Key: Value] { storage }
}

extension OrderedDictionary: RandomAccessCollection {
    public typealias Element = (key: Key, value: Value)
    public typealias Index = Int

    public var startIndex: Int { 0 }
    public var endIndex: Int { keys.count }

    public subscript(position: Int) -> Element {
        let key = keys[position]
        return (key, storage[key]!)
    }
}

extension OrderedDictionary: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (Key, Value)...) {
        self.init(elements)
    }
}

extension OrderedDictionary: Equatable where Value: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.storage == rhs.storage }
}

extension OrderedDictionary: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(storage) }
}

extension OrderedDictionary: Sendable where Key: Sendable, Value: Sendable {}

extension OrderedDictionary: CustomStringConvertible {
    public var description: String {
        "[" + map { "\($0.key): \($0.value)" }.joined(separator: ", ") + "]"
    }
}

extension OrderedDictionary: Decodable where Key == String, Value: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: JSONCodingKey.self)
        self.init()
        for key in container.allKeys {
            self[key.stringValue] = try container.decode(Value.self, forKey: key)
        }
    }
}

extension OrderedDictionary: Encodable where Key == String, Value: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: JSONCodingKey.self)
        for (key, value) in self {
            try container.encode(value, forKey: JSONCodingKey(key))
        }
    }
}
