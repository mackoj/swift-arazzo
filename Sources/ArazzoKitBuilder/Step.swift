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
///
/// Where `Step` names a type of your own, write the same step with the model type's initialiser:
///
/// ```swift
/// Arazzo.Step("getPet", target: .operationId("getPetById"), description: "Fetch the pet") { ... }
/// ```
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
        step = Arazzo.Step(stepId, target: target, vendorExtensions: vendorExtensions, content)
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

    /// The `$steps.<stepId>.outputs.<name>` expression that reads this step's output `name`.
    ///
    /// It follows a renamed step, but cannot check that the step declares `name`: `validate()` warns about that.
    public func output(_ name: String) -> Arazzo.RuntimeExpression {
        step.output(name)
    }

    public func apply(to workflow: inout Arazzo.Workflow) {
        workflow.steps.append(step)
    }
}

extension Arazzo.Step: WorkflowComponent {
    /// Builds a Step Object from the parts in `content`: ``ArazzoKitBuilder/Parameter``,
    /// ``ArazzoKitBuilder/RequestBody``, ``ArazzoKitBuilder/SuccessCriterion``, ``ArazzoKitBuilder/SuccessAction``,
    /// ``ArazzoKitBuilder/FailureAction`` and ``ArazzoKitBuilder/Output``, or the model values they stand for.
    ///
    /// ```swift
    /// Arazzo.Step("getPet", target: .operationId("getPetById"), description: "Fetch the pet") {
    ///     Parameter("petId", in: .path, value: "$inputs.petId")
    ///     SuccessCriterion("$statusCode == 200")
    /// }
    /// ```
    ///
    /// It is the same step as ``ArazzoKitBuilder/Step``, under a name that cannot clash with a `Step` of your own,
    /// and it is the model value itself, so no unwrapping is needed outside a builder. The scalar fields are its
    /// parameters.
    ///
    /// - Parameters:
    ///   - stepId: The `stepId`.
    ///   - target: The operation, channel or workflow the step invokes.
    ///   - description: The `description`.
    ///   - timeout: `timeout`, in milliseconds (Arazzo 1.1).
    ///   - correlationId: `correlationId` of an AsyncAPI step (Arazzo 1.1).
    ///   - action: `action` of an AsyncAPI step (Arazzo 1.1).
    ///   - dependsOn: The steps that must complete before this one (Arazzo 1.1).
    ///   - vendorExtensions: `x-` fields of the object.
    ///   - content: The step's parts, applied in source order.
    public init(
        _ stepId: String, target: Target, description: String? = nil, timeout: Int? = nil,
        correlationId: String? = nil, action: AsyncAction? = nil, dependsOn: [String] = [],
        vendorExtensions: VendorExtensions = [:], @StepBuilder _ content: () -> [any StepComponent] = { [] }
    ) {
        self.init(
            stepId: stepId, description: description, target: target, timeout: timeout,
            correlationId: correlationId, action: action, dependsOn: dependsOn, vendorExtensions: vendorExtensions)
        for component in content() { component.apply(to: &self) }
    }

    /// The `$steps.<stepId>.outputs.<name>` expression that reads this step's output `name`.
    ///
    /// It follows a renamed step, but cannot check that the step declares `name`: `validate()` warns about that.
    public func output(_ name: String) -> Arazzo.RuntimeExpression {
        Arazzo.RuntimeExpression(.steps(stepId: stepId, outputName: name, pointer: nil))
    }

    /// Appends this step to the workflow's `steps`.
    public func apply(to workflow: inout Arazzo.Workflow) {
        workflow.steps.append(self)
    }
}

/// A Parameter Object or a reference to one, in a ``Workflow``, a ``Step`` or ``Components``.
///
/// In a workflow or a step it is appended to `parameters` in source order. In ``Components`` it defines
/// `components.parameters.<name>`; a ``reference(_:value:)`` there is not a definition and is ignored.
public struct Parameter: WorkflowComponent, StepComponent, ReusableComponent {
    /// The parameter, inline or as a reference to `$components.parameters`.
    public var parameter: Arazzo.ReusableOr<Arazzo.Parameter>
    var componentKey: String?

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

    /// Creates an inline parameter whose value is a runtime expression, such as one from ``Input/expression`` or
    /// ``Step/output(_:)``.
    public init(
        _ name: String, in location: Arazzo.Parameter.Location? = nil, value: Arazzo.RuntimeExpression,
        vendorExtensions: VendorExtensions = [:]
    ) {
        self.init(name, in: location, value: .expression(value), vendorExtensions: vendorExtensions)
    }

    /// Sets the key of this parameter in ``Components``, which defaults to its `name`.
    ///
    /// The key is what a reference names: `Parameter("X-Trace-Id", in: .header, value: "t").componentKey("traceId")`
    /// is referenced as `Parameter.reference("traceId")`. Outside ``Components`` it has no effect.
    public func componentKey(_ key: String) -> Self {
        var copy = self
        copy.componentKey = key
        return copy
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
        components.parameters[componentKey ?? parameter.name] = parameter
    }
}

extension Arazzo.Parameter: WorkflowComponent, StepComponent, ReusableComponent {
    /// Appends this parameter to the workflow's `parameters`.
    public func apply(to workflow: inout Arazzo.Workflow) {
        workflow.parameters.append(.inline(self))
    }

    /// Appends this parameter to the step's `parameters`.
    public func apply(to step: inout Arazzo.Step) {
        step.parameters.append(.inline(self))
    }

    /// Defines `components.parameters.<name>`. Use ``ArazzoKitBuilder/Parameter/componentKey(_:)`` for a key other than
    /// the name.
    public func apply(to components: inout Arazzo.Components) {
        components.parameters[name] = self
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

extension Arazzo.RequestBody: StepComponent {
    /// Sets the step's `requestBody`. With several, the last one wins.
    public func apply(to step: inout Arazzo.Step) {
        step.requestBody = self
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

extension Arazzo.Criterion: StepComponent {
    /// Appends this criterion to the step's `successCriteria`, as ``ArazzoKitBuilder/SuccessCriterion`` does.
    public func apply(to step: inout Arazzo.Step) {
        step.successCriteria = (step.successCriteria ?? []) + [self]
    }
}
