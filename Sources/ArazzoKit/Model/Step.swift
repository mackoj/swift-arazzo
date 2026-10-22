import JSONPath
extension Arazzo {
    /// A single workflow step (the "Step Object"): a call to an OpenAPI operation,
    /// an AsyncAPI operation/channel, or another workflow.
    public struct Step: Hashable, Sendable, VendorExtendable {
        /// What the step invokes. The four fields are mutually exclusive.
        public enum Target: Hashable, Sendable {
            /// `operationId` – plain, or `$sourceDescriptions.<name>.<operationId>`.
            case operationId(String)
            /// `operationPath` – e.g. `{$sourceDescriptions.petstore.url}#/paths/~1pets/get`.
            case operationPath(String)
            /// `channelPath` – an AsyncAPI channel reference (Arazzo 1.1).
            case channelPath(String)
            /// `workflowId` – local, or `$sourceDescriptions.<name>.<workflowId>`.
            case workflowId(String)

            public var fieldName: String {
                switch self {
                case .operationId: "operationId"
                case .operationPath: "operationPath"
                case .channelPath: "channelPath"
                case .workflowId: "workflowId"
                }
            }

            public var rawValue: String {
                switch self {
                case .operationId(let v), .operationPath(let v), .channelPath(let v), .workflowId(let v): v
                }
            }

            /// `true` when the step targets a workflow (parameters then map to workflow inputs).
            public var isWorkflow: Bool {
                if case .workflowId = self { return true }
                return false
            }
        }

        /// Message flow intent for AsyncAPI steps (Arazzo 1.1).
        public enum AsyncAction: String, Hashable, Sendable, Codable, CaseIterable {
            case send
            case receive
        }

        /// Unique within the workflow; case-sensitive. SHOULD match `[A-Za-z0-9_\-]+`.
        public var stepId: String
        public var description: String?
        public var target: Target
        /// Overrides workflow-level parameters with the same `name` + `in`.
        public var parameters: [ReusableOr<Parameter>]
        public var requestBody: RequestBody?
        /// When present, MUST contain at least one criterion; all must pass.
        public var successCriteria: [Criterion]?
        /// When omitted, the next sequential step executes.
        public var onSuccess: [ReusableOr<SuccessAction>]
        /// When omitted, the workflow breaks and returns.
        public var onFailure: [ReusableOr<FailureAction>]
        /// Keys MUST match `^[a-zA-Z0-9\.\-_]+$`.
        public var outputs: OrderedDictionary<String, OutputValue>
        /// Milliseconds to wait before failing the step (Arazzo 1.1).
        public var timeout: Int?
        /// AsyncAPI correlation id for `receive` steps (Arazzo 1.1).
        public var correlationId: String?
        /// AsyncAPI `send` / `receive` (Arazzo 1.1).
        public var action: AsyncAction?
        /// Steps that must complete first (Arazzo 1.1): a `stepId`,
        /// `$workflows.<workflowId>.steps.<stepId>` or `$sourceDescriptions.<name>.<workflowId>.steps.<stepId>`.
        public var dependsOn: [String]
        public var vendorExtensions: VendorExtensions

        public init(
            stepId: String,
            description: String? = nil,
            target: Target,
            parameters: [ReusableOr<Parameter>] = [],
            requestBody: RequestBody? = nil,
            successCriteria: [Criterion]? = nil,
            onSuccess: [ReusableOr<SuccessAction>] = [],
            onFailure: [ReusableOr<FailureAction>] = [],
            outputs: OrderedDictionary<String, OutputValue> = [:],
            timeout: Int? = nil,
            correlationId: String? = nil,
            action: AsyncAction? = nil,
            dependsOn: [String] = [],
            vendorExtensions: VendorExtensions = [:]
        ) {
            self.stepId = stepId
            self.description = description
            self.target = target
            self.parameters = parameters
            self.requestBody = requestBody
            self.successCriteria = successCriteria
            self.onSuccess = onSuccess
            self.onFailure = onFailure
            self.outputs = outputs
            self.timeout = timeout
            self.correlationId = correlationId
            self.action = action
            self.dependsOn = dependsOn
            self.vendorExtensions = vendorExtensions
        }

        /// `true` when the step uses Arazzo 1.1-only fields.
        public var usesV1_1Features: Bool {
            if case .channelPath = target { return true }
            return timeout != nil || correlationId != nil || action != nil || !dependsOn.isEmpty
        }
    }
}

extension Arazzo.Step: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case stepId, description, operationId, operationPath, channelPath, workflowId, parameters, requestBody,
            successCriteria, onSuccess, onFailure, outputs, timeout, correlationId, action, dependsOn
    }

    public init(from decoder: any Decoder) throws {
        try decoder.ensureNoUnknownKeys(CodingKeys.self, objectName: "Step Object")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stepId = try container.decode(String.self, forKey: .stepId)
        description = try container.decodeIfPresent(String.self, forKey: .description)

        var targets: [Target] = []
        if let v = try container.decodeIfPresent(String.self, forKey: .operationId) { targets.append(.operationId(v)) }
        if let v = try container.decodeIfPresent(String.self, forKey: .operationPath) {
            targets.append(.operationPath(v))
        }
        if let v = try container.decodeIfPresent(String.self, forKey: .channelPath) { targets.append(.channelPath(v)) }
        if let v = try container.decodeIfPresent(String.self, forKey: .workflowId) { targets.append(.workflowId(v)) }
        guard targets.count == 1 else {
            let message =
                targets.isEmpty
                ? "Step '\(stepId)' must specify one of operationId, operationPath, channelPath or workflowId."
                : "Step '\(stepId)' specifies \(targets.map(\.fieldName).joined(separator: " and ")), which are mutually exclusive."
            throw decodingError(message, codingPath: container.codingPath)
        }
        target = targets[0]

        parameters = try container.decodeList([Arazzo.ReusableOr<Arazzo.Parameter>].self, forKey: .parameters)
        requestBody = try container.decodeIfPresent(Arazzo.RequestBody.self, forKey: .requestBody)
        successCriteria = try container.decodeIfPresent([Arazzo.Criterion].self, forKey: .successCriteria)
        onSuccess = try container.decodeList([Arazzo.ReusableOr<Arazzo.SuccessAction>].self, forKey: .onSuccess)
        onFailure = try container.decodeList([Arazzo.ReusableOr<Arazzo.FailureAction>].self, forKey: .onFailure)
        outputs =
            try container.decodeIfPresent(OrderedDictionary<String, Arazzo.OutputValue>.self, forKey: .outputs) ?? [:]
        timeout = try container.decodeIfPresent(Int.self, forKey: .timeout)
        correlationId = try container.decodeIfPresent(String.self, forKey: .correlationId)
        if let raw = try container.decodeIfPresent(String.self, forKey: .action) {
            guard let action = AsyncAction(rawValue: raw) else {
                throw decodingError(
                    "Step action '\(raw)' must be 'send' or 'receive'.",
                    codingPath: container.codingPath + [CodingKeys.action])
            }
            self.action = action
        } else {
            action = nil
        }
        dependsOn = try container.decodeList([String].self, forKey: .dependsOn)
        vendorExtensions = try decoder.decodeVendorExtensions()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stepId, forKey: .stepId)
        try container.encodeIfPresent(description, forKey: .description)
        switch target {
        case .operationId(let v): try container.encode(v, forKey: .operationId)
        case .operationPath(let v): try container.encode(v, forKey: .operationPath)
        case .channelPath(let v): try container.encode(v, forKey: .channelPath)
        case .workflowId(let v): try container.encode(v, forKey: .workflowId)
        }
        try container.encodeIfPresent(action, forKey: .action)
        try container.encodeIfPresent(correlationId, forKey: .correlationId)
        try container.encodeIfPresent(timeout, forKey: .timeout)
        try container.encodeNonEmpty(dependsOn, forKey: .dependsOn)
        try container.encodeNonEmpty(parameters, forKey: .parameters)
        try container.encodeIfPresent(requestBody, forKey: .requestBody)
        try container.encodeIfPresent(successCriteria, forKey: .successCriteria)
        try container.encodeNonEmpty(onSuccess, forKey: .onSuccess)
        try container.encodeNonEmpty(onFailure, forKey: .onFailure)
        try container.encodeNonEmpty(outputs, forKey: .outputs)
        try encoder.encodeVendorExtensions(vendorExtensions)
    }
}
