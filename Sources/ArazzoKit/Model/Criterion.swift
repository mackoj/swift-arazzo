import JSONPath
extension Arazzo {
    /// An assertion used by `successCriteria` and action `criteria` (the "Criterion Object").
    public struct Criterion: Hashable, Sendable, VendorExtendable {
        /// The type of condition.
        public enum ConditionType: Hashable, Sendable {
            case simple
            case regex
            case jsonPath
            case xPath
            /// A specific JSONPath or XPath version.
            case expressionType(ExpressionType)

            /// The raw `type` string for string-valued types.
            public var stringValue: String? {
                switch self {
                case .simple: "simple"
                case .regex: "regex"
                case .jsonPath: "jsonpath"
                case .xPath: "xpath"
                case .expressionType: nil
                }
            }
        }

        /// The runtime expression setting the context the condition applies to.
        /// Required whenever `type` is specified.
        public var context: RuntimeExpression?
        public var condition: String
        /// `nil` means `simple`.
        public var type: ConditionType?
        public var vendorExtensions: VendorExtensions

        public init(
            context: RuntimeExpression? = nil,
            condition: String,
            type: ConditionType? = nil,
            vendorExtensions: VendorExtensions = [:]
        ) {
            self.context = context
            self.condition = condition
            self.type = type
            self.vendorExtensions = vendorExtensions
        }

        /// `type`, defaulting to `simple`.
        public var effectiveType: ConditionType { type ?? .simple }

        /// Convenience for a simple condition such as `$statusCode == 200`.
        public static func simple(_ condition: String) -> Criterion {
            Criterion(condition: condition)
        }
    }
}

extension Arazzo.Criterion.ConditionType: Codable {
    public init(from decoder: any Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let raw = try? container.decode(String.self) {
            switch raw {
            case "simple": self = .simple
            case "regex": self = .regex
            case "jsonpath": self = .jsonPath
            case "xpath": self = .xPath
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Criterion type '\(raw)' must be one of simple, regex, jsonpath, xpath.")
            }
        } else {
            self = .expressionType(try Arazzo.ExpressionType(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        if case .expressionType(let type) = self {
            try type.encode(to: encoder)
        } else {
            var container = encoder.singleValueContainer()
            try container.encode(stringValue!)
        }
    }
}

extension Arazzo.Criterion: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case context, condition, type
    }

    public init(from decoder: any Decoder) throws {
        try decoder.ensureNoUnknownKeys(CodingKeys.self, objectName: "Criterion Object")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        context = try container.decodeIfPresent(Arazzo.RuntimeExpression.self, forKey: .context)
        condition = try container.decodeLenientString(forKey: .condition)
        type = try container.decodeIfPresent(ConditionType.self, forKey: .type)
        vendorExtensions = try decoder.decodeVendorExtensions()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(context, forKey: .context)
        try container.encode(condition, forKey: .condition)
        try container.encodeIfPresent(type, forKey: .type)
        try encoder.encodeVendorExtensions(vendorExtensions)
    }
}
