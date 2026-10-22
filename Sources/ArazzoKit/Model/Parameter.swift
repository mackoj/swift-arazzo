import JSONPath
extension Arazzo {
    /// A parameter passed to an operation or workflow (the "Parameter Object").
    /// A parameter is uniquely identified by the combination of `name` and `in`.
    public struct Parameter: Hashable, Sendable, VendorExtendable {
        public enum Location: String, Hashable, Sendable, Codable, CaseIterable {
            case path
            case query
            /// The whole query string as one value (Arazzo 1.1, OpenAPI 3.2).
            case querystring
            case header
            case cookie
        }

        /// Case-sensitive parameter name.
        public var name: String
        /// Required unless the step or action targets a `workflowId`
        /// (then parameters map to workflow inputs). Must not be used in action parameters.
        public var location: Location?
        public var value: Value
        public var vendorExtensions: VendorExtensions

        public init(name: String, in location: Location? = nil, value: Value, vendorExtensions: VendorExtensions = [:]) {
            self.name = name
            self.location = location
            self.value = value
            self.vendorExtensions = vendorExtensions
        }

        /// The identity used for de-duplication and overriding: `name` + `in`.
        /// Header names are compared case-insensitively (RFC 9110).
        public var identity: Identity {
            Identity(name: location == .header ? name.lowercased() : name, location: location)
        }

        public struct Identity: Hashable, Sendable {
            public let name: String
            public let location: Location?
        }
    }
}

extension Arazzo.Parameter: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case name
        case location = "in"
        case value
    }

    public init(from decoder: any Decoder) throws {
        try decoder.ensureNoUnknownKeys(CodingKeys.self, objectName: "Parameter Object")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        if let raw = try container.decodeIfPresent(String.self, forKey: .location) {
            guard let location = Location(rawValue: raw) else {
                throw decodingError(
                    "Parameter location '\(raw)' must be one of path, query, querystring, header, cookie.",
                    codingPath: container.codingPath + [CodingKeys.location])
            }
            self.location = location
        } else {
            location = nil
        }
        value = try container.decode(Arazzo.Value.self, forKey: .value)
        vendorExtensions = try decoder.decodeVendorExtensions()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(value, forKey: .value)
        try encoder.encodeVendorExtensions(vendorExtensions)
    }
}
