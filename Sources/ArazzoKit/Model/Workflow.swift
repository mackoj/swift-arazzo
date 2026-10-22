import JSONPath
extension Arazzo {
    /// A workflow output value: a runtime expression or (Arazzo 1.1) a Selector Object.
    public enum OutputValue: Hashable, Sendable {
        case expression(RuntimeExpression)
        case selector(Selector)

        /// The runtime expression the output is computed from (the selector's context for selectors).
        public var runtimeExpression: RuntimeExpression {
            switch self {
            case .expression(let e): e
            case .selector(let s): s.context
            }
        }
    }

    /// A workflow: a sequence of steps achieving a goal (the "Workflow Object").
    public struct Workflow: Hashable, Sendable, VendorExtendable {
        /// Unique, case-sensitive identifier. SHOULD match `[A-Za-z0-9_\-]+`.
        public var workflowId: String
        public var summary: String?
        public var description: String?
        /// JSON Schema describing the workflow inputs.
        public var inputs: JSONSchema?
        /// Workflows that must complete first: `workflowId`s or `$sourceDescriptions.<name>.<workflowId>`.
        public var dependsOn: [String]
        public var steps: [Step]
        /// Applied to every step; steps may override by `name` but never remove.
        public var successActions: [ReusableOr<SuccessAction>]
        /// Applied to every step; steps may override by `name` but never remove.
        public var failureActions: [ReusableOr<FailureAction>]
        /// Keys MUST match `^[a-zA-Z0-9\.\-_]+$`.
        public var outputs: OrderedDictionary<String, OutputValue>
        /// Applied to every step; steps may override by `name` + `in` but never remove.
        public var parameters: [ReusableOr<Parameter>]
        public var vendorExtensions: VendorExtensions

        public init(
            workflowId: String,
            summary: String? = nil,
            description: String? = nil,
            inputs: JSONSchema? = nil,
            dependsOn: [String] = [],
            steps: [Step],
            successActions: [ReusableOr<SuccessAction>] = [],
            failureActions: [ReusableOr<FailureAction>] = [],
            outputs: OrderedDictionary<String, OutputValue> = [:],
            parameters: [ReusableOr<Parameter>] = [],
            vendorExtensions: VendorExtensions = [:]
        ) {
            self.workflowId = workflowId
            self.summary = summary
            self.description = description
            self.inputs = inputs
            self.dependsOn = dependsOn
            self.steps = steps
            self.successActions = successActions
            self.failureActions = failureActions
            self.outputs = outputs
            self.parameters = parameters
            self.vendorExtensions = vendorExtensions
        }

        /// The step with the given `stepId` (case-sensitive).
        public func step(id: String) -> Step? {
            steps.first { $0.stepId == id }
        }
    }
}

extension Arazzo.OutputValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if (try? container.decode(String.self)) != nil {
            self = .expression(try Arazzo.RuntimeExpression(from: decoder))
        } else {
            self = .selector(try Arazzo.Selector(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .expression(let e): try e.encode(to: encoder)
        case .selector(let s): try s.encode(to: encoder)
        }
    }
}

extension Arazzo.OutputValue: ExpressibleByStringLiteral {
    /// Creates an expression output. Traps if the literal is not a valid runtime expression.
    public init(stringLiteral value: String) {
        do {
            self = .expression(try Arazzo.RuntimeExpression(value))
        } catch {
            preconditionFailure("\(error)")
        }
    }
}

extension Arazzo.Workflow: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case workflowId, summary, description, inputs, dependsOn, steps, successActions, failureActions, outputs,
            parameters
    }

    public init(from decoder: any Decoder) throws {
        try decoder.ensureNoUnknownKeys(CodingKeys.self, objectName: "Workflow Object")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workflowId = try container.decode(String.self, forKey: .workflowId)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        inputs = try container.decodeIfPresent(Arazzo.JSONSchema.self, forKey: .inputs)
        dependsOn = try container.decodeList([String].self, forKey: .dependsOn)
        steps = try container.decode([Arazzo.Step].self, forKey: .steps)
        successActions = try container.decodeList(
            [Arazzo.ReusableOr<Arazzo.SuccessAction>].self, forKey: .successActions)
        failureActions = try container.decodeList(
            [Arazzo.ReusableOr<Arazzo.FailureAction>].self, forKey: .failureActions)
        outputs =
            try container.decodeIfPresent(OrderedDictionary<String, Arazzo.OutputValue>.self, forKey: .outputs) ?? [:]
        parameters = try container.decodeList([Arazzo.ReusableOr<Arazzo.Parameter>].self, forKey: .parameters)
        vendorExtensions = try decoder.decodeVendorExtensions()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workflowId, forKey: .workflowId)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(inputs, forKey: .inputs)
        try container.encodeNonEmpty(dependsOn, forKey: .dependsOn)
        try container.encode(steps, forKey: .steps)
        try container.encodeNonEmpty(successActions, forKey: .successActions)
        try container.encodeNonEmpty(failureActions, forKey: .failureActions)
        try container.encodeNonEmpty(outputs, forKey: .outputs)
        try container.encodeNonEmpty(parameters, forKey: .parameters)
        try encoder.encodeVendorExtensions(vendorExtensions)
    }
}
