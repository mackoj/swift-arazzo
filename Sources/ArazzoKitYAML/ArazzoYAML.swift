// YAML support is compiled only with the `YAML` package trait (always on with Swift 6.0).
#if YAML
import ArazzoKit
import Yams

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Arazzo.Document {
    /// Decodes an Arazzo Description from YAML (or JSON, which is valid YAML 1.2).
    ///
    /// Map ordering in the source document is preserved.
    public init(yaml: String, options: Arazzo.DecodingOptions = .init()) throws {
        let decoder = YAMLDecoder()
        self = try decoder.decode(Self.self, from: yaml, userInfo: [Arazzo.DecodingOptions.key: options])
    }

    /// Decodes an Arazzo Description from UTF-8 YAML (or JSON) data.
    public init(yaml data: Data, options: Arazzo.DecodingOptions = .init()) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "The data is not valid UTF-8."))
        }
        try self.init(yaml: string, options: options)
    }

    /// Decodes an Arazzo Description, detecting JSON vs. YAML from the content.
    public init(contentsOf data: Data, options: Arazzo.DecodingOptions = .init()) throws {
        let firstNonWhitespace = data.first { !(" \t\r\n" as String).utf8.contains($0) }
        if firstNonWhitespace == UInt8(ascii: "{") {
            try self.init(json: data, options: options)
        } else {
            try self.init(yaml: data, options: options)
        }
    }

    /// Encodes the description as YAML, preserving field order.
    public func yamlString(sortKeys: Bool = false) throws -> String {
        let encoder = YAMLEncoder()
        encoder.options.sortKeys = sortKeys
        encoder.options.allowUnicode = true
        return try encoder.encode(self)
    }
}

/// A YAML coder for any Arazzo type (documents, workflows, steps, ...).
public enum ArazzoYAML {
    public static func decode<T: Decodable>(
        _ type: T.Type, from yaml: String, options: Arazzo.DecodingOptions = .init()
    ) throws -> T {
        try YAMLDecoder().decode(type, from: yaml, userInfo: [Arazzo.DecodingOptions.key: options])
    }

    public static func encode<T: Encodable>(_ value: T, sortKeys: Bool = false) throws -> String {
        let encoder = YAMLEncoder()
        encoder.options.sortKeys = sortKeys
        encoder.options.allowUnicode = true
        return try encoder.encode(value)
    }
}
#endif
