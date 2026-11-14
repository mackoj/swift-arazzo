/// A Step Object, appended to the workflow's `steps` in source order.
///
/// ```swift
/// Step("getPet", operationId: "getPetById") {
///     Parameter("petId", in: .path, value: "$inputs.petId")
///     SuccessCriterion("$statusCode == 200")
///     OnFailure.retry("retry", after: 2, limit: 3)
///     Output("name", "$response.body#/name")
/// }
/// .description("Fetch the pet")
/// ```
///
/// Each initialiser names one target, so a step always has exactly one. Scalar fields are modifiers; the body holds
/// the collections: ``Parameter``, ``RequestBody``, ``SuccessCriterion``, ``SuccessAction``, ``FailureAction`` and
/// ``Output``.
public struct Step: WorkflowComponent {
    /// The Step Object built so far.
    public var step: Arazzo.Step

    /// Creates a step that calls the operation `operationId`.
    public init(
        _ stepId: String, operationId: String, vendorExtensions: VendorExtensions = [:],
        @StepBuilder _ content: () -> [any StepComponent] = { [] }
    ) {
        self.init(stepId, target: .operationId(operationId), vendorExtensions: vendorExtensions, content)
    }

    /// Creates a step that calls the operation at `operationPath`, a JSON Pointer into a source description.
    public init(
        _ stepId: String, operationPath: String, vendorExtensions: VendorExtensions = [:],
        @StepBuilder _ content: () -> [any StepComponent] = { [] }
    ) {
        self.init(stepId, target: .operationPath(operationPath), vendorExtensions: vendorExtensions, content)
    }

    /// Creates a step that sends or receives on the AsyncAPI channel at `channelPath` (Arazzo 1.1).
    ///
    /// Set the step's `action` and `correlationId` with ``async(_:correlationId:)``.
    public init(
        _ stepId: String, channelPath: String, vendorExtensions: VendorExtensions = [:],
        @StepBuilder _ content: () -> [any StepComponent] = { [] }
    ) {
        self.init(stepId, target: .channelPath(channelPath), vendorExtensions: vendorExtensions, content)
    }

    /// Creates a step that runs the workflow `workflowId`.
    public init(
        _ stepId: String, workflowId: String, vendorExtensions: VendorExtensions = [:],
        @StepBuilder _ content: () -> [any StepComponent] = { [] }
    ) {
        self.init(stepId, target: .workflowId(workflowId), vendorExtensions: vendorExtensions, content)
    }

    private init(
        _ stepId: String, target: Arazzo.Step.Target, vendorExtensions: VendorExtensions,
        _ content: () -> [any StepComponent]
    ) {
        step = Arazzo.Step(stepId: stepId, target: target, vendorExtensions: vendorExtensions)
        for component in content() { component.apply(to: &step) }
    }

    /// Sets the `description`.
    public func description(_ description: String) -> Self {
        var copy = self
        copy.step.description = description
        return copy
    }

    /// Sets `timeout`, in milliseconds (Arazzo 1.1).
    public func timeout(_ milliseconds: Int) -> Self {
        var copy = self
        copy.step.timeout = milliseconds
        return copy
    }

    /// Sets `dependsOn`: the steps that must complete before this one runs (Arazzo 1.1).
    public func dependsOn(_ stepIds: [String]) -> Self {
        var copy = self
        copy.step.dependsOn = stepIds
        return copy
    }

    /// Sets `action` and `correlationId` for a ``init(_:channelPath:vendorExtensions:_:)`` step (Arazzo 1.1).
    public func async(_ action: Arazzo.Step.AsyncAction, correlationId: String? = nil) -> Self {
        var copy = self
        copy.step.action = action
        copy.step.correlationId = correlationId
        return copy
    }

    public func apply(to workflow: inout Arazzo.Workflow) {
        workflow.steps.append(step)
    }
}

/// A Parameter Object or a reference to one, in a ``Workflow``, a ``Step`` or ``Components``.
///
/// In a workflow or a step it is appended to `parameters` in source order. In ``Components`` it defines
/// `components.parameters.<name>`; a ``reference(_:value:)`` there is not a definition and is ignored.
public struct Parameter: WorkflowComponent, StepComponent, ReusableComponent {
    /// The parameter, inline or as a reference to `$components.parameters`.
    public var parameter: Arazzo.ReusableOr<Arazzo.Parameter>

    /// Creates an inline parameter, such as `Parameter("petId", in: .path, value: "$inputs.petId")`.
    ///
    /// - Parameters:
    ///   - name: The `name`.
    ///   - location: The `in` field; required when the step targets an operation.
    ///   - value: A runtime expression, a Selector Object or a literal.
    ///   - vendorExtensions: `x-` fields of the object.
    public init(
        _ name: String, in location: Arazzo.Parameter.Location? = nil, value: Arazzo.Value,
        vendorExtensions: VendorExtensions = [:]
    ) {
        parameter = .inline(
            Arazzo.Parameter(name: name, in: location, value: value, vendorExtensions: vendorExtensions))
    }

    /// A Reusable Object pointing at `$components.parameters.<name>`, with an optional `value` override.
    public static func reference(_ name: String, value: Arazzo.Value? = nil) -> Parameter {
        Parameter(parameter: .reusable(Arazzo.Reusable(.parameters, name, value: value)))
    }

    private init(parameter: Arazzo.ReusableOr<Arazzo.Parameter>) {
        self.parameter = parameter
    }

    public func apply(to workflow: inout Arazzo.Workflow) {
        workflow.parameters.append(parameter)
    }

    public func apply(to step: inout Arazzo.Step) {
        step.parameters.append(parameter)
    }

    public func apply(to components: inout Arazzo.Components) {
        guard let parameter = parameter.inlineValue else { return }
        components.parameters[parameter.name] = parameter
    }
}

/// The Request Body Object of a ``Step``. With several, the last one wins.
public struct RequestBody: StepComponent {
    /// The Request Body Object this part sets.
    public var requestBody: Arazzo.RequestBody

    /// Creates a Request Body Object; the parameters are its fields.
    public init(
        contentType: String? = nil, payload: JSONValue? = nil, replacements: [Arazzo.PayloadReplacement] = [],
        vendorExtensions: VendorExtensions = [:]
    ) {
        requestBody = Arazzo.RequestBody(
            contentType: contentType, payload: payload, replacements: replacements,
            vendorExtensions: vendorExtensions)
    }

    public func apply(to step: inout Arazzo.Step) {
        step.requestBody = requestBody
    }
}

/// A Criterion Object, appended to the step's `successCriteria` in source order.
///
/// A step whose body has no `SuccessCriterion` has no `successCriteria` field at all (`nil`), as the specification
/// distinguishes an omitted list from a present one.
public struct SuccessCriterion: StepComponent {
    /// The Criterion Object this part adds.
    public var criterion: Arazzo.Criterion

    /// Creates a criterion, such as `SuccessCriterion("$statusCode == 200")` for a simple condition.
    ///
    /// - Parameters:
    ///   - condition: The `condition`.
    ///   - context: The `context`; required when `type` is set.
    ///   - type: The `type`; `nil` means a simple condition.
    ///   - vendorExtensions: `x-` fields of the object.
    public init(
        _ condition: String, context: Arazzo.RuntimeExpression? = nil, type: Arazzo.Criterion.ConditionType? = nil,
        vendorExtensions: VendorExtensions = [:]
    ) {
        criterion = Arazzo.Criterion(
            context: context, condition: condition, type: type, vendorExtensions: vendorExtensions)
    }

    public func apply(to step: inout Arazzo.Step) {
        step.successCriteria = (step.successCriteria ?? []) + [criterion]
    }
}
