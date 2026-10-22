extension JSONValue {
    /// An error raised while parsing JSON text.
    public struct ParseError: Error, Hashable, Sendable, CustomStringConvertible {
        public let message: String
        /// The byte offset in the UTF-8 input where the error was detected.
        public let offset: Int
        public var description: String { "Invalid JSON at offset \(offset): \(message)" }
    }

    /// Parses JSON text (RFC 8259), preserving the order of object members.
    ///
    /// Integers that fit in `Int` become ``integer(_:)``; other numbers become ``number(_:)``.
    /// When an object repeats a member name, the last value wins (at the first position).
    public init(parsing text: String) throws {
        var copy = text
        self = try copy.withUTF8 { buffer in
            var parser = JSONTextParser(buffer)
            return try parser.parseDocument()
        }
    }

    /// Parses UTF-8 encoded JSON text.
    public init(parsing bytes: some Collection<UInt8>) throws {
        let array = Array(bytes)
        self = try array.withUnsafeBufferPointer { buffer in
            var parser = JSONTextParser(buffer)
            return try parser.parseDocument()
        }
    }
}

struct JSONTextParser {
    let bytes: UnsafeBufferPointer<UInt8>
    var index = 0
    var depth = 0
    static let maximumDepth = 512

    init(_ bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    func fail(_ message: String) -> JSONValue.ParseError {
        JSONValue.ParseError(message: message, offset: index)
    }

    mutating func parseDocument() throws -> JSONValue {
        // Skip a UTF-8 byte order mark.
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { index = 3 }
        skipWhitespace()
        let value = try parseValue()
        skipWhitespace()
        guard index == bytes.count else { throw fail("unexpected trailing characters") }
        return value
    }

    mutating func skipWhitespace() {
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D: index += 1
            default: return
            }
        }
    }

    mutating func parseValue() throws -> JSONValue {
        guard index < bytes.count else { throw fail("unexpected end of input") }
        switch bytes[index] {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): try expectLiteral("true"); return .bool(true)
        case UInt8(ascii: "f"): try expectLiteral("false"); return .bool(false)
        case UInt8(ascii: "n"): try expectLiteral("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try parseNumber()
        default: throw fail("unexpected character")
        }
    }

    mutating func expectLiteral(_ literal: StaticString) throws {
        let count = literal.utf8CodeUnitCount
        guard index + count <= bytes.count else { throw fail("invalid literal") }
        for offset in 0..<count where bytes[index + offset] != literal.utf8Start[offset] {
            throw fail("invalid literal")
        }
        index += count
    }

    mutating func parseObject() throws -> JSONValue {
        depth += 1
        defer { depth -= 1 }
        guard depth <= Self.maximumDepth else { throw fail("nesting too deep") }
        index += 1
        var object = OrderedDictionary<String, JSONValue>()
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            return .object(object)
        }
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw fail("expected a member name") }
            let key = try parseString()
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw fail("expected ':'") }
            index += 1
            skipWhitespace()
            object[key] = try parseValue()
            skipWhitespace()
            guard index < bytes.count else { throw fail("unterminated object") }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            if bytes[index] == UInt8(ascii: "}") {
                index += 1
                return .object(object)
            }
            throw fail("expected ',' or '}'")
        }
    }

    mutating func parseArray() throws -> JSONValue {
        depth += 1
        defer { depth -= 1 }
        guard depth <= Self.maximumDepth else { throw fail("nesting too deep") }
        index += 1
        var array: [JSONValue] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
            index += 1
            return .array(array)
        }
        while true {
            skipWhitespace()
            array.append(try parseValue())
            skipWhitespace()
            guard index < bytes.count else { throw fail("unterminated array") }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            if bytes[index] == UInt8(ascii: "]") {
                index += 1
                return .array(array)
            }
            throw fail("expected ',' or ']'")
        }
    }

    mutating func parseNumber() throws -> JSONValue {
        let start = index
        var isInteger = true
        if bytes[index] == UInt8(ascii: "-") { index += 1 }
        guard index < bytes.count, isDigit(bytes[index]) else { throw fail("invalid number") }
        if bytes[index] == UInt8(ascii: "0") {
            index += 1
            if index < bytes.count, isDigit(bytes[index]) { throw fail("leading zeros are not allowed") }
        } else {
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            isInteger = false
            index += 1
            guard index < bytes.count, isDigit(bytes[index]) else { throw fail("invalid fraction") }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            isInteger = false
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                index += 1
            }
            guard index < bytes.count, isDigit(bytes[index]) else { throw fail("invalid exponent") }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<index]), as: UTF8.self)
        if isInteger, let int = Int(text) { return .integer(int) }
        guard let double = Double(text) else { throw fail("invalid number") }
        return .number(double)
    }

    func isDigit(_ byte: UInt8) -> Bool { byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }

    mutating func parseString() throws -> String {
        index += 1  // opening quote
        var scalars = String.UnicodeScalarView()
        var runStart = index
        func flushRun(_ end: Int, into scalars: inout String.UnicodeScalarView) {
            if end > runStart {
                scalars.append(
                    contentsOf: String(decoding: UnsafeBufferPointer(rebasing: bytes[runStart..<end]), as: UTF8.self)
                        .unicodeScalars)
            }
        }
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                flushRun(index, into: &scalars)
                index += 1
                return String(scalars)
            }
            if byte < 0x20 { throw fail("unescaped control character in string") }
            if byte == UInt8(ascii: "\\") {
                flushRun(index, into: &scalars)
                index += 1
                guard index < bytes.count else { throw fail("unterminated escape") }
                let escaped = bytes[index]
                index += 1
                switch escaped {
                case UInt8(ascii: "\""): scalars.append("\"")
                case UInt8(ascii: "\\"): scalars.append("\\")
                case UInt8(ascii: "/"): scalars.append("/")
                case UInt8(ascii: "b"): scalars.append("\u{08}")
                case UInt8(ascii: "f"): scalars.append("\u{0C}")
                case UInt8(ascii: "n"): scalars.append("\n")
                case UInt8(ascii: "r"): scalars.append("\r")
                case UInt8(ascii: "t"): scalars.append("\t")
                case UInt8(ascii: "u"):
                    let high = try parseHex4()
                    if (0xD800...0xDBFF).contains(high) {
                        guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"),
                            bytes[index + 1] == UInt8(ascii: "u")
                        else { throw fail("unpaired surrogate") }
                        index += 2
                        let low = try parseHex4()
                        guard (0xDC00...0xDFFF).contains(low) else { throw fail("invalid low surrogate") }
                        let value = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
                        scalars.append(Unicode.Scalar(value)!)
                    } else if (0xDC00...0xDFFF).contains(high) {
                        throw fail("unpaired surrogate")
                    } else {
                        scalars.append(Unicode.Scalar(high)!)
                    }
                default:
                    throw fail("invalid escape sequence")
                }
                runStart = index
                continue
            }
            index += 1
        }
        throw fail("unterminated string")
    }

    mutating func parseHex4() throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw fail("invalid unicode escape") }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            let digit: UInt32
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - UInt8(ascii: "A") + 10)
            default: throw fail("invalid unicode escape")
            }
            value = value * 16 + digit
            index += 1
        }
        return value
    }
}
