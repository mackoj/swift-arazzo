import JSONPath
extension Arazzo {
    /// The request body a step passes to an operation (the "Request Body Object").
    public struct RequestBody: Hashable, Sendable, VendorExtendable {
        /// The Content-Type. When omitted, the target operation's Content-Type applies.
        public var contentType: String?
        /// A literal, a runtime expression, or a structure containing expressions / Selector Objects.
        /// Non-JSON media types are typically represented as strings with embedded `{$...}` expressions.
        public var payload: JSONValue?
        /// Locations and values to set within the payload.
        public var replacements: [PayloadReplacement]
        public var vendorExtensions: VendorExtensions

        public init(
            contentType: String? = nil,
            payload: JSONValue? = nil,
            replacements: [PayloadReplacement] = [],
            vendorExtensions: VendorExtensions = [:]
        ) {
            self.contentType = contentType
            self.payload = payload
            self.replacements = replacements
            self.vendorExtensions = vendorExtensions
        }

        /// Every runtime expression the payload and replacements depend on.
        public var runtimeExpressions: [RuntimeExpression] {
            (payload.map(JSONValue.runtimeExpressions(in:)) ?? [])
                + replacements.flatMap(\.value.runtimeExpressions)
        }

        /// `true` when the content type is JSON (`application/json` or `+json`).
        public var isJSON: Bool {
            guard let base = contentType?.split(separator: ";").first?.trimmingCharacters() else { return false }
            return base == "application/json" || base.hasSuffix("+json")
        }

        /// `true` when the content type is XML (`application/xml`, `text/xml` or `+xml`).
        public var isXML: Bool {
            guard let base = contentType?.split(separator: ";").first?.trimmingCharacters() else { return false }
            return base == "application/xml" || base == "text/xml" || base.hasSuffix("+xml")
        }
    }

    /// A location within a payload and the value to set there (the "Payload Replacement Object").
    public struct PayloadReplacement: Hashable, Sendable, VendorExtendable {
        /// A JSON Pointer, XPath or JSONPath resolved against the request body.
        public var target: String
        /// Defaults to JSON Pointer for JSON payloads and XPath for XML payloads.
        public var targetSelectorType: SelectorType?
        public var value: Value
        public var vendorExtensions: VendorExtensions

        public init(
            target: String,
            targetSelectorType: SelectorType? = nil,
            value: Value,
            vendorExtensions: VendorExtensions = [:]
        ) {
            self.target = target
            self.targetSelectorType = targetSelectorType
            self.value = value
            self.vendorExtensions = vendorExtensions
        }

        /// The selector kind used to interpret `target`, given the request body's content type.
        public func effectiveTargetKind(in body: RequestBody?) -> ExpressionType.Kind {
            if let targetSelectorType { return targetSelectorType.kind }
            if body?.isXML == true { return .xPath }
            return .jsonPointer
        }
    }
}

extension Substring {
    func trimmingCharacters() -> String { String(self).trimmingWhitespace().lowercased() }
}

extension Arazzo.RequestBody: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case contentType, payload, replacements
    }

    public init(from decoder: any Decoder) throws {
        try decoder.ensureNoUnknownKeys(CodingKeys.self, objectName: "Request Body Object")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
        // Distinguish an explicit `payload: null` from an absent payload.
        if container.contains(.payload) {
            payload = try container.decodeNil(forKey: .payload)
                ? .null : try container.decode(JSONValue.self, forKey: .payload)
        } else {
            payload = nil
        }
        replacements = try container.decodeList([Arazzo.PayloadReplacement].self, forKey: .replacements)
        vendorExtensions = try decoder.decodeVendorExtensions()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(contentType, forKey: .contentType)
        try container.encodeIfPresent(payload, forKey: .payload)
        try container.encodeNonEmpty(replacements, forKey: .replacements)
        try encoder.encodeVendorExtensions(vendorExtensions)
    }
}

extension Arazzo.PayloadReplacement: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case target, targetSelectorType, value
    }

    public init(from decoder: any Decoder) throws {
        try decoder.ensureNoUnknownKeys(CodingKeys.self, objectName: "Payload Replacement Object")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decode(String.self, forKey: .target)
        targetSelectorType = try container.decodeIfPresent(Arazzo.SelectorType.self, forKey: .targetSelectorType)
        value = try container.decode(Arazzo.Value.self, forKey: .value)
        vendorExtensions = try decoder.decodeVendorExtensions()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encodeIfPresent(targetSelectorType, forKey: .targetSelectorType)
        try container.encode(value, forKey: .value)
        try encoder.encodeVendorExtensions(vendorExtensions)
    }
}
