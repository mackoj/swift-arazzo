import JSONPath
extension Arazzo {
    /// Metadata about the workflows contained within the Arazzo Description.
    public struct Info: Hashable, Sendable, VendorExtendable {
        public var title: String
        public var summary: String?
        /// CommonMark may be used.
        public var description: String?
        /// The version of the Arazzo document (distinct from the specification version).
        public var version: String
        public var vendorExtensions: VendorExtensions

        public init(
            title: String,
            summary: String? = nil,
            description: String? = nil,
            version: String,
            vendorExtensions: VendorExtensions = [:]
        ) {
            self.title = title
            self.summary = summary
            self.description = description
            self.version = version
            self.vendorExtensions = vendorExtensions
        }
    }

    /// A source description (OpenAPI, AsyncAPI or Arazzo document) the workflows apply to.
    public struct SourceDescription: Hashable, Sendable, VendorExtendable {
        public enum SourceType: String, Hashable, Sendable, Codable, CaseIterable {
            case openapi
            case asyncapi
            case arazzo
        }

        /// A unique name for the source description. SHOULD match `[A-Za-z0-9_\-]+`.
        public var name: String
        /// A URI-reference to the source description.
        public var url: String
        public var type: SourceType?
        public var vendorExtensions: VendorExtensions

        public init(name: String, url: String, type: SourceType? = nil, vendorExtensions: VendorExtensions = [:]) {
            self.name = name
            self.url = url
            self.type = type
            self.vendorExtensions = vendorExtensions
        }
    }
}

extension Arazzo.Info: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case title, summary, description, version
    }

    public init(from decoder: any Decoder) throws {
        try decoder.ensureNoUnknownKeys(CodingKeys.self, objectName: "Info Object")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        version = try container.decodeLenientString(forKey: .version)
        vendorExtensions = try decoder.decodeVendorExtensions()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(version, forKey: .version)
        try encoder.encodeVendorExtensions(vendorExtensions)
    }
}

extension Arazzo.SourceDescription: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, url, type
    }

    public init(from decoder: any Decoder) throws {
        try decoder.ensureNoUnknownKeys(CodingKeys.self, objectName: "Source Description Object")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        if let rawType = try container.decodeIfPresent(String.self, forKey: .type) {
            guard let type = SourceType(rawValue: rawType) else {
                throw decodingError(
                    "Source description type '\(rawType)' is not one of openapi, asyncapi, arazzo.",
                    codingPath: container.codingPath + [CodingKeys.type])
            }
            self.type = type
        } else {
            type = nil
        }
        vendorExtensions = try decoder.decodeVendorExtensions()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(type, forKey: .type)
        try encoder.encodeVendorExtensions(vendorExtensions)
    }
}

extension KeyedDecodingContainer {
    /// Decodes a string, accepting unquoted YAML numbers (e.g. `version: 1.0`) as their textual form.
    func decodeLenientString(forKey key: Key) throws -> String {
        if let string = try? decode(String.self, forKey: key) { return string }
        if let int = try? decode(Int.self, forKey: key) { return String(int) }
        if let double = try? decode(Double.self, forKey: key) { return String(double) }
        return try decode(String.self, forKey: key)
    }
}
