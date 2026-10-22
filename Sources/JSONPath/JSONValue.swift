/// Any JSON value. Used wherever the Arazzo Specification allows `Any`
/// (parameter values, request body payloads, specification extensions, JSON Schemas).
public enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object(OrderedDictionary<String, JSONValue>)
}

// MARK: - Accessors

extension JSONValue {
    public var isNull: Bool { if case .null = self { true } else { false } }

    public var boolValue: Bool? { if case .bool(let v) = self { v } else { nil } }

    public var stringValue: String? { if case .string(let v) = self { v } else { nil } }

    public var intValue: Int? {
        switch self {
        case .integer(let v): v
        case .number(let v) where v.rounded() == v && abs(v) < 9.0e18: Int(v)
        default: nil
        }
    }

    /// The numeric value of `.integer` or `.number`.
    public var doubleValue: Double? {
        switch self {
        case .integer(let v): Double(v)
        case .number(let v): v
        default: nil
        }
    }

    public var arrayValue: [JSONValue]? { if case .array(let v) = self { v } else { nil } }

    public var objectValue: OrderedDictionary<String, JSONValue>? {
        if case .object(let v) = self { v } else { nil }
    }

    /// Object member lookup. Returns `nil` for non-objects or missing keys.
    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    /// Object member lookup comparing names by Unicode code points (as JSON requires) rather than
    /// Swift's canonical equivalence (`"ü" == "u\u{308}"`).
    public func member(_ name: String) -> JSONValue? {
        guard case .object(let object) = self, let entry = object.entry(forKey: name),
            entry.key.unicodeScalars.elementsEqual(name.unicodeScalars)
        else { return nil }
        return entry.value
    }

    /// Array element lookup. Returns `nil` for non-arrays or out-of-range indices.
    public subscript(index: Int) -> JSONValue? {
        guard let array = arrayValue, array.indices.contains(index) else { return nil }
        return array[index]
    }

    /// `true` for objects and arrays.
    public var isStructured: Bool {
        switch self {
        case .array, .object: true
        default: false
        }
    }
}

// MARK: - Literals

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .integer(value) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(OrderedDictionary(elements)) }
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        if let container = try? decoder.container(keyedBy: JSONCodingKey.self) {
            var object = OrderedDictionary<String, JSONValue>()
            for key in container.allKeys {
                object[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
            }
            self = .object(object)
            return
        }
        if var container = try? decoder.unkeyedContainer() {
            var array: [JSONValue] = []
            if let count = container.count { array.reserveCapacity(count) }
            while !container.isAtEnd {
                array.append(try container.decode(JSONValue.self))
            }
            self = .array(array)
            return
        }
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .integer(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values { try container.encode(value) }
        case .object(let object):
            var container = encoder.container(keyedBy: JSONCodingKey.self)
            for (key, value) in object {
                try container.encode(value, forKey: JSONCodingKey(key))
            }
        }
    }
}

// MARK: - Serialization

extension JSONValue: CustomStringConvertible {
    /// A compact JSON (RFC 8259) serialization of the value. Object members keep their order.
    public var description: String { jsonString }

    /// A compact JSON (RFC 8259) serialization of the value. Object members keep their order.
    public var jsonString: String {
        var output = ""
        write(to: &output)
        return output
    }

    private func write(to output: inout String) {
        switch self {
        case .null: output += "null"
        case .bool(let v): output += v ? "true" : "false"
        case .integer(let v): output += String(v)
        case .number(let v):
            if v.isFinite, v.rounded() == v, abs(v) < 1e15 {
                output += String(Int(v))
            } else if v.isFinite {
                output += String(v)
            } else {
                output += "null"
            }
        case .string(let v): Self.writeString(v, to: &output)
        case .array(let values):
            output += "["
            for (index, value) in values.enumerated() {
                if index > 0 { output += "," }
                value.write(to: &output)
            }
            output += "]"
        case .object(let object):
            output += "{"
            for (index, element) in object.enumerated() {
                if index > 0 { output += "," }
                Self.writeString(element.key, to: &output)
                output += ":"
                element.value.write(to: &output)
            }
            output += "}"
        }
    }

    private static func writeString(_ string: String, to output: inout String) {
        output += "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case "\u{08}": output += "\\b"
            case "\u{0C}": output += "\\f"
            case let s where s.value < 0x20:
                let hex = String(s.value, radix: 16)
                output += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }
}
