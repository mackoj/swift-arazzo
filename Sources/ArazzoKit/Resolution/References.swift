import JSONPath
extension Arazzo {
    /// A reference to a workflow: a local `workflowId` or `$sourceDescriptions.<name>.<workflowId>`.
    public enum WorkflowReference: Hashable, Sendable, CustomStringConvertible {
        case local(workflowId: String)
        case sourceDescription(name: String, workflowId: String)

        public init?(_ string: String) {
            if string.hasPrefix("$") {
                guard let expression = try? RuntimeExpression(string),
                    case .sourceDescriptions(let name, let reference) = expression.kind
                else { return nil }
                self = .sourceDescription(name: name, workflowId: reference)
            } else {
                guard !string.isEmpty else { return nil }
                self = .local(workflowId: string)
            }
        }

        public var workflowId: String {
            switch self {
            case .local(let id), .sourceDescription(_, let id): id
            }
        }

        public var description: String {
            switch self {
            case .local(let id): id
            case .sourceDescription(let name, let id): "$sourceDescriptions.\(name).\(id)"
            }
        }
    }

    /// A step reference used by step-level `dependsOn` (Arazzo 1.1).
    public enum StepReference: Hashable, Sendable, CustomStringConvertible {
        /// A step in the current workflow.
        case local(stepId: String)
        /// `$workflows.<workflowId>.steps.<stepId>`
        case workflow(workflowId: String, stepId: String)
        /// `$sourceDescriptions.<name>.<workflowId>.steps.<stepId>`
        case sourceDescription(name: String, workflowId: String, stepId: String)

        public init?(_ string: String) {
            if string.hasPrefix("$workflows.") {
                let rest = string.dropFirst("$workflows.".count)
                guard let range = rest.firstRange(of: ".steps.") else { return nil }
                let workflowId = rest[..<range.lowerBound]
                let stepId = rest[range.upperBound...]
                guard ExpressionGrammar.isStrictIdentifier(workflowId), !stepId.isEmpty else { return nil }
                self = .workflow(workflowId: String(workflowId), stepId: String(stepId))
            } else if string.hasPrefix("$sourceDescriptions.") {
                let rest = string.dropFirst("$sourceDescriptions.".count)
                guard let dot = rest.firstIndex(of: "."),
                    let range = rest[rest.index(after: dot)...].firstRange(of: ".steps.")
                else { return nil }
                let name = rest[..<dot]
                let workflowId = rest[rest.index(after: dot)..<range.lowerBound]
                let stepId = rest[range.upperBound...]
                guard ExpressionGrammar.isStrictIdentifier(name), !workflowId.isEmpty, !stepId.isEmpty else {
                    return nil
                }
                self = .sourceDescription(name: String(name), workflowId: String(workflowId), stepId: String(stepId))
            } else {
                guard !string.isEmpty, !string.hasPrefix("$") else { return nil }
                self = .local(stepId: string)
            }
        }

        public var stepId: String {
            switch self {
            case .local(let id), .workflow(_, let id), .sourceDescription(_, _, let id): id
            }
        }

        public var description: String {
            switch self {
            case .local(let id): id
            case .workflow(let w, let s): "$workflows.\(w).steps.\(s)"
            case .sourceDescription(let n, let w, let s): "$sourceDescriptions.\(n).\(w).steps.\(s)"
            }
        }
    }

    /// The operation (or channel) a step invokes, decoded from `operationId`, `operationPath` or `channelPath`.
    public enum OperationReference: Hashable, Sendable {
        /// A bare `operationId`.
        case operationId(String)
        /// `$sourceDescriptions.<name>.<operationId>`
        case qualifiedOperationId(sourceDescription: String, operationId: String)
        /// `{$sourceDescriptions.<name>.url}#/json/pointer` (or another `$sourceDescriptions` expression).
        case path(sourceDescription: String, pointer: JSONPointer?, raw: String)

        /// The source description name, when the reference names one.
        public var sourceDescriptionName: String? {
            switch self {
            case .operationId: nil
            case .qualifiedOperationId(let name, _), .path(let name, _, _): name
            }
        }
    }
}

extension Arazzo.Step.Target {
    /// The operation reference for `operationId`, `operationPath` and `channelPath` targets.
    /// `nil` for workflow targets or malformed paths.
    public var operationReference: Arazzo.OperationReference? {
        switch self {
        case .workflowId:
            return nil
        case .operationId(let id):
            if id.hasPrefix("$sourceDescriptions."),
                let expression = try? Arazzo.RuntimeExpression(id),
                case .sourceDescriptions(let name, let operationId) = expression.kind
            {
                return .qualifiedOperationId(sourceDescription: name, operationId: operationId)
            }
            return .operationId(id)
        case .operationPath(let raw), .channelPath(let raw):
            let template = Arazzo.ExpressionTemplate(raw)
            if let first = template.expressions.first, case .sourceDescriptions(let name, _) = first.kind {
                var pointer: JSONPointer?
                if case .literal(let text)? = template.segments.last, let hash = text.firstIndex(of: "#") {
                    pointer = try? JSONPointer(String(text[hash...]))
                }
                return .path(sourceDescription: name, pointer: pointer, raw: raw)
            }
            // Spec examples also use a bare expression: `$sourceDescriptions.async.placeOrder`.
            if let expression = try? Arazzo.RuntimeExpression(raw),
                case .sourceDescriptions(let name, _) = expression.kind
            {
                return .path(sourceDescription: name, pointer: nil, raw: raw)
            }
            return nil
        }
    }

    /// The workflow reference for `workflowId` targets.
    public var workflowReference: Arazzo.WorkflowReference? {
        if case .workflowId(let id) = self { return Arazzo.WorkflowReference(id) }
        return nil
    }
}

// MARK: - Expression collection

extension Arazzo.Criterion {
    /// The runtime expressions this criterion reads (context, condition operands, embedded expressions).
    public var runtimeExpressions: [Arazzo.RuntimeExpression] {
        var result: [Arazzo.RuntimeExpression] = context.map { [$0] } ?? []
        if effectiveType == .simple, let parsed = try? Arazzo.Condition(condition) {
            result += parsed.runtimeExpressions
        } else {
            result += Arazzo.ExpressionTemplate(condition).expressions
        }
        return result
    }
}

extension Arazzo.Step {
    /// Every runtime expression the step reads, resolving reusable components through `components`.
    public func runtimeExpressions(components: Arazzo.Components = .noComponents) -> [Arazzo.RuntimeExpression] {
        var result: [Arazzo.RuntimeExpression] = []
        for parameter in parameters {
            if let resolved = try? components.resolve(parameter) {
                result += resolved.value.runtimeExpressions
            }
        }
        result += requestBody?.runtimeExpressions ?? []
        result += (successCriteria ?? []).flatMap(\.runtimeExpressions)
        for action in onSuccess {
            if let resolved = try? components.resolve(action) {
                result += resolved.criteria.flatMap(\.runtimeExpressions)
                result += resolved.parameters.compactMap { try? components.resolve($0) }.flatMap(\.value.runtimeExpressions)
            }
        }
        for action in onFailure {
            if let resolved = try? components.resolve(action) {
                result += resolved.criteria.flatMap(\.runtimeExpressions)
                result += resolved.parameters.compactMap { try? components.resolve($0) }.flatMap(\.value.runtimeExpressions)
            }
        }
        result += outputs.values.map(\.runtimeExpression)
        if let correlationId, let expression = try? Arazzo.RuntimeExpression(correlationId) {
            result.append(expression)
        }
        return result
    }
}

// MARK: - Effective parameters & actions

extension Arazzo.Document {
    /// The parameters a step receives: workflow-level parameters overridden (by `name` + `in`)
    /// by the step's own, with reusable references resolved. Order: workflow parameters first
    /// (in place when overridden), then new step parameters.
    public func effectiveParameters(for step: Arazzo.Step, in workflow: Arazzo.Workflow) throws -> [Arazzo.Parameter] {
        var result = OrderedDictionary<Arazzo.Parameter.Identity, Arazzo.Parameter>()
        for parameter in workflow.parameters {
            let resolved = try components.resolve(parameter)
            result[resolved.identity] = resolved
        }
        for parameter in step.parameters {
            let resolved = try components.resolve(parameter)
            result[resolved.identity] = resolved
        }
        return result.values
    }

    /// The success actions considered for a step: the step's `onSuccess` actions followed by the
    /// workflow-level `successActions` it does not override (by `name`).
    public func effectiveSuccessActions(for step: Arazzo.Step, in workflow: Arazzo.Workflow) throws
        -> [Arazzo.SuccessAction]
    {
        let own = try step.onSuccess.map(components.resolve)
        let names = Set(own.map(\.name))
        return own + (try workflow.successActions.map(components.resolve)).filter { !names.contains($0.name) }
    }

    /// The failure actions considered for a step: the step's `onFailure` actions followed by the
    /// workflow-level `failureActions` it does not override (by `name`).
    public func effectiveFailureActions(for step: Arazzo.Step, in workflow: Arazzo.Workflow) throws
        -> [Arazzo.FailureAction]
    {
        let own = try step.onFailure.map(components.resolve)
        let names = Set(own.map(\.name))
        return own + (try workflow.failureActions.map(components.resolve)).filter { !names.contains($0.name) }
    }

    /// The workflow's input schema with a local `#/components/inputs/...` reference resolved.
    public func resolvedInputs(for workflow: Arazzo.Workflow) throws -> Arazzo.JSONSchema? {
        guard let inputs = workflow.inputs else { return nil }
        return try components.resolveInputs(inputs)
    }
}

// MARK: - Execution order

extension Arazzo.Workflow {
    public struct DependencyCycleError: Error, Hashable, Sendable, CustomStringConvertible {
        public let stepIds: [String]
        public var description: String { "Steps form a dependency cycle: \(stepIds.joined(separator: " → "))" }
    }

    /// The steps of this workflow that `step` must wait for: explicit `dependsOn` entries plus
    /// implicit dependencies from `$steps.<id>.outputs` references (as required by the specification).
    public func localDependencies(of step: Arazzo.Step, components: Arazzo.Components = .noComponents) -> [String] {
        var result: [String] = []
        func add(_ id: String) {
            if id != step.stepId, self.step(id: id) != nil, !result.contains(id) { result.append(id) }
        }
        for entry in step.dependsOn {
            switch Arazzo.StepReference(entry) {
            case .local(let id)?: add(id)
            case .workflow(let workflowId, let id)? where workflowId == self.workflowId: add(id)
            default: break
            }
        }
        for expression in step.runtimeExpressions(components: components) {
            if let id = expression.referencedStepID { add(id) }
        }
        return result
    }

    /// A step order satisfying explicit and implicit dependencies, as close to the declared order
    /// as possible. Throws when the dependencies are cyclic.
    public func executionOrder(components: Arazzo.Components = .noComponents) throws -> [Arazzo.Step] {
        let dependencies = Dictionary(
            steps.map { ($0.stepId, Set(localDependencies(of: $0, components: components))) },
            uniquingKeysWith: { a, b in a.union(b) })
        var completed = Set<String>()
        var ordered: [Arazzo.Step] = []
        var remaining = steps
        while !remaining.isEmpty {
            guard let index = remaining.firstIndex(where: { (dependencies[$0.stepId] ?? []).isSubset(of: completed) })
            else {
                throw DependencyCycleError(stepIds: Self.findCycle(in: dependencies) ?? remaining.map(\.stepId))
            }
            let step = remaining.remove(at: index)
            ordered.append(step)
            completed.insert(step.stepId)
        }
        return ordered
    }

    static func findCycle(in graph: [String: Set<String>]) -> [String]? {
        var state: [String: Int] = [:]  // 1 = visiting, 2 = done
        var stack: [String] = []
        func visit(_ node: String) -> [String]? {
            state[node] = 1
            stack.append(node)
            for next in (graph[node] ?? []).sorted() {
                if state[next] == 1, let start = stack.firstIndex(of: next) {
                    return Array(stack[start...]) + [next]
                }
                if state[next] == nil, let cycle = visit(next) { return cycle }
            }
            stack.removeLast()
            state[node] = 2
            return nil
        }
        for node in graph.keys.sorted() where state[node] == nil {
            if let cycle = visit(node) { return cycle }
        }
        return nil
    }
}
