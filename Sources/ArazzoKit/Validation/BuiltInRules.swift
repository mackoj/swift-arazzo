import JSONPath
/// The validation rules shipped with ArazzoKit.
enum BuiltInRules {
    static let all: [Arazzo.ValidationRule] = [
        specificationVersion,
        selfURI,
        sourceDescriptions,
        workflows,
        workflowDependencies,
        steps,
        stepTargets,
        stepDependencies,
        asyncSteps,
        parameters,
        actions,
        criteria,
        selectors,
        outputs,
        components,
        runtimeExpressions,
        inputs,
        payloadReplacements,
    ]

    static let identifierStrictPattern = "[A-Za-z0-9_\\-]+"
    static let keyPattern = "^[a-zA-Z0-9\\.\\-_]+$"

    // MARK: Document level

    static let specificationVersion = Arazzo.ValidationRule("specification-version") { document, report in
        if !document.arazzo.isSupported {
            report.warning(
                "/arazzo",
                "Arazzo \(document.arazzo) is not a version this library models (supported: 1.0.x, 1.1.x); some fields may be ignored."
            )
        }
    }

    static let selfURI = Arazzo.ValidationRule("self-uri") { document, report in
        guard let selfURI = document.selfURI else { return }
        if !document.arazzo.supportsV1_1Features {
            report.warning(
                "/$self", "`$self` was introduced in Arazzo 1.1 but the document declares \(document.arazzo).")
        }
        if selfURI.contains("#") {
            report.error("/$self", "`$self` MUST NOT contain a fragment identifier.")
        }
        if selfURI.isEmpty || selfURI.contains(where: { $0.isWhitespace }) {
            report.error("/$self", "`$self` MUST be a valid URI-reference (RFC 3986).")
        }
    }

    static let sourceDescriptions = Arazzo.ValidationRule("source-descriptions") { document, report in
        if document.sourceDescriptions.isEmpty {
            report.error("/sourceDescriptions", "At least one source description is REQUIRED.")
        }
        var seen = Set<String>()
        for (index, source) in document.sourceDescriptions.enumerated() {
            let path = "/sourceDescriptions/\(index)"
            if !seen.insert(source.name).inserted {
                report.error(path + "/name", "Source description name '\(source.name)' is not unique.")
            }
            if !ExpressionGrammar.isStrictIdentifier(source.name) {
                report.warning(
                    path + "/name",
                    "Source description name '\(source.name)' SHOULD match \(identifierStrictPattern); runtime expressions cannot reference it otherwise."
                )
            }
            if source.url.isEmpty || source.url.contains(where: { $0.isWhitespace }) {
                report.error(path + "/url", "Source description url '\(source.url)' MUST be a valid URI-reference.")
            }
        }
    }

    static let workflows = Arazzo.ValidationRule("workflows") { document, report in
        if document.workflows.isEmpty {
            report.error("/workflows", "At least one workflow is REQUIRED.")
        }
        var seen = Set<String>()
        for (index, workflow) in document.workflows.enumerated() {
            let path = "/workflows/\(index)/workflowId"
            if !seen.insert(workflow.workflowId).inserted {
                report.error(path, "workflowId '\(workflow.workflowId)' MUST be unique within the description.")
            }
            if !ExpressionGrammar.isStrictIdentifier(workflow.workflowId) {
                report.warning(path, "workflowId '\(workflow.workflowId)' SHOULD match \(identifierStrictPattern).")
            }
        }
    }

    static let workflowDependencies = Arazzo.ValidationRule("workflow-dependencies") { document, report in
        var graph: [String: Set<String>] = [:]
        for (index, workflow) in document.workflows.enumerated() {
            var local = Set<String>()
            for (depIndex, dependency) in workflow.dependsOn.enumerated() {
                let path = "/workflows/\(index)/dependsOn/\(depIndex)"
                guard let reference = Arazzo.WorkflowReference(dependency) else {
                    report.error(
                        path,
                        "'\(dependency)' is neither a workflowId nor a $sourceDescriptions.<name>.<workflowId> expression."
                    )
                    continue
                }
                switch reference {
                case .local(let id):
                    if id == workflow.workflowId {
                        report.error(path, "Workflow '\(id)' cannot depend on itself.")
                    } else if document.workflow(id: id) == nil {
                        report.error(path, "Workflow '\(workflow.workflowId)' depends on unknown workflow '\(id)'.")
                    } else {
                        local.insert(id)
                    }
                case .sourceDescription(let name, _):
                    checkArazzoSource(name, in: document, path: path, report: &report)
                }
            }
            graph[workflow.workflowId, default: []].formUnion(local)
        }
        if let cycle = Arazzo.Workflow.findCycle(in: graph) {
            report.error("/workflows", "Workflow dependencies form a cycle: \(cycle.joined(separator: " → ")).")
        }
    }

    // MARK: Steps

    static let steps = Arazzo.ValidationRule("steps") { document, report in
        for (wIndex, workflow) in document.workflows.enumerated() {
            if workflow.steps.isEmpty {
                report.error(
                    "/workflows/\(wIndex)/steps", "Workflow '\(workflow.workflowId)' MUST have at least one step.")
            }
            var seen = Set<String>()
            for (sIndex, step) in workflow.steps.enumerated() {
                let path = "/workflows/\(wIndex)/steps/\(sIndex)"
                if !seen.insert(step.stepId).inserted {
                    report.error(
                        path + "/stepId",
                        "stepId '\(step.stepId)' MUST be unique within workflow '\(workflow.workflowId)'.")
                }
                if !ExpressionGrammar.isStrictIdentifier(step.stepId) {
                    report.warning(path + "/stepId", "stepId '\(step.stepId)' SHOULD match \(identifierStrictPattern).")
                }
                if let criteria = step.successCriteria, criteria.isEmpty {
                    report.error(
                        path + "/successCriteria",
                        "successCriteria, when provided, MUST contain at least one criterion.")
                }
                if step.requestBody != nil, step.target.isWorkflow {
                    report.warning(
                        path + "/requestBody", "requestBody is only applicable to operation steps, not workflow steps.")
                }
            }
        }
    }

    static let stepTargets = Arazzo.ValidationRule("step-targets") { document, report in
        let apiSources = document.apiSourceDescriptions
        for (wIndex, workflow) in document.workflows.enumerated() {
            for (sIndex, step) in workflow.steps.enumerated() {
                let path = "/workflows/\(wIndex)/steps/\(sIndex)/\(step.target.fieldName)"
                switch step.target {
                case .operationId(let id):
                    if id.hasPrefix("$") {
                        guard case .qualifiedOperationId(let name, _)? = step.target.operationReference else {
                            report.error(
                                path,
                                "operationId '\(id)' must be a $sourceDescriptions.<name>.<operationId> expression.")
                            break
                        }
                        if let source = document.sourceDescription(named: name) {
                            if source.type == .arazzo {
                                report.error(
                                    path,
                                    "operationId references '\(name)', which is an Arazzo document; use workflowId instead."
                                )
                            }
                        } else {
                            report.error(path, "operationId references unknown source description '\(name)'.")
                        }
                    } else if apiSources.count > 1 {
                        report.error(
                            path,
                            "With multiple (non arazzo) source descriptions, operationId '\(id)' MUST be written as $sourceDescriptions.<name>.\(id)."
                        )
                    } else if apiSources.isEmpty {
                        report.error(
                            path,
                            "operationId '\(id)' cannot be resolved: there is no openapi or asyncapi source description."
                        )
                    }
                case .operationPath(let raw), .channelPath(let raw):
                    guard let reference = step.target.operationReference, let name = reference.sourceDescriptionName
                    else {
                        report.error(
                            path,
                            "'\(raw)' MUST identify the source description with a runtime expression, e.g. '{$sourceDescriptions.<name>.url}#/paths/...'."
                        )
                        break
                    }
                    if let source = document.sourceDescription(named: name) {
                        if case .channelPath = step.target, let type = source.type, type != .asyncapi {
                            report.warning(
                                path,
                                "channelPath references '\(name)', which is a \(type.rawValue) description, not asyncapi."
                            )
                        }
                        if source.type == .arazzo {
                            report.error(
                                path, "'\(name)' is an Arazzo document; operations cannot be referenced in it.")
                        }
                    } else {
                        report.error(path, "References unknown source description '\(name)'.")
                    }
                case .workflowId(let id):
                    guard let reference = Arazzo.WorkflowReference(id) else {
                        report.error(
                            path, "workflowId '\(id)' must be a workflowId or $sourceDescriptions.<name>.<workflowId>.")
                        break
                    }
                    switch reference {
                    case .local(let localId):
                        if localId == workflow.workflowId {
                            report.warning(path, "Step '\(step.stepId)' invokes its own workflow recursively.")
                        }
                        if document.workflow(id: localId) == nil {
                            let hint =
                                document.sourceDescriptions.contains { $0.type == .arazzo }
                                ? " Workflows from arazzo source descriptions MUST be referenced as $sourceDescriptions.<name>.\(localId)."
                                : ""
                            report.error(path, "Unknown workflowId '\(localId)'.\(hint)")
                        }
                    case .sourceDescription(let name, _):
                        checkArazzoSource(name, in: document, path: path, report: &report)
                    }
                }
            }
        }
    }

    static let stepDependencies = Arazzo.ValidationRule("step-dependencies") { document, report in
        for (wIndex, workflow) in document.workflows.enumerated() {
            for (sIndex, step) in workflow.steps.enumerated() {
                for (dIndex, entry) in step.dependsOn.enumerated() {
                    let path = "/workflows/\(wIndex)/steps/\(sIndex)/dependsOn/\(dIndex)"
                    guard let reference = Arazzo.StepReference(entry) else {
                        report.error(
                            path,
                            "'\(entry)' must be a stepId, $workflows.<workflowId>.steps.<stepId> or $sourceDescriptions.<name>.<workflowId>.steps.<stepId>."
                        )
                        continue
                    }
                    switch reference {
                    case .local(let id):
                        if id == step.stepId {
                            report.error(path, "Step '\(id)' cannot depend on itself.")
                        } else if workflow.step(id: id) == nil {
                            report.error(path, "Unknown stepId '\(id)' in workflow '\(workflow.workflowId)'.")
                        }
                    case .workflow(let workflowId, let stepId):
                        guard let target = document.workflow(id: workflowId) else {
                            report.error(path, "Unknown workflow '\(workflowId)'.")
                            break
                        }
                        if target.step(id: stepId) == nil {
                            report.error(path, "Workflow '\(workflowId)' has no step '\(stepId)'.")
                        }
                    case .sourceDescription(let name, _, _):
                        checkArazzoSource(name, in: document, path: path, report: &report)
                    }
                }
            }
            // Cycles across explicit and implicit dependencies.
            let graph = Dictionary(
                workflow.steps.map {
                    ($0.stepId, Set(workflow.localDependencies(of: $0, components: document.components)))
                },
                uniquingKeysWith: { a, b in a.union(b) })
            if let cycle = Arazzo.Workflow.findCycle(in: graph) {
                report.error(
                    "/workflows/\(wIndex)/steps",
                    "Steps of workflow '\(workflow.workflowId)' form a dependency cycle: \(cycle.joined(separator: " → "))."
                )
            }
        }
    }

    static let asyncSteps = Arazzo.ValidationRule("async-steps") { document, report in
        let v11 = document.arazzo.supportsV1_1Features
        for (wIndex, workflow) in document.workflows.enumerated() {
            for (sIndex, step) in workflow.steps.enumerated() {
                let path = "/workflows/\(wIndex)/steps/\(sIndex)"
                if !v11 {
                    var fields: [String] = []
                    if case .channelPath = step.target { fields.append("channelPath") }
                    if step.action != nil { fields.append("action") }
                    if step.correlationId != nil { fields.append("correlationId") }
                    if step.timeout != nil { fields.append("timeout") }
                    if !step.dependsOn.isEmpty { fields.append("dependsOn") }
                    if !fields.isEmpty {
                        report.warning(
                            path,
                            "\(fields.joined(separator: ", ")) \(fields.count == 1 ? "was" : "were") introduced in Arazzo 1.1 but the document declares \(document.arazzo)."
                        )
                    }
                }
                if let timeout = step.timeout, timeout < 0 {
                    report.error(path + "/timeout", "timeout MUST be a non-negative number of milliseconds.")
                }
                if step.correlationId != nil, step.action != .receive {
                    report.warning(
                        path + "/correlationId", "correlationId only applies to asyncapi steps with action 'receive'.")
                }
                if step.action != nil || step.correlationId != nil {
                    if let name = step.target.operationReference?.sourceDescriptionName,
                        let type = document.sourceDescription(named: name)?.type, type != .asyncapi
                    {
                        report.warning(
                            path + "/action",
                            "action/correlationId only apply to asyncapi steps, but '\(name)' is \(type.rawValue).")
                    }
                    if step.target.isWorkflow {
                        report.warning(path + "/action", "action/correlationId do not apply to workflow steps.")
                    }
                }
                if step.action == .receive, step.successCriteria == nil {
                    report.warning(
                        path,
                        "AsyncAPI receive steps SHOULD define successCriteria evaluating the received message (e.g. $message.payload)."
                    )
                }
            }
        }
    }

    // MARK: Parameters

    enum ParameterSite {
        case workflow
        case step(Arazzo.Step.Target)
        case action(Arazzo.ActionTarget?)
    }

    static func parameterLists(
        in document: Arazzo.Document
    ) -> [(String, [Arazzo.ReusableOr<Arazzo.Parameter>], ParameterSite)] {
        var result: [(String, [Arazzo.ReusableOr<Arazzo.Parameter>], ParameterSite)] = []
        for (wIndex, workflow) in document.workflows.enumerated() {
            let wPath = "/workflows/\(wIndex)"
            result.append((wPath + "/parameters", workflow.parameters, .workflow))
            for (aIndex, action) in workflow.successActions.enumerated() {
                if let action = action.inlineValue {
                    result.append(
                        ("\(wPath)/successActions/\(aIndex)/parameters", action.parameters, .action(action.target)))
                }
            }
            for (aIndex, action) in workflow.failureActions.enumerated() {
                if let action = action.inlineValue {
                    result.append(
                        ("\(wPath)/failureActions/\(aIndex)/parameters", action.parameters, .action(action.target)))
                }
            }
            for (sIndex, step) in workflow.steps.enumerated() {
                let sPath = "\(wPath)/steps/\(sIndex)"
                result.append((sPath + "/parameters", step.parameters, .step(step.target)))
                for (aIndex, action) in step.onSuccess.enumerated() {
                    if let action = action.inlineValue {
                        result.append(
                            ("\(sPath)/onSuccess/\(aIndex)/parameters", action.parameters, .action(action.target)))
                    }
                }
                for (aIndex, action) in step.onFailure.enumerated() {
                    if let action = action.inlineValue {
                        result.append(
                            ("\(sPath)/onFailure/\(aIndex)/parameters", action.parameters, .action(action.target)))
                    }
                }
            }
        }
        for (key, action) in document.components.successActions {
            result.append(
                ("/components/successActions/\(escape(key))/parameters", action.parameters, .action(action.target)))
        }
        for (key, action) in document.components.failureActions {
            result.append(
                ("/components/failureActions/\(escape(key))/parameters", action.parameters, .action(action.target)))
        }
        return result
    }

    static let parameters = Arazzo.ValidationRule("parameters") { document, report in
        let v11 = document.arazzo.supportsV1_1Features
        for (listPath, list, site) in parameterLists(in: document) {
            var identities = Set<Arazzo.Parameter.Identity>()
            var locations = Set<Arazzo.Parameter.Location>()
            for (index, entry) in list.enumerated() {
                let path = "\(listPath)/\(index)"
                let parameter: Arazzo.Parameter
                switch entry {
                case .inline(let value):
                    parameter = value
                case .reusable(let reusable):
                    guard let (type, name) = reusable.component else {
                        report.error(
                            path + "/reference", "'\(reusable.reference)' MUST reference $components.parameters.<name>."
                        )
                        continue
                    }
                    guard type == .parameters else {
                        report.error(
                            path + "/reference",
                            "'\(reusable.reference)' references \(type.rawValue); parameters MUST reference $components.parameters."
                        )
                        continue
                    }
                    guard var resolved = document.components.parameters[name] else {
                        report.error(path + "/reference", "No parameter named '\(name)' in components.")
                        continue
                    }
                    if let value = reusable.value { resolved.value = value }
                    parameter = resolved
                }

                if !identities.insert(parameter.identity).inserted {
                    report.error(
                        path,
                        "Duplicate parameter '\(parameter.name)'\(parameter.location.map { " in \($0.rawValue)" } ?? ""); lists MUST NOT include duplicates."
                    )
                }
                if let location = parameter.location { locations.insert(location) }
                if parameter.location == .querystring, !v11 {
                    report.warning(path + "/in", "The 'querystring' location was introduced in Arazzo 1.1.")
                }

                switch site {
                case .workflow:
                    break
                case .step(let target):
                    if parameter.location == nil, !target.isWorkflow {
                        report.error(
                            path + "/in",
                            "Parameter '\(parameter.name)' MUST specify `in` because the step targets an operation, not a workflow."
                        )
                    }
                case .action(let target):
                    if parameter.location != nil {
                        report.error(
                            path + "/in", "Action parameters map to workflow inputs; the `in` field MUST NOT be used.")
                    }
                    if target?.workflowId == nil {
                        report.warning(
                            path, "Action parameters are only passed to a target workflowId; this action has none.")
                    }
                }
            }
            if locations.contains(.querystring) && locations.contains(.query) {
                report.warning(
                    listPath, "A 'querystring' parameter cannot coexist with 'query' parameters for the same operation."
                )
            }
        }
        for (key, parameter) in document.components.parameters where parameter.location == .querystring && !v11 {
            report.warning(
                "/components/parameters/\(escape(key))/in", "The 'querystring' location was introduced in Arazzo 1.1.")
        }
    }

    // MARK: Actions

    static let actions = Arazzo.ValidationRule("actions") { document, report in
        func checkTarget(_ target: Arazzo.ActionTarget?, workflow: Arazzo.Workflow?, path: String) {
            switch target {
            case .step(let id)?:
                if let workflow {
                    if workflow.step(id: id) == nil {
                        report.error(
                            path + "/stepId", "stepId '\(id)' MUST be a step of workflow '\(workflow.workflowId)'.")
                    }
                } else if !document.workflows.contains(where: { $0.step(id: id) != nil }) {
                    report.warning(path + "/stepId", "No workflow has a step '\(id)'.")
                }
            case .workflow(let id)?:
                switch Arazzo.WorkflowReference(id) {
                case .local(let local)?:
                    if document.workflow(id: local) == nil {
                        report.error(path + "/workflowId", "Unknown workflowId '\(local)'.")
                    }
                case .sourceDescription(let name, _)?:
                    checkArazzoSource(name, in: document, path: path + "/workflowId", report: &report)
                case nil:
                    report.error(
                        path + "/workflowId", "'\(id)' must be a workflowId or $sourceDescriptions.<name>.<workflowId>."
                    )
                }
            case nil:
                break
            }
        }

        func checkFailure(_ action: Arazzo.FailureAction, workflow: Arazzo.Workflow?, path: String) {
            checkTarget(action.target, workflow: workflow, path: path)
            if case .retry(let retry) = action.kind {
                if let after = retry.retryAfter, after < 0 || !after.isFinite {
                    report.error(path + "/retryAfter", "retryAfter MUST be a non-negative number.")
                }
                if let limit = retry.retryLimit, limit < 0 {
                    report.error(path + "/retryLimit", "retryLimit MUST be a non-negative integer.")
                }
            }
        }

        func checkList<A>(
            _ list: [Arazzo.ReusableOr<A>], expected: Arazzo.RuntimeExpression.ComponentType,
            lookup: (String) -> A?, name: (A) -> String, check: (A, String) -> Void, path listPath: String
        ) {
            var names = Set<String>()
            for (index, entry) in list.enumerated() {
                let path = "\(listPath)/\(index)"
                let action: A
                switch entry {
                case .inline(let value):
                    action = value
                    check(value, path)
                case .reusable(let reusable):
                    if reusable.value != nil {
                        report.warning(path + "/value", "Reusable `value` only applies to parameter references.")
                    }
                    guard let (type, componentName) = reusable.component, type == expected else {
                        report.error(
                            path + "/reference",
                            "'\(reusable.reference)' MUST reference $components.\(expected.rawValue).<name>.")
                        continue
                    }
                    guard let resolved = lookup(componentName) else {
                        report.error(path + "/reference", "No \(expected.rawValue) component named '\(componentName)'.")
                        continue
                    }
                    action = resolved
                }
                if !names.insert(name(action)).inserted {
                    report.error(path, "Duplicate action '\(name(action))'; lists MUST NOT include duplicates.")
                }
            }
        }

        for (wIndex, workflow) in document.workflows.enumerated() {
            let wPath = "/workflows/\(wIndex)"
            checkList(
                workflow.successActions, expected: .successActions, lookup: { document.components.successActions[$0] },
                name: \.name, check: { checkTarget($0.target, workflow: workflow, path: $1) },
                path: wPath + "/successActions")
            checkList(
                workflow.failureActions, expected: .failureActions, lookup: { document.components.failureActions[$0] },
                name: \.name, check: { checkFailure($0, workflow: workflow, path: $1) }, path: wPath + "/failureActions"
            )
            for (sIndex, step) in workflow.steps.enumerated() {
                let sPath = "\(wPath)/steps/\(sIndex)"
                checkList(
                    step.onSuccess, expected: .successActions, lookup: { document.components.successActions[$0] },
                    name: \.name, check: { checkTarget($0.target, workflow: workflow, path: $1) },
                    path: sPath + "/onSuccess")
                checkList(
                    step.onFailure, expected: .failureActions, lookup: { document.components.failureActions[$0] },
                    name: \.name, check: { checkFailure($0, workflow: workflow, path: $1) }, path: sPath + "/onFailure")
                // Reusable actions resolved from components must target steps of *this* workflow.
                for (aIndex, entry) in step.onSuccess.enumerated() {
                    if entry.reusableValue != nil, let action = try? document.components.resolve(entry),
                        case .step(let id)? = action.target, workflow.step(id: id) == nil
                    {
                        report.error(
                            "\(sPath)/onSuccess/\(aIndex)",
                            "Referenced action targets step '\(id)', which is not in workflow '\(workflow.workflowId)'."
                        )
                    }
                }
                for (aIndex, entry) in step.onFailure.enumerated() {
                    if entry.reusableValue != nil, let action = try? document.components.resolve(entry),
                        case .step(let id)? = action.target, workflow.step(id: id) == nil
                    {
                        report.error(
                            "\(sPath)/onFailure/\(aIndex)",
                            "Referenced action targets step '\(id)', which is not in workflow '\(workflow.workflowId)'."
                        )
                    }
                }
            }
        }
        for (key, action) in document.components.successActions {
            checkTarget(action.target, workflow: nil, path: "/components/successActions/\(escape(key))")
        }
        for (key, action) in document.components.failureActions {
            checkFailure(action, workflow: nil, path: "/components/failureActions/\(escape(key))")
        }
    }

    // MARK: Criteria

    static func criteriaLists(in document: Arazzo.Document) -> [(String, [Arazzo.Criterion])] {
        var result: [(String, [Arazzo.Criterion])] = []
        func addActions<A>(_ list: [Arazzo.ReusableOr<A>], path: String, criteria: (A) -> [Arazzo.Criterion]) {
            for (index, entry) in list.enumerated() {
                if let action = entry.inlineValue { result.append(("\(path)/\(index)/criteria", criteria(action))) }
            }
        }
        for (wIndex, workflow) in document.workflows.enumerated() {
            let wPath = "/workflows/\(wIndex)"
            addActions(workflow.successActions, path: wPath + "/successActions", criteria: \.criteria)
            addActions(workflow.failureActions, path: wPath + "/failureActions", criteria: \.criteria)
            for (sIndex, step) in workflow.steps.enumerated() {
                let sPath = "\(wPath)/steps/\(sIndex)"
                result.append((sPath + "/successCriteria", step.successCriteria ?? []))
                addActions(step.onSuccess, path: sPath + "/onSuccess", criteria: \.criteria)
                addActions(step.onFailure, path: sPath + "/onFailure", criteria: \.criteria)
            }
        }
        for (key, action) in document.components.successActions {
            result.append(("/components/successActions/\(escape(key))/criteria", action.criteria))
        }
        for (key, action) in document.components.failureActions {
            result.append(("/components/failureActions/\(escape(key))/criteria", action.criteria))
        }
        return result
    }

    static let criteria = Arazzo.ValidationRule("criteria") { document, report in
        for (listPath, list) in criteriaLists(in: document) {
            for (index, criterion) in list.enumerated() {
                let path = "\(listPath)/\(index)"
                if let type = criterion.type, criterion.context == nil {
                    // The rule is literally "if type is specified", but a simple condition never uses context.
                    report.report(
                        type == .simple ? .warning : .error, path + "/context",
                        "context MUST be provided when type is specified.")
                }
                switch criterion.effectiveType {
                case .simple:
                    do {
                        _ = try Arazzo.Condition(criterion.condition)
                    } catch {
                        report.error(path + "/condition", "\(error)")
                    }
                case .regex:
                    let template = Arazzo.ExpressionTemplate(criterion.condition)
                    if !template.hasExpressions {
                        do {
                            _ = try Regex(criterion.condition)
                        } catch {
                            report.error(
                                path + "/condition", "Invalid regular expression '\(criterion.condition)': \(error)")
                        }
                    }
                case .jsonPath:
                    checkJSONPath(criterion.condition, version: .rfc9535, path: path + "/condition", report: &report)
                case .xPath:
                    break
                case .expressionType(let type):
                    if !document.arazzo.supportsV1_1Features {
                        let allowed10: [Arazzo.ExpressionType.Version] = [
                            .draftGoessnerDispatchJSONPath00, .xpath30, .xpath20, .xpath10,
                        ]
                        if type.kind == .jsonPointer || (type.hasAllowedVersion && !allowed10.contains(type.version)) {
                            report.warning(
                                path + "/type",
                                "\(type.kind.rawValue) \(type.version) was introduced in Arazzo 1.1; Arazzo 1.0 allows draft-goessner-dispatch-jsonpath-00, xpath-30, xpath-20 and xpath-10."
                            )
                        }
                    }
                    if type.kind == .jsonPath, type.hasAllowedVersion {
                        checkJSONPath(
                            criterion.condition, version: type.version, path: path + "/condition", report: &report)
                    }
                    if type.kind == .jsonPointer {
                        report.error(
                            path + "/type",
                            "Criterion types are simple, regex, jsonpath or xpath; jsonpointer is not a condition language."
                        )
                    } else if !type.hasAllowedVersion {
                        report.error(
                            path + "/type/version",
                            "'\(type.version)' is not a valid \(type.kind.rawValue) version (allowed: \(type.kind.allowedVersions.map(\.rawValue).joined(separator: ", ")))."
                        )
                    }
                }
            }
        }
    }

    // MARK: Selectors

    static func checkSelectorType(
        _ type: Arazzo.SelectorType, path: String, report: inout Arazzo.ValidationReporter
    ) {
        if case .expressionType(let expressionType) = type, !expressionType.hasAllowedVersion {
            report.error(
                path + "/version",
                "'\(expressionType.version)' is not a valid \(expressionType.kind.rawValue) version (allowed: \(expressionType.kind.allowedVersions.map(\.rawValue).joined(separator: ", ")))."
            )
        }
    }

    static func checkSelector(
        _ selector: Arazzo.Selector, path: String, v11: Bool, report: inout Arazzo.ValidationReporter
    ) {
        if !v11 {
            report.warning(path, "Selector Objects were introduced in Arazzo 1.1.")
        }
        if let error = selector.context.parseError {
            report.error(path + "/context", "\(error)")
        }
        checkSelectorType(selector.type, path: path + "/type", report: &report)
        if selector.type.kind == .jsonPath {
            checkJSONPath(
                selector.selector, version: selector.type.effectiveVersion, path: path + "/selector", report: &report)
        }
        if selector.type.kind == .jsonPointer, (try? JSONPointer(selector.selector)) == nil {
            report.error(path + "/selector", "'\(selector.selector)' is not a valid JSON Pointer.")
        }
        if selector.selector.isEmpty, selector.type.kind != .jsonPointer {
            report.error(path + "/selector", "selector MUST NOT be empty.")
        }
    }

    static func selectorsInJSON(_ value: JSONValue, path: String) -> [(String, Arazzo.Selector)] {
        if let selector = Arazzo.Selector(json: value) { return [(path, selector)] }
        switch value {
        case .array(let values):
            return values.enumerated().flatMap { selectorsInJSON($1, path: "\(path)/\($0)") }
        case .object(let object):
            return object.flatMap { selectorsInJSON($0.value, path: "\(path)/\(escape($0.key))") }
        default:
            return []
        }
    }

    static func selectors(in value: Arazzo.Value, path: String) -> [(String, Arazzo.Selector)] {
        switch value {
        case .selector(let selector): [(path, selector)]
        case .literal(let json): selectorsInJSON(json, path: path)
        case .expression: []
        }
    }

    static let selectors = Arazzo.ValidationRule("selectors") { document, report in
        let v11 = document.arazzo.supportsV1_1Features
        var found: [(String, Arazzo.Selector)] = []
        func outputs(_ outputs: OrderedDictionary<String, Arazzo.OutputValue>, path: String) {
            for (key, value) in outputs {
                if case .selector(let selector) = value { found.append(("\(path)/\(escape(key))", selector)) }
            }
        }
        for (listPath, list, _) in parameterLists(in: document) {
            for (index, entry) in list.enumerated() {
                switch entry {
                case .inline(let parameter): found += selectors(in: parameter.value, path: "\(listPath)/\(index)/value")
                case .reusable(let reusable):
                    if let value = reusable.value { found += selectors(in: value, path: "\(listPath)/\(index)/value") }
                }
            }
        }
        for (key, parameter) in document.components.parameters {
            found += selectors(in: parameter.value, path: "/components/parameters/\(escape(key))/value")
        }
        for (wIndex, workflow) in document.workflows.enumerated() {
            outputs(workflow.outputs, path: "/workflows/\(wIndex)/outputs")
            for (sIndex, step) in workflow.steps.enumerated() {
                let sPath = "/workflows/\(wIndex)/steps/\(sIndex)"
                outputs(step.outputs, path: sPath + "/outputs")
                if let body = step.requestBody {
                    if let payload = body.payload {
                        found += selectorsInJSON(payload, path: sPath + "/requestBody/payload")
                    }
                    for (rIndex, replacement) in body.replacements.enumerated() {
                        let rPath = "\(sPath)/requestBody/replacements/\(rIndex)"
                        found += selectors(in: replacement.value, path: rPath + "/value")
                        if let type = replacement.targetSelectorType {
                            checkSelectorType(type, path: rPath + "/targetSelectorType", report: &report)
                            if !v11 {
                                report.warning(
                                    rPath + "/targetSelectorType", "targetSelectorType was introduced in Arazzo 1.1.")
                            }
                        }
                    }
                }
            }
        }
        for (path, selector) in found {
            checkSelector(selector, path: path, v11: v11, report: &report)
        }
    }

    // MARK: Names

    static let outputs = Arazzo.ValidationRule("output-names") { document, report in
        for (wIndex, workflow) in document.workflows.enumerated() {
            for key in workflow.outputs.keys where !ExpressionGrammar.isIdentifier(key) {
                report.error(
                    "/workflows/\(wIndex)/outputs/\(escape(key))", "Output name '\(key)' MUST match \(keyPattern).")
            }
            for (sIndex, step) in workflow.steps.enumerated() {
                for key in step.outputs.keys where !ExpressionGrammar.isIdentifier(key) {
                    report.error(
                        "/workflows/\(wIndex)/steps/\(sIndex)/outputs/\(escape(key))",
                        "Output name '\(key)' MUST match \(keyPattern).")
                }
            }
        }
    }

    static let components = Arazzo.ValidationRule("components") { document, report in
        let maps: [(String, [String])] = [
            ("inputs", document.components.inputs.keys),
            ("parameters", document.components.parameters.keys),
            ("successActions", document.components.successActions.keys),
            ("failureActions", document.components.failureActions.keys),
        ]
        for (field, keys) in maps {
            for key in keys where !ExpressionGrammar.isIdentifier(key) {
                report.error("/components/\(field)/\(escape(key))", "Component key '\(key)' MUST match \(keyPattern).")
            }
        }
    }

    // MARK: Runtime expressions

    static let runtimeExpressions = Arazzo.ValidationRule("runtime-expressions") { document, report in
        let usesStepDependsOn: (Arazzo.Workflow) -> Bool = { workflow in
            workflow.steps.contains { !$0.dependsOn.isEmpty }
        }

        func checkCommon(_ expression: Arazzo.RuntimeExpression, path: String, workflow: Arazzo.Workflow?) {
            if expression.usesNonStandardNotation {
                report.warning(
                    path,
                    "'\(expression.rawValue)' uses dotted-path notation; the ABNF form is '\(expression.canonicalString)'."
                )
            }
            switch expression.kind {
            case .invalid(let error):
                if !document.arazzo.supportsV1_1Features, Self.isValidArazzo10Expression(expression.rawValue) {
                    report.warning(
                        path,
                        "\(error) – accepted by Arazzo 1.0's looser grammar, but not by Arazzo 1.1 or by expression evaluation."
                    )
                } else {
                    report.error(path, "\(error)")
                }
            case .sourceDescriptions(let name, _):
                if document.sourceDescription(named: name) == nil {
                    report.error(path, "'\(expression.rawValue)' references unknown source description '\(name)'.")
                }
            case .components(let type, let name):
                let exists =
                    switch type {
                    case .parameters: document.components.parameters[name] != nil
                    case .successActions: document.components.successActions[name] != nil
                    case .failureActions: document.components.failureActions[name] != nil
                    }
                if !exists { report.error(path, "'\(expression.rawValue)' references a missing component.") }
            case .workflows(let workflowId, let field, let name, _):
                guard let target = document.workflow(id: workflowId) else {
                    report.error(path, "'\(expression.rawValue)' references unknown workflow '\(workflowId)'.")
                    break
                }
                if field == .outputs, !target.outputs.isEmpty, target.outputs[name] == nil {
                    report.warning(path, "Workflow '\(workflowId)' declares no output '\(name)'.")
                }
                if field == .inputs, let schema = try? document.resolvedInputs(for: target) {
                    checkInputName(name, schema: schema, path: path, expression: expression)
                }
            case .inputs(let name, _):
                if let workflow, let schema = try? document.resolvedInputs(for: workflow) {
                    checkInputName(name, schema: schema, path: path, expression: expression)
                } else if let workflow, workflow.inputs == nil {
                    report.warning(
                        path,
                        "'\(expression.rawValue)' is used but workflow '\(workflow.workflowId)' declares no inputs.")
                }
            case .self:
                if document.selfURI == nil {
                    report.warning(path, "'$self' is used but the document has no `$self` field.")
                }
            default:
                break
            }
        }

        func checkInputName(
            _ name: String, schema: Arazzo.JSONSchema, path: String, expression: Arazzo.RuntimeExpression
        ) {
            guard !schema.isComposite, !schema.properties.isEmpty else { return }
            let root = String(name.split(separator: ".").first ?? Substring(name))
            if schema.properties[name] == nil, schema.properties[root] == nil {
                report.warning(
                    path,
                    "'\(expression.rawValue)' references input '\(name)', which the inputs schema does not declare.")
            }
        }

        func checkStepReference(
            _ expression: Arazzo.RuntimeExpression, path: String, workflow: Arazzo.Workflow, fromIndex: Int?
        ) {
            guard case .steps(let stepId, let outputName, _) = expression.kind else { return }
            guard let index = workflow.steps.firstIndex(where: { $0.stepId == stepId }) else {
                report.error(
                    path,
                    "'\(expression.rawValue)' references unknown step '\(stepId)' in workflow '\(workflow.workflowId)'."
                )
                return
            }
            let target = workflow.steps[index]
            if !target.outputs.isEmpty || fromIndex != nil, target.outputs[outputName] == nil {
                report.warning(path, "Step '\(stepId)' declares no output '\(outputName)'.")
            }
            if let fromIndex, index > fromIndex, !usesStepDependsOn(workflow) {
                report.error(
                    path,
                    "'\(expression.rawValue)' is a forward reference: step '\(stepId)' runs after this step in sequential execution."
                )
            }
        }

        func checkStrings(in json: JSONValue, path: String) {
            switch json {
            case .string(let string):
                for invalid in Arazzo.ExpressionTemplate(string).invalidExpressions {
                    report.warning(
                        path, "Embedded expression '{\(invalid.text)}' is invalid: \(invalid.error.message).")
                }
            case .array(let values):
                for (index, value) in values.enumerated() { checkStrings(in: value, path: "\(path)/\(index)") }
            case .object(let object):
                for (key, value) in object { checkStrings(in: value, path: "\(path)/\(escape(key))") }
            default:
                break
            }
        }

        func checkValue(_ value: Arazzo.Value, path: String, workflow: Arazzo.Workflow, stepIndex: Int?) {
            if case .literal(.string(let string)) = value, string.hasPrefix("$"), !string.contains("{") {
                do {
                    _ = try Arazzo.RuntimeExpression(string)
                } catch let error as Arazzo.RuntimeExpression.ParseError {
                    report.warning(
                        path,
                        "'\(string)' looks like a runtime expression but is not one (\(error.message)); it will be sent literally."
                    )
                } catch {}
            }
            if case .literal(let json) = value { checkStrings(in: json, path: path) }
            for expression in value.runtimeExpressions {
                checkCommon(expression, path: path, workflow: workflow)
                checkStepReference(expression, path: path, workflow: workflow, fromIndex: stepIndex)
            }
        }

        for (wIndex, workflow) in document.workflows.enumerated() {
            let wPath = "/workflows/\(wIndex)"
            for (pIndex, entry) in workflow.parameters.enumerated() {
                if let parameter = try? document.components.resolve(entry) {
                    checkValue(
                        parameter.value, path: "\(wPath)/parameters/\(pIndex)/value", workflow: workflow, stepIndex: nil
                    )
                }
            }
            for (key, output) in workflow.outputs {
                let path = "\(wPath)/outputs/\(escape(key))"
                let expression = output.runtimeExpression
                checkCommon(expression, path: path, workflow: workflow)
                checkStepReference(expression, path: path, workflow: workflow, fromIndex: nil)
                if expression.isStepRuntimeOnly {
                    report.warning(
                        path,
                        "'\(expression.rawValue)' is only available while a step executes; workflow outputs usually reference $steps."
                    )
                }
            }
            let workflowActionCriteria: [(String, [Arazzo.Criterion])] =
                workflow.successActions.enumerated().compactMap { i, a in
                    a.inlineValue.map { ("\(wPath)/successActions/\(i)", $0.criteria) }
                }
                + workflow.failureActions.enumerated().compactMap { i, a in
                    a.inlineValue.map { ("\(wPath)/failureActions/\(i)", $0.criteria) }
                }
            for (aPath, criteria) in workflowActionCriteria {
                for (cIndex, criterion) in criteria.enumerated() {
                    for expression in criterion.runtimeExpressions {
                        let path = "\(aPath)/criteria/\(cIndex)"
                        checkCommon(expression, path: path, workflow: workflow)
                        checkStepReference(expression, path: path, workflow: workflow, fromIndex: nil)
                    }
                }
            }
            for (sIndex, step) in workflow.steps.enumerated() {
                let sPath = "\(wPath)/steps/\(sIndex)"
                for (pIndex, entry) in step.parameters.enumerated() {
                    if let parameter = try? document.components.resolve(entry) {
                        checkValue(
                            parameter.value, path: "\(sPath)/parameters/\(pIndex)/value", workflow: workflow,
                            stepIndex: sIndex)
                    }
                }
                if let body = step.requestBody {
                    if let payload = body.payload {
                        checkValue(
                            .literal(payload), path: sPath + "/requestBody/payload", workflow: workflow,
                            stepIndex: sIndex)
                    }
                    for (rIndex, replacement) in body.replacements.enumerated() {
                        checkValue(
                            replacement.value, path: "\(sPath)/requestBody/replacements/\(rIndex)/value",
                            workflow: workflow,
                            stepIndex: sIndex)
                    }
                }
                for (cIndex, criterion) in (step.successCriteria ?? []).enumerated() {
                    let path = "\(sPath)/successCriteria/\(cIndex)"
                    for expression in criterion.runtimeExpressions {
                        checkCommon(expression, path: path, workflow: workflow)
                        checkStepReference(expression, path: path, workflow: workflow, fromIndex: sIndex)
                    }
                }
                for (key, output) in step.outputs {
                    let path = "\(sPath)/outputs/\(escape(key))"
                    checkCommon(output.runtimeExpression, path: path, workflow: workflow)
                    checkStepReference(output.runtimeExpression, path: path, workflow: workflow, fromIndex: sIndex)
                }
                let actionCriteria: [(String, [Arazzo.Criterion])] =
                    step.onSuccess.enumerated().compactMap { i, a in
                        (try? document.components.resolve(a)).map { ("\(sPath)/onSuccess/\(i)", $0.criteria) }
                    }
                    + step.onFailure.enumerated().compactMap { i, a in
                        (try? document.components.resolve(a)).map { ("\(sPath)/onFailure/\(i)", $0.criteria) }
                    }
                for (aPath, criteria) in actionCriteria {
                    for (cIndex, criterion) in criteria.enumerated() {
                        for expression in criterion.runtimeExpressions {
                            let path = "\(aPath)/criteria/\(cIndex)"
                            checkCommon(expression, path: path, workflow: workflow)
                            checkStepReference(expression, path: path, workflow: workflow, fromIndex: sIndex)
                        }
                    }
                }
            }
        }
        let componentCriteria: [(String, [Arazzo.Criterion])] =
            document.components.successActions.map {
                ("/components/successActions/\(escape($0.key))", $0.value.criteria)
            }
            + document.components.failureActions.map {
                ("/components/failureActions/\(escape($0.key))", $0.value.criteria)
            }
        for (aPath, criteria) in componentCriteria {
            for (cIndex, criterion) in criteria.enumerated() {
                for expression in criterion.runtimeExpressions {
                    checkCommon(expression, path: "\(aPath)/criteria/\(cIndex)", workflow: nil)
                }
            }
        }
        for (key, parameter) in document.components.parameters {
            for expression in parameter.value.runtimeExpressions {
                checkCommon(expression, path: "/components/parameters/\(escape(key))/value", workflow: nil)
            }
        }
    }

    static let inputs = Arazzo.ValidationRule("inputs") { document, report in
        for (wIndex, workflow) in document.workflows.enumerated() {
            guard let schema = workflow.inputs, let ref = schema.ref, ref.hasPrefix("#/components/inputs/") else {
                continue
            }
            do {
                _ = try document.components.resolveInputs(schema)
            } catch {
                report.error("/workflows/\(wIndex)/inputs/$ref", "\(error)")
            }
        }
    }

    static let payloadReplacements = Arazzo.ValidationRule("payload-replacements") { document, report in
        for (wIndex, workflow) in document.workflows.enumerated() {
            for (sIndex, step) in workflow.steps.enumerated() {
                guard let body = step.requestBody else { continue }
                if !body.replacements.isEmpty, body.payload == nil {
                    report.warning(
                        "/workflows/\(wIndex)/steps/\(sIndex)/requestBody/replacements",
                        "Replacements are applied to the payload, but no payload is defined.")
                }
                for (rIndex, replacement) in body.replacements.enumerated() {
                    let path = "/workflows/\(wIndex)/steps/\(sIndex)/requestBody/replacements/\(rIndex)/target"
                    switch replacement.effectiveTargetKind(in: body) {
                    case .jsonPointer:
                        if (try? JSONPointer(replacement.target)) == nil {
                            report.error(path, "'\(replacement.target)' is not a valid JSON Pointer.")
                        }
                    case .jsonPath:
                        checkJSONPath(
                            replacement.target, version: replacement.targetSelectorType?.effectiveVersion ?? .rfc9535,
                            path: path, report: &report)
                    case .xPath:
                        break
                    }
                    if replacement.target.isEmpty, replacement.effectiveTargetKind(in: body) != .jsonPointer {
                        report.error(path, "target is REQUIRED and MUST NOT be empty.")
                    }
                }
            }
        }
    }

    // MARK: Helpers

    /// The Arazzo 1.0.x runtime expression ABNF, which allows any characters after most prefixes.
    static func isValidArazzo10Expression(_ text: String) -> Bool {
        if ["$url", "$method", "$statusCode"].contains(text) { return true }
        for prefix in ["$inputs.", "$outputs.", "$steps.", "$workflows.", "$sourceDescriptions.", "$components."]
        where text.hasPrefix(prefix) {
            return !text.contains("{") && !text.contains("}")
        }
        for prefix in ["$request.", "$response."] where text.hasPrefix(prefix) {
            let source = text.dropFirst(prefix.count)
            if source.hasPrefix("header.") {
                let token = source.dropFirst("header.".count)
                return !token.isEmpty && token.allSatisfy(ExpressionGrammar.isTokenCharacter)
            }
            if source.hasPrefix("query.") || source.hasPrefix("path.") { return true }
            if source == "body" { return true }
            if source.hasPrefix("body#") { return (try? JSONPointer(String(source.dropFirst(5)))) != nil }
        }
        return false
    }

    /// Reports JSONPath syntax errors. Expressions with embedded `{$...}` runtime expressions are only
    /// known at runtime and are skipped.
    static func checkJSONPath(
        _ expression: String, version: Arazzo.ExpressionType.Version, path: String,
        report: inout Arazzo.ValidationReporter
    ) {
        guard !Arazzo.ExpressionTemplate(expression).hasExpressions else { return }
        let dialect = Arazzo.BuiltInQueries.dialect(for: version)
        if let message = JSONPath.validate(expression, dialect: dialect) {
            report.error(
                path,
                "Invalid JSONPath (\(dialect == .rfc9535 ? "RFC 9535" : "Goessner/Jayway")) '\(expression)': \(message)"
            )
        }
    }

    static func checkArazzoSource(
        _ name: String, in document: Arazzo.Document, path: String, report: inout Arazzo.ValidationReporter
    ) {
        guard let source = document.sourceDescription(named: name) else {
            report.error(path, "References unknown source description '\(name)'.")
            return
        }
        if let type = source.type, type != .arazzo {
            report.error(
                path,
                "Source description '\(name)' is \(type.rawValue); workflows can only be referenced in arazzo sources.")
        }
    }

    /// Escapes a key for use as a JSON Pointer token.
    static func escape(_ key: String) -> String {
        key.replacingAll("~", with: "~0").replacingAll("/", with: "~1")
    }
}
