import JSONPath
extension Arazzo {
    /// Reusable objects (the "Components Object"). Keys MUST match `^[a-zA-Z0-9\.\-_]+$`.
    public struct Components: Hashable, Sendable, VendorExtendable {
        public var inputs: OrderedDictionary<String, JSONSchema>
        public var parameters: OrderedDictionary<String, Parameter>
        public var successActions: OrderedDictionary<String, SuccessAction>
        public var failureActions: OrderedDictionary<String, FailureAction>
        public var vendorExtensions: VendorExtensions

        public init(
            inputs: OrderedDictionary<String, JSONSchema> = [:],
            parameters: OrderedDictionary<String, Parameter> = [:],
            successActions: OrderedDictionary<String, SuccessAction> = [:],
            failureActions: OrderedDictionary<String, FailureAction> = [:],
            vendorExtensions: VendorExtensions = [:]
        ) {
            self.inputs = inputs
            self.parameters = parameters
            self.successActions = successActions
            self.failureActions = failureActions
            self.vendorExtensions = vendorExtensions
        }

        public static let noComponents = Components()

        public var isEmpty: Bool {
            inputs.isEmpty && parameters.isEmpty && successActions.isEmpty && failureActions.isEmpty
                && vendorExtensions.isEmpty
        }
    }
}

extension Arazzo.Components: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case inputs, parameters, successActions, failureActions
    }

    public init(from decoder: any Decoder) throws {
        try decoder.ensureNoUnknownKeys(CodingKeys.self, objectName: "Components Object")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputs =
            try container.decodeIfPresent(OrderedDictionary<String, Arazzo.JSONSchema>.self, forKey: .inputs) ?? [:]
        parameters =
            try container.decodeIfPresent(OrderedDictionary<String, Arazzo.Parameter>.self, forKey: .parameters) ?? [:]
        successActions =
            try container.decodeIfPresent(
                OrderedDictionary<String, Arazzo.SuccessAction>.self, forKey: .successActions) ?? [:]
        failureActions =
            try container.decodeIfPresent(
                OrderedDictionary<String, Arazzo.FailureAction>.self, forKey: .failureActions) ?? [:]
        vendorExtensions = try decoder.decodeVendorExtensions()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNonEmpty(inputs, forKey: .inputs)
        try container.encodeNonEmpty(parameters, forKey: .parameters)
        try container.encodeNonEmpty(successActions, forKey: .successActions)
        try container.encodeNonEmpty(failureActions, forKey: .failureActions)
        try encoder.encodeVendorExtensions(vendorExtensions)
    }
}

// MARK: - Resolution

extension Arazzo {
    /// An error raised when a reference cannot be resolved.
    public struct ResolutionError: Error, Hashable, Sendable, CustomStringConvertible {
        public let reference: String
        public let message: String
        public var description: String { "Cannot resolve '\(reference)': \(message)" }
    }
}

extension Arazzo.Components {
    /// Resolves a parameter reference, applying the Reusable `value` override.
    public func resolve(_ parameter: Arazzo.ReusableOr<Arazzo.Parameter>) throws -> Arazzo.Parameter {
        switch parameter {
        case .inline(let value): return value
        case .reusable(let reusable):
            guard let (type, name) = reusable.component, type == .parameters else {
                throw Arazzo.ResolutionError(
                    reference: reusable.reference.rawValue, message: "expected a $components.parameters reference")
            }
            guard var resolved = parameters[name] else {
                throw Arazzo.ResolutionError(
                    reference: reusable.reference.rawValue, message: "no parameter named '\(name)' in components")
            }
            if let value = reusable.value { resolved.value = value }
            return resolved
        }
    }

    /// Resolves a success action reference.
    public func resolve(_ action: Arazzo.ReusableOr<Arazzo.SuccessAction>) throws -> Arazzo.SuccessAction {
        switch action {
        case .inline(let value): return value
        case .reusable(let reusable):
            guard let (type, name) = reusable.component, type == .successActions else {
                throw Arazzo.ResolutionError(
                    reference: reusable.reference.rawValue, message: "expected a $components.successActions reference")
            }
            guard let resolved = successActions[name] else {
                throw Arazzo.ResolutionError(
                    reference: reusable.reference.rawValue, message: "no success action named '\(name)' in components")
            }
            return resolved
        }
    }

    /// Resolves a failure action reference.
    public func resolve(_ action: Arazzo.ReusableOr<Arazzo.FailureAction>) throws -> Arazzo.FailureAction {
        switch action {
        case .inline(let value): return value
        case .reusable(let reusable):
            guard let (type, name) = reusable.component, type == .failureActions else {
                throw Arazzo.ResolutionError(
                    reference: reusable.reference.rawValue, message: "expected a $components.failureActions reference")
            }
            guard let resolved = failureActions[name] else {
                throw Arazzo.ResolutionError(
                    reference: reusable.reference.rawValue, message: "no failure action named '\(name)' in components")
            }
            return resolved
        }
    }

    /// Resolves a local `#/components/inputs/<name>` JSON Schema reference.
    public func resolveInputs(_ schema: Arazzo.JSONSchema) throws -> Arazzo.JSONSchema {
        guard let ref = schema.ref else { return schema }
        let prefix = "#/components/inputs/"
        guard ref.hasPrefix(prefix) else {
            throw Arazzo.ResolutionError(
                reference: ref, message: "only local #/components/inputs references are resolved")
        }
        let encodedName = String(ref.dropFirst(prefix.count))
        let name = (try? JSONPointer("/" + encodedName).tokens.first) ?? encodedName
        guard let resolved = inputs[name] else {
            throw Arazzo.ResolutionError(
                reference: ref, message: "no input schema named '\(encodedName)' in components")
        }
        return resolved
    }
}
