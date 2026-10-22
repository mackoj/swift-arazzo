import JSONPath
extension Arazzo {
    /// Describes the type and version of an expression used within a Criterion,
    /// Selector or Payload Replacement (the "Expression Type Object"; called the
    /// "Criterion Expression Type Object" in Arazzo 1.0).
    public struct ExpressionType: Hashable, Sendable, VendorExtendable {
        public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
            case jsonPath = "jsonpath"
            case xPath = "xpath"
            case jsonPointer = "jsonpointer"

            /// The versions the specification allows for this kind.
            public var allowedVersions: [Version] {
                switch self {
                case .jsonPath: [.rfc9535, .draftGoessnerDispatchJSONPath00]
                case .xPath: [.xpath31, .xpath30, .xpath20, .xpath10]
                case .jsonPointer: [.rfc6901]
                }
            }

            /// The version used when none is specified.
            public var defaultVersion: Version {
                switch self {
                case .jsonPath: .rfc9535
                case .xPath: .xpath31
                case .jsonPointer: .rfc6901
                }
            }
        }

        /// A version identifier such as `rfc9535` or `xpath-30`.
        public struct Version: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral,
            CustomStringConvertible
        {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }
            public init(stringLiteral value: String) { rawValue = value }
            public var description: String { rawValue }

            public init(from decoder: any Decoder) throws {
                rawValue = try decoder.singleValueContainer().decode(String.self)
            }

            public func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(rawValue)
            }

            public static let rfc9535: Self = "rfc9535"
            public static let draftGoessnerDispatchJSONPath00: Self = "draft-goessner-dispatch-jsonpath-00"
            public static let xpath31: Self = "xpath-31"
            public static let xpath30: Self = "xpath-30"
            public static let xpath20: Self = "xpath-20"
            public static let xpath10: Self = "xpath-10"
            public static let rfc6901: Self = "rfc6901"
        }

        public var kind: Kind
        public var version: Version
        public var vendorExtensions: VendorExtensions

        public init(kind: Kind, version: Version, vendorExtensions: VendorExtensions = [:]) {
            self.kind = kind
            self.version = version
            self.vendorExtensions = vendorExtensions
        }

        /// `true` when `version` is one the specification allows for `kind`.
        public var hasAllowedVersion: Bool { kind.allowedVersions.contains(version) }
    }

    /// The selector type of a Selector or Payload Replacement:
    /// `jsonpath`, `xpath`, `jsonpointer`, or an ``ExpressionType`` object.
    public enum SelectorType: Hashable, Sendable {
        case jsonPath
        case xPath
        case jsonPointer
        case expressionType(ExpressionType)

        public init(_ kind: ExpressionType.Kind) {
            switch kind {
            case .jsonPath: self = .jsonPath
            case .xPath: self = .xPath
            case .jsonPointer: self = .jsonPointer
            }
        }

        public var kind: ExpressionType.Kind {
            switch self {
            case .jsonPath: .jsonPath
            case .xPath: .xPath
            case .jsonPointer: .jsonPointer
            case .expressionType(let type): type.kind
            }
        }

        /// The explicit version, or the default for the kind.
        public var effectiveVersion: ExpressionType.Version {
            if case .expressionType(let type) = self { return type.version }
            return kind.defaultVersion
        }
    }
}

extension Arazzo.ExpressionType: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case kind = "type"
        case version
    }

    public init(from decoder: any Decoder) throws {
        try decoder.ensureNoUnknownKeys(CodingKeys.self, objectName: "Expression Type Object")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try container.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: rawKind) else {
            throw decodingError(
                "Expression type '\(rawKind)' must be one of jsonpath, xpath, jsonpointer.",
                codingPath: container.codingPath + [CodingKeys.kind])
        }
        self.kind = kind
        version = try container.decode(Version.self, forKey: .version)
        vendorExtensions = try decoder.decodeVendorExtensions()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(version, forKey: .version)
        try encoder.encodeVendorExtensions(vendorExtensions)
    }
}

extension Arazzo.SelectorType: Codable {
    public init(from decoder: any Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let raw = try? container.decode(String.self) {
            guard let kind = Arazzo.ExpressionType.Kind(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Selector type '\(raw)' must be one of jsonpath, xpath, jsonpointer.")
            }
            self.init(kind)
        } else {
            self = .expressionType(try Arazzo.ExpressionType(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .expressionType(let type):
            try type.encode(to: encoder)
        default:
            var container = encoder.singleValueContainer()
            try container.encode(kind.rawValue)
        }
    }
}
