extension Arazzo {
    /// A JSON Schema (Draft 2020-12) used for workflow `inputs` and `components.inputs`.
    ///
    /// The schema is kept losslessly as a ``JSONValue``; convenience accessors cover the
    /// keywords Arazzo tooling typically needs. Boolean schemas (`true` / `false`) are supported.
    public struct JSONSchema: Hashable, Sendable, Codable, ExpressibleByDictionaryLiteral {
        public var value: JSONValue

        public init(_ value: JSONValue) {
            self.value = value
        }

        public init(dictionaryLiteral elements: (String, JSONValue)...) {
            value = .object(OrderedDictionary(elements))
        }

        /// An object schema with the given properties.
        public static func object(
            properties: OrderedDictionary<String, JSONSchema>, required: [String] = []
        ) -> JSONSchema {
            var object: OrderedDictionary<String, JSONValue> = ["type": "object"]
            object["properties"] = .object(properties.mapValues(\.value))
            if !required.isEmpty { object["required"] = .array(required.map(JSONValue.string)) }
            return JSONSchema(.object(object))
        }

        /// A `$ref` schema, e.g. `#/components/inputs/pagination`.
        public static func reference(_ ref: String) -> JSONSchema {
            JSONSchema(["$ref": .string(ref)])
        }

        public init(from decoder: any Decoder) throws {
            value = try JSONValue(from: decoder)
        }

        public func encode(to encoder: any Encoder) throws {
            try value.encode(to: encoder)
        }

        /// `$ref`, if present.
        public var ref: String? { value["$ref"]?.stringValue }

        /// The `type` keyword (a single type or the list of types).
        public var types: [String] {
            switch value["type"] {
            case .string(let type)?: [type]
            case .array(let types)?: types.compactMap(\.stringValue)
            default: []
            }
        }

        /// The `properties` keyword.
        public var properties: OrderedDictionary<String, JSONSchema> {
            value["properties"]?.objectValue?.mapValues(JSONSchema.init) ?? [:]
        }

        /// The `required` keyword.
        public var required: [String] {
            value["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
        }

        /// The `description` keyword.
        public var description: String? { value["description"]?.stringValue }

        /// The `default` keyword.
        public var defaultValue: JSONValue? { value["default"] }

        /// `true` when the schema uses composition or references, so its full set of
        /// properties cannot be known from `properties` alone.
        public var isComposite: Bool {
            guard case .object(let object) = value else { return false }
            return ["$ref", "allOf", "anyOf", "oneOf", "$dynamicRef", "patternProperties", "additionalProperties"]
                .contains { object[$0] != nil }
        }
    }
}
