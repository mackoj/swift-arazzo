import JSONPath
/// Specification extensions: patterned fields prefixed by `x-`.
public typealias VendorExtensions = OrderedDictionary<String, JSONValue>

/// A type that may carry [Specification Extensions](https://spec.openapis.org/arazzo/latest.html#specification-extensions).
public protocol VendorExtendable {
    var vendorExtensions: VendorExtensions { get set }
}

extension VendorExtendable {
    /// Looks up a specification extension. The `x-` prefix is added if missing.
    public subscript(extension name: String) -> JSONValue? {
        get { vendorExtensions[Self.normalizedExtensionName(name)] }
        set { vendorExtensions[Self.normalizedExtensionName(name)] = newValue }
    }

    static func normalizedExtensionName(_ name: String) -> String {
        name.lowercased().hasPrefix("x-") ? name : "x-" + name
    }
}

/// Options controlling how Arazzo documents are decoded.
///
/// Pass them through `userInfo` on your decoder:
/// ```swift
/// let decoder = JSONDecoder()
/// decoder.userInfo[Arazzo.DecodingOptions.key] = Arazzo.DecodingOptions(strict: true)
/// ```
extension Arazzo {
    public struct DecodingOptions: Sendable {
        /// When `true`, properties that are neither fixed fields nor `x-` extensions
        /// cause decoding to fail, as do fields that are irrelevant to the chosen
        /// action `type` (for example `retryLimit` on a `goto` failure action).
        public var strict: Bool

        public init(strict: Bool = false) {
            self.strict = strict
        }

        public static let key = CodingUserInfoKey(rawValue: "ArazzoKit.DecodingOptions")!
    }
}

extension Decoder {
    var arazzoOptions: Arazzo.DecodingOptions {
        (userInfo[Arazzo.DecodingOptions.key] as? Arazzo.DecodingOptions) ?? Arazzo.DecodingOptions()
    }

    /// Decodes every `x-` prefixed property of the current object.
    func decodeVendorExtensions() throws -> VendorExtensions {
        let container = try container(keyedBy: AnyCodingKey.self)
        var extensions = VendorExtensions()
        for key in container.allKeys where key.stringValue.lowercased().hasPrefix("x-") {
            extensions[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        return extensions
    }

    /// In strict mode, fails if the object contains properties other than the given fixed fields
    /// (and `x-` extensions, when `allowExtensions` is `true`).
    func ensureNoUnknownKeys<K: CodingKey & CaseIterable>(
        _ keys: K.Type, objectName: String, allowExtensions: Bool = true
    ) throws {
        guard arazzoOptions.strict else { return }
        let container = try container(keyedBy: AnyCodingKey.self)
        let known = Set(K.allCases.map(\.stringValue))
        let unknown = container.allKeys.map(\.stringValue).filter { key in
            !known.contains(key) && !(allowExtensions && key.lowercased().hasPrefix("x-"))
        }
        guard unknown.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: codingPath,
                    debugDescription:
                        "\(objectName) contains unsupported properties: \(unknown.sorted().joined(separator: ", "))."
                ))
        }
    }
}

extension Encoder {
    func encodeVendorExtensions(_ extensions: VendorExtensions) throws {
        guard !extensions.isEmpty else { return }
        var container = container(keyedBy: AnyCodingKey.self)
        for (key, value) in extensions {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
    }
}

extension KeyedDecodingContainer {
    /// Decodes an array that defaults to empty when the key is absent.
    func decodeList<T: Decodable>(_ type: [T].Type, forKey key: Key) throws -> [T] {
        try decodeIfPresent(type, forKey: key) ?? []
    }
}

extension KeyedEncodingContainer {
    /// Encodes a collection only when it is non-empty.
    mutating func encodeNonEmpty<C: Encodable & Collection>(_ value: C, forKey key: Key) throws {
        if !value.isEmpty { try encode(value, forKey: key) }
    }
}

func decodingError(_ message: String, codingPath: [any CodingKey]) -> DecodingError {
    DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: message))
}
