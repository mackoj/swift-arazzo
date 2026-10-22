extension Arazzo {
    /// Selects data from structured content (JSON or XML) using JSONPath, XPath or JSON Pointer
    /// (the "Selector Object", Arazzo 1.1).
    ///
    /// ```yaml
    /// userEmail:
    ///   context: $response.body
    ///   selector: $.user.profile.email
    ///   type: jsonpath
    /// ```
    public struct Selector: Hashable, Sendable, VendorExtendable {
        /// Must evaluate to structured data.
        public var context: RuntimeExpression
        /// The selector expression, e.g. `$.items[0].id` or `/Envelope/Item`.
        public var selector: String
        public var type: SelectorType
        public var vendorExtensions: VendorExtensions

        public init(
            context: RuntimeExpression, selector: String, type: SelectorType, vendorExtensions: VendorExtensions = [:]
        ) {
            self.context = context
            self.selector = selector
            self.type = type
            self.vendorExtensions = vendorExtensions
        }

        /// Interprets a JSON object as a Selector Object, if it has that shape.
        public init?(json: JSONValue) {
            guard case .object(let object) = json,
                let contextString = object["context"]?.stringValue,
                let context = try? RuntimeExpression(contextString),
                let selector = object["selector"]?.stringValue,
                let typeValue = object["type"]
            else { return nil }
            let otherKeys = object.keys.filter { !["context", "selector", "type"].contains($0) }
            guard otherKeys.allSatisfy({ $0.lowercased().hasPrefix("x-") }) else { return nil }

            let type: SelectorType
            switch typeValue {
            case .string(let raw):
                guard let kind = ExpressionType.Kind(rawValue: raw) else { return nil }
                type = SelectorType(kind)
            case .object(let typeObject):
                guard let rawKind = typeObject["type"]?.stringValue,
                    let kind = ExpressionType.Kind(rawValue: rawKind),
                    let version = typeObject["version"]?.stringValue
                else { return nil }
                type = .expressionType(
                    ExpressionType(
                        kind: kind, version: .init(rawValue: version),
                        vendorExtensions: typeObject.filter { $0.key.lowercased().hasPrefix("x-") }))
            default:
                return nil
            }
            self.init(
                context: context, selector: selector, type: type,
                vendorExtensions: object.filter { $0.key.lowercased().hasPrefix("x-") })
        }
    }
}

extension Arazzo.Selector: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case context, selector, type
    }

    public init(from decoder: any Decoder) throws {
        try decoder.ensureNoUnknownKeys(CodingKeys.self, objectName: "Selector Object")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        context = try container.decode(Arazzo.RuntimeExpression.self, forKey: .context)
        selector = try container.decode(String.self, forKey: .selector)
        type = try container.decode(Arazzo.SelectorType.self, forKey: .type)
        vendorExtensions = try decoder.decodeVendorExtensions()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(context, forKey: .context)
        try container.encode(selector, forKey: .selector)
        try container.encode(type, forKey: .type)
        try encoder.encodeVendorExtensions(vendorExtensions)
    }
}

extension Arazzo {
    /// A value that can be a constant, a runtime expression or a Selector Object
    /// (used by Parameter `value` and Payload Replacement `value`).
    ///
    /// Strings that parse as a runtime expression (`$inputs.username`) decode as ``expression(_:)``;
    /// objects with exactly the Selector Object shape decode as ``selector(_:)``; anything else is a
    /// ``literal(_:)``. Literal strings may still embed expressions (`"Bearer {$inputs.token}"`) –
    /// see ``template``.
    public enum Value: Hashable, Sendable {
        case expression(RuntimeExpression)
        case selector(Selector)
        case literal(JSONValue)

        /// Classifies a raw JSON value.
        public init(interpreting json: JSONValue) {
            switch json {
            case .string(let string) where string.hasPrefix("$"):
                if let expression = try? RuntimeExpression(string) {
                    self = .expression(expression)
                } else {
                    self = .literal(json)
                }
            case .object:
                if let selector = Selector(json: json) {
                    self = .selector(selector)
                } else {
                    self = .literal(json)
                }
            default:
                self = .literal(json)
            }
        }

        /// The embedded-expression template for literal string values.
        public var template: ExpressionTemplate? {
            if case .literal(.string(let string)) = self { return ExpressionTemplate(string) }
            return nil
        }

        /// Every runtime expression this value depends on (direct, selector context, or embedded).
        public var runtimeExpressions: [RuntimeExpression] {
            switch self {
            case .expression(let e): [e]
            case .selector(let s): [s.context]
            case .literal(let json): JSONValue.runtimeExpressions(in: json)
            }
        }
    }
}

extension Arazzo.Value: Codable {
    public init(from decoder: any Decoder) throws {
        self.init(interpreting: try JSONValue(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .expression(let expression): try expression.encode(to: encoder)
        case .selector(let selector): try selector.encode(to: encoder)
        case .literal(let value): try value.encode(to: encoder)
        }
    }
}

extension Arazzo.Value: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    /// `"$inputs.id"` becomes an expression; other strings are literals.
    public init(stringLiteral value: String) { self.init(interpreting: .string(value)) }
    public init(integerLiteral value: Int) { self = .literal(.integer(value)) }
    public init(booleanLiteral value: Bool) { self = .literal(.bool(value)) }
}

extension JSONValue {
    /// Finds runtime expressions anywhere inside a JSON value: strings that are expressions,
    /// expressions embedded in strings with `{$...}`, and Selector Object contexts.
    static func runtimeExpressions(in value: JSONValue) -> [Arazzo.RuntimeExpression] {
        switch value {
        case .string(let string):
            if string.hasPrefix("$"), let expression = try? Arazzo.RuntimeExpression(string) {
                return [expression]
            }
            return Arazzo.ExpressionTemplate(string).expressions
        case .array(let values):
            return values.flatMap(runtimeExpressions(in:))
        case .object(let object):
            if let selector = Arazzo.Selector(json: value) { return [selector.context] }
            return object.values.flatMap(runtimeExpressions(in:))
        default:
            return []
        }
    }
}
