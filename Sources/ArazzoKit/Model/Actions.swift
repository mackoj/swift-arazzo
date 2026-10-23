import JSONPath
extension Arazzo {
    /// Where a `goto` (or `retry`) action transfers control.
    public enum ActionTarget: Hashable, Sendable {
        /// A step within the current workflow.
        case step(String)
        /// A workflow in this description, or `$sourceDescriptions.<name>.<workflowId>`.
        case workflow(String)

        public var stepId: String? { if case .step(let id) = self { id } else { nil } }
        public var workflowId: String? { if case .workflow(let id) = self { id } else { nil } }
    }

    /// The action to take when a step succeeds (the "Success Action Object").
    public struct SuccessAction: Hashable, Sendable, VendorExtendable {
        public enum Kind: Hashable, Sendable {
            /// The workflow ends and context returns to the caller with applicable outputs.
            case end
            /// One-way transfer of control to a step or workflow.
            case goto(ActionTarget)

            public var typeName: String {
                switch self {
                case .end: "end"
                case .goto: "goto"
                }
            }
        }

        /// Case-sensitive name; used to override workflow-level actions.
        public var name: String
        public var kind: Kind
        /// Parameters passed to the target workflow. `in` must not be used.
        public var parameters: [ReusableOr<Parameter>]
        /// All criteria must pass for the action to be executed.
        public var criteria: [Criterion]
        public var vendorExtensions: VendorExtensions

        public init(
            name: String,
            kind: Kind,
            parameters: [ReusableOr<Parameter>] = [],
            criteria: [Criterion] = [],
            vendorExtensions: VendorExtensions = [:]
        ) {
            self.name = name
            self.kind = kind
            self.parameters = parameters
            self.criteria = criteria
            self.vendorExtensions = vendorExtensions
        }

        public static func end(name: String, criteria: [Criterion] = []) -> SuccessAction {
            SuccessAction(name: name, kind: .end, criteria: criteria)
        }

        public static func goto(name: String, _ target: ActionTarget, criteria: [Criterion] = []) -> SuccessAction {
            SuccessAction(name: name, kind: .goto(target), criteria: criteria)
        }

        public var target: ActionTarget? {
            if case .goto(let target) = kind { return target }
            return nil
        }
    }

    /// The action to take when a step fails (the "Failure Action Object").
    public struct FailureAction: Hashable, Sendable, VendorExtendable {
        public struct Retry: Hashable, Sendable {
            /// Non-negative seconds to wait before the next attempt. A `Retry-After` header SHOULD win.
            public var retryAfter: Double?
            /// Non-negative number of attempts. Defaults to a single retry when omitted.
            public var retryLimit: Int?
            /// A step or workflow to run before retrying the current step.
            public var target: ActionTarget?

            public init(retryAfter: Double? = nil, retryLimit: Int? = nil, target: ActionTarget? = nil) {
                self.retryAfter = retryAfter
                self.retryLimit = retryLimit
                self.target = target
            }

            /// `retryLimit`, or the specification default of `1`.
            public var effectiveRetryLimit: Int { retryLimit ?? 1 }
        }

        public enum Kind: Hashable, Sendable {
            /// The workflow ends and context returns to the caller.
            case end
            /// Retry the current step.
            case retry(Retry)
            /// One-way transfer of control to a step or workflow.
            case goto(ActionTarget)

            public var typeName: String {
                switch self {
                case .end: "end"
                case .retry: "retry"
                case .goto: "goto"
                }
            }
        }

        public var name: String
        public var kind: Kind
        public var parameters: [ReusableOr<Parameter>]
        public var criteria: [Criterion]
        public var vendorExtensions: VendorExtensions

        public init(
            name: String,
            kind: Kind,
            parameters: [ReusableOr<Parameter>] = [],
            criteria: [Criterion] = [],
            vendorExtensions: VendorExtensions = [:]
        ) {
            self.name = name
            self.kind = kind
            self.parameters = parameters
            self.criteria = criteria
            self.vendorExtensions = vendorExtensions
        }

        public static func end(name: String, criteria: [Criterion] = []) -> FailureAction {
            FailureAction(name: name, kind: .end, criteria: criteria)
        }

        public static func retry(
            name: String, after: Double? = nil, limit: Int? = nil, target: ActionTarget? = nil,
            criteria: [Criterion] = []
        ) -> FailureAction {
            FailureAction(
                name: name, kind: .retry(Retry(retryAfter: after, retryLimit: limit, target: target)),
                criteria: criteria)
        }

        public static func goto(name: String, _ target: ActionTarget, criteria: [Criterion] = []) -> FailureAction {
            FailureAction(name: name, kind: .goto(target), criteria: criteria)
        }

        /// The step or workflow this action transfers to (for `goto`, or `retry` with a target).
        public var target: ActionTarget? {
            switch kind {
            case .end: nil
            case .goto(let target): target
            case .retry(let retry): retry.target
            }
        }
    }
}

// MARK: - Codable

private enum ActionCodingKeys: String, CodingKey, CaseIterable {
    case name, type, workflowId, stepId, parameters, criteria, retryAfter, retryLimit
}

private func decodeTarget(
    _ container: KeyedDecodingContainer<ActionCodingKeys>, required: Bool, actionType: String
) throws -> Arazzo.ActionTarget? {
    let workflowId = try container.decodeIfPresent(String.self, forKey: .workflowId)
    let stepId = try container.decodeIfPresent(String.self, forKey: .stepId)
    switch (workflowId, stepId) {
    case (let w?, nil): return .workflow(w)
    case (nil, let s?): return .step(s)
    case (nil, nil):
        if required {
            throw decodingError(
                "A '\(actionType)' action requires either a workflowId or a stepId.", codingPath: container.codingPath)
        }
        return nil
    case (.some, .some):
        throw decodingError("workflowId and stepId are mutually exclusive.", codingPath: container.codingPath)
    }
}

private func encodeTarget(
    _ target: Arazzo.ActionTarget?, into container: inout KeyedEncodingContainer<ActionCodingKeys>
)
    throws
{
    switch target {
    case .workflow(let id)?: try container.encode(id, forKey: .workflowId)
    case .step(let id)?: try container.encode(id, forKey: .stepId)
    case nil: break
    }
}

private func ensureAbsent(
    _ keys: [ActionCodingKeys], in container: KeyedDecodingContainer<ActionCodingKeys>, actionType: String,
    decoder: any Decoder
) throws {
    guard decoder.arazzoOptions.strict else { return }
    let present = keys.filter { container.contains($0) }
    guard present.isEmpty else {
        throw decodingError(
            "\(present.map(\.stringValue).joined(separator: ", ")) not applicable to a '\(actionType)' action.",
            codingPath: container.codingPath)
    }
}

extension Arazzo.SuccessAction: Codable {
    public init(from decoder: any Decoder) throws {
        try decoder.ensureNoUnknownKeys(ActionCodingKeys.self, objectName: "Success Action Object")
        let container = try decoder.container(keyedBy: ActionCodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        let type = try container.decode(String.self, forKey: .type)
        try ensureAbsent([.retryAfter, .retryLimit], in: container, actionType: type, decoder: decoder)
        switch type {
        case "end":
            try ensureAbsent([.workflowId, .stepId], in: container, actionType: type, decoder: decoder)
            kind = .end
        case "goto":
            kind = .goto(try decodeTarget(container, required: true, actionType: type)!)
        default:
            throw decodingError(
                "Success action type '\(type)' must be 'end' or 'goto'.",
                codingPath: container.codingPath + [ActionCodingKeys.type])
        }
        parameters = try container.decodeList([Arazzo.ReusableOr<Arazzo.Parameter>].self, forKey: .parameters)
        criteria = try container.decodeList([Arazzo.Criterion].self, forKey: .criteria)
        vendorExtensions = try decoder.decodeVendorExtensions()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: ActionCodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(kind.typeName, forKey: .type)
        try encodeTarget(target, into: &container)
        try container.encodeNonEmpty(parameters, forKey: .parameters)
        try container.encodeNonEmpty(criteria, forKey: .criteria)
        try encoder.encodeVendorExtensions(vendorExtensions)
    }
}

extension Arazzo.FailureAction: Codable {
    public init(from decoder: any Decoder) throws {
        try decoder.ensureNoUnknownKeys(ActionCodingKeys.self, objectName: "Failure Action Object")
        let container = try decoder.container(keyedBy: ActionCodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "end":
            try ensureAbsent(
                [.workflowId, .stepId, .retryAfter, .retryLimit], in: container, actionType: type, decoder: decoder)
            kind = .end
        case "goto":
            try ensureAbsent([.retryAfter, .retryLimit], in: container, actionType: type, decoder: decoder)
            kind = .goto(try decodeTarget(container, required: true, actionType: type)!)
        case "retry":
            kind = .retry(
                Retry(
                    retryAfter: try container.decodeIfPresent(Double.self, forKey: .retryAfter),
                    retryLimit: try container.decodeIfPresent(Int.self, forKey: .retryLimit),
                    target: try decodeTarget(container, required: false, actionType: type)))
        default:
            throw decodingError(
                "Failure action type '\(type)' must be 'end', 'retry' or 'goto'.",
                codingPath: container.codingPath + [ActionCodingKeys.type])
        }
        parameters = try container.decodeList([Arazzo.ReusableOr<Arazzo.Parameter>].self, forKey: .parameters)
        criteria = try container.decodeList([Arazzo.Criterion].self, forKey: .criteria)
        vendorExtensions = try decoder.decodeVendorExtensions()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: ActionCodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(kind.typeName, forKey: .type)
        try encodeTarget(target, into: &container)
        if case .retry(let retry) = kind {
            try container.encodeIfPresent(retry.retryAfter, forKey: .retryAfter)
            try container.encodeIfPresent(retry.retryLimit, forKey: .retryLimit)
        }
        try container.encodeNonEmpty(parameters, forKey: .parameters)
        try container.encodeNonEmpty(criteria, forKey: .criteria)
        try encoder.encodeVendorExtensions(vendorExtensions)
    }
}
