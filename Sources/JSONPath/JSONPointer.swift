/// A [JSON Pointer (RFC 6901)](https://www.rfc-editor.org/rfc/rfc6901).
public struct JSONPointer: Hashable, Sendable, CustomStringConvertible, Codable {
    /// The unescaped reference tokens.
    public var tokens: [String]

    public init(tokens: [String]) {
        self.tokens = tokens
    }

    /// The pointer that references the whole document (`""`).
    public static let root = JSONPointer(tokens: [])

    public struct ParseError: Error, Hashable, Sendable, CustomStringConvertible {
        public let pointer: String
        public let message: String
        public var description: String { "Invalid JSON Pointer '\(pointer)': \(message)" }
    }

    /// Parses a pointer such as `/paths/~1pets/get`. A leading `#` (URI fragment form) is accepted.
    public init(_ string: String) throws {
        var text = Substring(string)
        if text.first == "#" { text = text.dropFirst() }
        if text.isEmpty {
            tokens = []
            return
        }
        guard text.first == "/" else {
            throw ParseError(pointer: string, message: "a non-empty pointer must start with '/'")
        }
        var tokens: [String] = []
        for rawToken in text.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
            var token = ""
            var iterator = rawToken.makeIterator()
            while let character = iterator.next() {
                if character == "~" {
                    switch iterator.next() {
                    case "0": token.append("~")
                    case "1": token.append("/")
                    default:
                        throw ParseError(pointer: string, message: "'~' must be followed by '0' or '1'")
                    }
                } else {
                    token.append(character)
                }
            }
            tokens.append(token)
        }
        self.tokens = tokens
    }

    /// The escaped string form, e.g. `/paths/~1pets/get`.
    public var description: String {
        tokens.map { "/" + $0.replacingAll("~", with: "~0").replacingAll("/", with: "~1") }.joined()
    }

    /// Resolves the pointer against a JSON value. Returns `nil` when a token cannot be resolved.
    public func resolve(in value: JSONValue) -> JSONValue? {
        var current = value
        for token in tokens {
            switch current {
            case .object(let object):
                guard let next = object[token] else { return nil }
                current = next
            case .array(let array):
                guard let index = Self.arrayIndex(token), array.indices.contains(index) else { return nil }
                current = array[index]
            default:
                return nil
            }
        }
        return current
    }

    /// Appends a token.
    public func appending(_ token: String) -> JSONPointer {
        JSONPointer(tokens: tokens + [token])
    }

    static func arrayIndex(_ token: String) -> Int? {
        guard !token.isEmpty, token.allSatisfy(\.isASCIIDigit) else { return nil }
        if token.count > 1 && token.first == "0" { return nil }
        return Int(token)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        do {
            try self.init(string)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "\(error)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
