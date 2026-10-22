// Codable bridging between Swift types and `JSONValue`, preserving object member order
// (unlike `JSONDecoder`, whose keyed containers expose keys in no particular order).

/// Decodes `Decodable` values from a ``JSONValue`` tree, exposing object keys in document order.
///
/// ```swift
/// struct Pet: Decodable { let name: String }
/// let pets = try JSONValueDecoder().decode([Pet].self, from: JSONPath("$.pets[*]").values(in: document))
/// ```
public struct JSONValueDecoder {
    public var userInfo: [CodingUserInfoKey: any Sendable]

    public init(userInfo: [CodingUserInfoKey: any Sendable] = [:]) {
        self.userInfo = userInfo
    }

    public func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        try ValueDecoder(value: value, codingPath: [], userInfo: userInfo).decode(type)
    }

    /// Decodes each value of an array (e.g. the result of a JSONPath query).
    public func decode<T: Decodable>(_ type: T.Type, from values: [JSONValue]) throws -> [T] {
        try values.map { try decode(type, from: $0) }
    }
}

/// Encodes `Encodable` values into a ``JSONValue`` tree, keeping the order in which keys are encoded.
public struct JSONValueEncoder {
    public var userInfo: [CodingUserInfoKey: any Sendable]

    public init(userInfo: [CodingUserInfoKey: any Sendable] = [:]) {
        self.userInfo = userInfo
    }

    public func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        let root = EncodedNode()
        try ValueEncoder(node: root, codingPath: [], userInfo: userInfo).encode(value)
        return root.value
    }
}

extension JSONValue {
    /// Encodes any `Encodable` value as a `JSONValue`, preserving key order.
    public init(encoding value: some Encodable) throws {
        self = try JSONValueEncoder().encode(value)
    }

    /// Decodes this value as `T`.
    public func decode<T: Decodable>(as type: T.Type = T.self) throws -> T {
        try JSONValueDecoder().decode(type, from: self)
    }
}

// MARK: - Decoding

private struct ValueDecoder: Decoder {
    let value: JSONValue
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    init(value: JSONValue, codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: any Sendable]) {
        self.value = value
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    init(value: JSONValue, codingPath: [any CodingKey], anyUserInfo: [CodingUserInfoKey: Any]) {
        self.value = value
        self.codingPath = codingPath
        self.userInfo = anyUserInfo
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if type == JSONValue.self { return value as! T }
        return try T(from: self)
    }

    func mismatch(_ expected: String) -> DecodingError {
        DecodingError.typeMismatch(
            Any.self,
            .init(codingPath: codingPath, debugDescription: "Expected \(expected) but found \(value.typeName)."))
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .object(let object) = value else { throw mismatch("an object") }
        return KeyedDecodingContainer(KeyedContainer<Key>(object: object, decoder: self))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case .array(let array) = value else { throw mismatch("an array") }
        return UnkeyedContainer(array: array, decoder: self)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        SingleValueContainer(decoder: self)
    }

    func child(_ value: JSONValue, key: any CodingKey) -> ValueDecoder {
        ValueDecoder(value: value, codingPath: codingPath + [key], anyUserInfo: userInfo)
    }

    // Scalar conversions shared by the containers.

    func decodeBool() throws -> Bool {
        guard case .bool(let b) = value else { throw mismatch("a boolean") }
        return b
    }

    func decodeString() throws -> String {
        guard case .string(let s) = value else { throw mismatch("a string") }
        return s
    }

    func decodeDouble() throws -> Double {
        guard let d = value.doubleValue else { throw mismatch("a number") }
        return d
    }

    func decodeInteger<I: FixedWidthInteger>(_ type: I.Type) throws -> I {
        switch value {
        case .integer(let i):
            guard let result = I(exactly: i) else { throw overflow(type) }
            return result
        case .number(let d):
            guard d.isFinite, d.rounded() == d, let result = I(exactly: d) else { throw overflow(type) }
            return result
        default:
            throw mismatch("an integer")
        }
    }

    func overflow<I>(_ type: I.Type) -> DecodingError {
        DecodingError.dataCorrupted(
            .init(codingPath: codingPath, debugDescription: "\(value) does not fit in \(type)."))
    }
}

private struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let object: OrderedDictionary<String, JSONValue>
    let decoder: ValueDecoder

    var codingPath: [any CodingKey] { decoder.codingPath }
    var allKeys: [Key] { object.keys.compactMap { Key(stringValue: $0) } }

    func contains(_ key: Key) -> Bool { object[key.stringValue] != nil }

    func child(_ key: Key) throws -> ValueDecoder {
        guard let value = object[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key, .init(codingPath: codingPath, debugDescription: "No value associated with key '\(key.stringValue)'."))
        }
        return decoder.child(value, key: key)
    }

    func decodeNil(forKey key: Key) throws -> Bool { try child(key).value.isNull }
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try child(key).decodeBool() }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try child(key).decodeString() }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try child(key).decodeDouble() }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { Float(try child(key).decodeDouble()) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try child(key).decodeInteger(type) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try child(key).decodeInteger(type) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try child(key).decodeInteger(type) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try child(key).decodeInteger(type) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try child(key).decodeInteger(type) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try child(key).decodeInteger(type) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try child(key).decodeInteger(type) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try child(key).decodeInteger(type) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try child(key).decodeInteger(type) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try child(key).decodeInteger(type) }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T { try child(key).decode(type) }

    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard let value = object[key.stringValue], !value.isNull else { return nil }
        return try decoder.child(value, key: key).decode(type)
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws
        -> KeyedDecodingContainer<NestedKey>
    {
        try child(key).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        try child(key).unkeyedContainer()
    }

    func superDecoder() throws -> any Decoder {
        decoder.child(object["super"] ?? .null, key: JSONCodingKey("super"))
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        decoder.child(object[key.stringValue] ?? .null, key: key)
    }
}

private struct UnkeyedContainer: UnkeyedDecodingContainer {
    let array: [JSONValue]
    let decoder: ValueDecoder
    var currentIndex = 0

    init(array: [JSONValue], decoder: ValueDecoder) {
        self.array = array
        self.decoder = decoder
    }

    var codingPath: [any CodingKey] { decoder.codingPath }
    var count: Int? { array.count }
    var isAtEnd: Bool { currentIndex >= array.count }

    mutating func next() throws -> ValueDecoder {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                Any.self, .init(codingPath: codingPath, debugDescription: "Unkeyed container is at end."))
        }
        defer { currentIndex += 1 }
        return decoder.child(array[currentIndex], key: JSONCodingKey(intValue: currentIndex))
    }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else { return false }
        if array[currentIndex].isNull {
            currentIndex += 1
            return true
        }
        return false
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool { try next().decodeBool() }
    mutating func decode(_ type: String.Type) throws -> String { try next().decodeString() }
    mutating func decode(_ type: Double.Type) throws -> Double { try next().decodeDouble() }
    mutating func decode(_ type: Float.Type) throws -> Float { Float(try next().decodeDouble()) }
    mutating func decode(_ type: Int.Type) throws -> Int { try next().decodeInteger(type) }
    mutating func decode(_ type: Int8.Type) throws -> Int8 { try next().decodeInteger(type) }
    mutating func decode(_ type: Int16.Type) throws -> Int16 { try next().decodeInteger(type) }
    mutating func decode(_ type: Int32.Type) throws -> Int32 { try next().decodeInteger(type) }
    mutating func decode(_ type: Int64.Type) throws -> Int64 { try next().decodeInteger(type) }
    mutating func decode(_ type: UInt.Type) throws -> UInt { try next().decodeInteger(type) }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try next().decodeInteger(type) }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try next().decodeInteger(type) }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try next().decodeInteger(type) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try next().decodeInteger(type) }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T { try next().decode(type) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws
        -> KeyedDecodingContainer<NestedKey>
    {
        try next().container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        try next().unkeyedContainer()
    }

    mutating func superDecoder() throws -> any Decoder { try next() }
}

private struct SingleValueContainer: SingleValueDecodingContainer {
    let decoder: ValueDecoder
    var codingPath: [any CodingKey] { decoder.codingPath }

    func decodeNil() -> Bool { decoder.value.isNull }
    func decode(_ type: Bool.Type) throws -> Bool { try decoder.decodeBool() }
    func decode(_ type: String.Type) throws -> String { try decoder.decodeString() }
    func decode(_ type: Double.Type) throws -> Double { try decoder.decodeDouble() }
    func decode(_ type: Float.Type) throws -> Float { Float(try decoder.decodeDouble()) }
    func decode(_ type: Int.Type) throws -> Int { try decoder.decodeInteger(type) }
    func decode(_ type: Int8.Type) throws -> Int8 { try decoder.decodeInteger(type) }
    func decode(_ type: Int16.Type) throws -> Int16 { try decoder.decodeInteger(type) }
    func decode(_ type: Int32.Type) throws -> Int32 { try decoder.decodeInteger(type) }
    func decode(_ type: Int64.Type) throws -> Int64 { try decoder.decodeInteger(type) }
    func decode(_ type: UInt.Type) throws -> UInt { try decoder.decodeInteger(type) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try decoder.decodeInteger(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try decoder.decodeInteger(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try decoder.decodeInteger(type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try decoder.decodeInteger(type) }
    func decode<T: Decodable>(_ type: T.Type) throws -> T { try decoder.decode(type) }
}

// MARK: - Encoding

/// A mutable node of the tree being encoded; containers keep references so nested encodings
/// write through to their parent.
private final class EncodedNode {
    enum Kind {
        case empty
        case value(JSONValue)
        case object(ObjectStorage)
        case array(ArrayStorage)
    }

    final class ObjectStorage {
        var members = OrderedDictionary<String, EncodedNode>()
    }

    final class ArrayStorage {
        var elements: [EncodedNode] = []
    }

    var kind: Kind = .empty

    var value: JSONValue {
        switch kind {
        case .empty: .object([:])
        case .value(let v): v
        case .object(let storage): .object(storage.members.mapValues(\.value))
        case .array(let storage): .array(storage.elements.map(\.value))
        }
    }

    func objectStorage() -> ObjectStorage {
        if case .object(let storage) = kind { return storage }
        let storage = ObjectStorage()
        kind = .object(storage)
        return storage
    }

    func arrayStorage() -> ArrayStorage {
        if case .array(let storage) = kind { return storage }
        let storage = ArrayStorage()
        kind = .array(storage)
        return storage
    }
}

private struct ValueEncoder: Encoder {
    let node: EncodedNode
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    init(node: EncodedNode, codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: any Sendable]) {
        self.node = node
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    init(node: EncodedNode, codingPath: [any CodingKey], anyUserInfo: [CodingUserInfoKey: Any]) {
        self.node = node
        self.codingPath = codingPath
        self.userInfo = anyUserInfo
    }

    func encode<T: Encodable>(_ value: T) throws {
        if let json = value as? JSONValue {
            node.kind = .value(json)
            return
        }
        try value.encode(to: self)
    }

    func child(_ node: EncodedNode, key: any CodingKey) -> ValueEncoder {
        ValueEncoder(node: node, codingPath: codingPath + [key], anyUserInfo: userInfo)
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(KeyedEncoder<Key>(storage: node.objectStorage(), encoder: self))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        UnkeyedEncoder(storage: node.arrayStorage(), encoder: self)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        SingleValueEncoder(encoder: self)
    }

    static func number(_ value: Double, at codingPath: [any CodingKey]) throws -> JSONValue {
        guard value.isFinite else {
            throw EncodingError.invalidValue(value, .init(codingPath: codingPath, debugDescription: "\(value) is not valid JSON."))
        }
        return .number(value)
    }

    static func integer<I: FixedWidthInteger>(_ value: I) -> JSONValue {
        if let int = Int(exactly: value) { return .integer(int) }
        return .number(Double(value))
    }
}

private struct KeyedEncoder<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let storage: EncodedNode.ObjectStorage
    let encoder: ValueEncoder
    var codingPath: [any CodingKey] { encoder.codingPath }

    func set(_ value: JSONValue, _ key: Key) {
        let node = EncodedNode()
        node.kind = .value(value)
        storage.members[key.stringValue] = node
    }

    mutating func encodeNil(forKey key: Key) throws { set(.null, key) }
    mutating func encode(_ value: Bool, forKey key: Key) throws { set(.bool(value), key) }
    mutating func encode(_ value: String, forKey key: Key) throws { set(.string(value), key) }
    mutating func encode(_ value: Double, forKey key: Key) throws { set(try ValueEncoder.number(value, at: codingPath + [key]), key) }
    mutating func encode(_ value: Float, forKey key: Key) throws { set(try ValueEncoder.number(Double(value), at: codingPath + [key]), key) }
    mutating func encode(_ value: Int, forKey key: Key) throws { set(.integer(value), key) }
    mutating func encode(_ value: Int8, forKey key: Key) throws { set(ValueEncoder.integer(value), key) }
    mutating func encode(_ value: Int16, forKey key: Key) throws { set(ValueEncoder.integer(value), key) }
    mutating func encode(_ value: Int32, forKey key: Key) throws { set(ValueEncoder.integer(value), key) }
    mutating func encode(_ value: Int64, forKey key: Key) throws { set(ValueEncoder.integer(value), key) }
    mutating func encode(_ value: UInt, forKey key: Key) throws { set(ValueEncoder.integer(value), key) }
    mutating func encode(_ value: UInt8, forKey key: Key) throws { set(ValueEncoder.integer(value), key) }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { set(ValueEncoder.integer(value), key) }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { set(ValueEncoder.integer(value), key) }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { set(ValueEncoder.integer(value), key) }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        let node = EncodedNode()
        try encoder.child(node, key: key).encode(value)
        storage.members[key.stringValue] = node
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key)
        -> KeyedEncodingContainer<NestedKey>
    {
        let node = EncodedNode()
        storage.members[key.stringValue] = node
        return encoder.child(node, key: key).container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        let node = EncodedNode()
        storage.members[key.stringValue] = node
        return encoder.child(node, key: key).unkeyedContainer()
    }

    mutating func superEncoder() -> any Encoder {
        let node = EncodedNode()
        storage.members["super"] = node
        return encoder.child(node, key: JSONCodingKey("super"))
    }

    mutating func superEncoder(forKey key: Key) -> any Encoder {
        let node = EncodedNode()
        storage.members[key.stringValue] = node
        return encoder.child(node, key: key)
    }
}

private struct UnkeyedEncoder: UnkeyedEncodingContainer {
    let storage: EncodedNode.ArrayStorage
    let encoder: ValueEncoder
    var codingPath: [any CodingKey] { encoder.codingPath }
    var count: Int { storage.elements.count }

    func append(_ value: JSONValue) {
        let node = EncodedNode()
        node.kind = .value(value)
        storage.elements.append(node)
    }

    var nextKey: JSONCodingKey { JSONCodingKey(intValue: count) }

    mutating func encodeNil() throws { append(.null) }
    mutating func encode(_ value: Bool) throws { append(.bool(value)) }
    mutating func encode(_ value: String) throws { append(.string(value)) }
    mutating func encode(_ value: Double) throws { append(try ValueEncoder.number(value, at: codingPath + [nextKey])) }
    mutating func encode(_ value: Float) throws { append(try ValueEncoder.number(Double(value), at: codingPath + [nextKey])) }
    mutating func encode(_ value: Int) throws { append(.integer(value)) }
    mutating func encode(_ value: Int8) throws { append(ValueEncoder.integer(value)) }
    mutating func encode(_ value: Int16) throws { append(ValueEncoder.integer(value)) }
    mutating func encode(_ value: Int32) throws { append(ValueEncoder.integer(value)) }
    mutating func encode(_ value: Int64) throws { append(ValueEncoder.integer(value)) }
    mutating func encode(_ value: UInt) throws { append(ValueEncoder.integer(value)) }
    mutating func encode(_ value: UInt8) throws { append(ValueEncoder.integer(value)) }
    mutating func encode(_ value: UInt16) throws { append(ValueEncoder.integer(value)) }
    mutating func encode(_ value: UInt32) throws { append(ValueEncoder.integer(value)) }
    mutating func encode(_ value: UInt64) throws { append(ValueEncoder.integer(value)) }

    mutating func encode<T: Encodable>(_ value: T) throws {
        let node = EncodedNode()
        let key = nextKey
        storage.elements.append(node)
        try encoder.child(node, key: key).encode(value)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        let node = EncodedNode()
        let key = nextKey
        storage.elements.append(node)
        return encoder.child(node, key: key).container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        let node = EncodedNode()
        let key = nextKey
        storage.elements.append(node)
        return encoder.child(node, key: key).unkeyedContainer()
    }

    mutating func superEncoder() -> any Encoder {
        let node = EncodedNode()
        let key = nextKey
        storage.elements.append(node)
        return encoder.child(node, key: key)
    }
}

private struct SingleValueEncoder: SingleValueEncodingContainer {
    let encoder: ValueEncoder
    var codingPath: [any CodingKey] { encoder.codingPath }

    func set(_ value: JSONValue) { encoder.node.kind = .value(value) }

    mutating func encodeNil() throws { set(.null) }
    mutating func encode(_ value: Bool) throws { set(.bool(value)) }
    mutating func encode(_ value: String) throws { set(.string(value)) }
    mutating func encode(_ value: Double) throws { set(try ValueEncoder.number(value, at: codingPath)) }
    mutating func encode(_ value: Float) throws { set(try ValueEncoder.number(Double(value), at: codingPath)) }
    mutating func encode(_ value: Int) throws { set(.integer(value)) }
    mutating func encode(_ value: Int8) throws { set(ValueEncoder.integer(value)) }
    mutating func encode(_ value: Int16) throws { set(ValueEncoder.integer(value)) }
    mutating func encode(_ value: Int32) throws { set(ValueEncoder.integer(value)) }
    mutating func encode(_ value: Int64) throws { set(ValueEncoder.integer(value)) }
    mutating func encode(_ value: UInt) throws { set(ValueEncoder.integer(value)) }
    mutating func encode(_ value: UInt8) throws { set(ValueEncoder.integer(value)) }
    mutating func encode(_ value: UInt16) throws { set(ValueEncoder.integer(value)) }
    mutating func encode(_ value: UInt32) throws { set(ValueEncoder.integer(value)) }
    mutating func encode(_ value: UInt64) throws { set(ValueEncoder.integer(value)) }
    mutating func encode<T: Encodable>(_ value: T) throws { try encoder.encode(value) }
}

// MARK: - Pretty printing

extension JSONValue {
    /// Serializes the value as JSON text.
    /// - Parameters:
    ///   - prettyPrinted: indent nested values with two spaces.
    ///   - sortedKeys: sort object members by name instead of keeping their order.
    public func jsonString(prettyPrinted: Bool, sortedKeys: Bool = false) -> String {
        guard prettyPrinted || sortedKeys else { return jsonString }
        var output = ""
        write(to: &output, indent: prettyPrinted ? 0 : nil, sortedKeys: sortedKeys)
        return output
    }

    private func write(to output: inout String, indent: Int?, sortedKeys: Bool) {
        func newline(_ level: Int) {
            guard let _ = indent else { return }
            output += "\n" + String(repeating: "  ", count: level)
        }
        switch self {
        case .array(let values) where !values.isEmpty:
            output += "["
            for (index, value) in values.enumerated() {
                if index > 0 { output += "," }
                newline((indent ?? 0) + 1)
                value.write(to: &output, indent: indent.map { $0 + 1 }, sortedKeys: sortedKeys)
            }
            newline(indent ?? 0)
            output += "]"
        case .object(let object) where !object.isEmpty:
            output += "{"
            let keys = sortedKeys ? object.keys.sorted() : object.keys
            for (index, key) in keys.enumerated() {
                if index > 0 { output += "," }
                newline((indent ?? 0) + 1)
                output += JSONValue.string(key).jsonString + (indent == nil ? ":" : ": ")
                object[key]!.write(to: &output, indent: indent.map { $0 + 1 }, sortedKeys: sortedKeys)
            }
            newline(indent ?? 0)
            output += "}"
        default:
            output += jsonString
        }
    }
}
