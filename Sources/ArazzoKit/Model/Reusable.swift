import JSONPath
extension Arazzo {
    /// A reference to an object in the Components Object (the "Reusable Object").
    ///
    /// ```yaml
    /// - reference: $components.parameters.page
    ///   value: 1
    /// ```
    /// This object cannot be extended; additional properties are ignored.
    public struct Reusable: Hashable, Sendable {
        /// A `$components.<type>.<name>` runtime expression.
        public var reference: RuntimeExpression
        /// Overrides the value of a referenced parameter. Only applicable to parameter references.
        public var value: Value?

        public init(reference: RuntimeExpression, value: Value? = nil) {
            self.reference = reference
            self.value = value
        }

        /// A reference to `$components.<type>.<name>`.
        public init(_ type: RuntimeExpression.ComponentType, _ name: String, value: Value? = nil) {
            self.init(reference: RuntimeExpression(.components(type: type, name: name)), value: value)
        }

        /// The referenced component type and name, when `reference` is a `$components` expression.
        public var component: (type: RuntimeExpression.ComponentType, name: String)? {
            if case .components(let type, let name) = reference.kind { return (type, name) }
            return nil
        }
    }

    /// Either an inline object or a ``Reusable`` reference to one in `components`.
    public enum ReusableOr<Wrapped: Hashable & Sendable>: Hashable, Sendable {
        case reusable(Reusable)
        case inline(Wrapped)

        public var inlineValue: Wrapped? {
            if case .inline(let value) = self { return value }
            return nil
        }

        public var reusableValue: Reusable? {
            if case .reusable(let value) = self { return value }
            return nil
        }
    }
}

extension Arazzo.Reusable: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case reference, value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reference = try container.decode(Arazzo.RuntimeExpression.self, forKey: .reference)
        value = try container.decodeIfPresent(Arazzo.Value.self, forKey: .value)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reference, forKey: .reference)
        try container.encodeIfPresent(value, forKey: .value)
    }
}

extension Arazzo.ReusableOr: Codable where Wrapped: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        if container.contains(AnyCodingKey("reference")) {
            self = .reusable(try Arazzo.Reusable(from: decoder))
        } else {
            self = .inline(try Wrapped(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .reusable(let reusable): try reusable.encode(to: encoder)
        case .inline(let value): try value.encode(to: encoder)
        }
    }
}

extension Arazzo.ReusableOr {
    /// Wraps an inline value.
    public static func value(_ value: Wrapped) -> Self { .inline(value) }
}
