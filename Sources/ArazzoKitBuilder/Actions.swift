/// A Success Action Object or a reference to one, in a ``Workflow``, a ``Step`` or ``Components``.
///
/// In a step it is appended to `onSuccess`, in a workflow to `successActions`, in source order. In ``Components``
/// it defines `components.successActions.<name>`; a ``reference(_:)`` there is not a definition and is ignored.
public struct SuccessAction: WorkflowComponent, StepComponent, ReusableComponent {
    /// The action, inline or as a reference to `$components.successActions`.
    public var action: Arazzo.ReusableOr<Arazzo.SuccessAction>
    var componentKey: String?

    private init(_ action: Arazzo.ReusableOr<Arazzo.SuccessAction>) {
        self.action = action
    }

    /// An `end` action: the workflow ends after this step.
    ///
    /// - Parameters:
    ///   - name: The action's `name`.
    ///   - criteria: The `criteria` that must all hold for the action to apply.
    ///   - vendorExtensions: `x-` fields of the object.
    public static func end(
        _ name: String, criteria: [Arazzo.Criterion] = [], vendorExtensions: VendorExtensions = [:]
    ) -> SuccessAction {
        SuccessAction(
            .inline(
                Arazzo.SuccessAction(name: name, kind: .end, criteria: criteria, vendorExtensions: vendorExtensions))
        )
    }

    /// A `goto` action to `target`, a step (`.step("id")`) or a workflow (`.workflow("id")`).
    ///
    /// - Parameters:
    ///   - name: The action's `name`.
    ///   - target: The step or workflow to go to.
    ///   - parameters: Parameters for a target workflow.
    ///   - criteria: The `criteria` that must all hold for the action to apply.
    ///   - vendorExtensions: `x-` fields of the object.
    public static func goto(
        _ name: String, _ target: Arazzo.ActionTarget, parameters: [Parameter] = [], criteria: [Arazzo.Criterion] = [],
        vendorExtensions: VendorExtensions = [:]
    ) -> SuccessAction {
        SuccessAction(
            .inline(
                Arazzo.SuccessAction(
                    name: name, kind: .goto(target), parameters: parameters.map(\.parameter), criteria: criteria,
                    vendorExtensions: vendorExtensions)))
    }

    /// Sets the key of this action in ``Components``, which defaults to its `name`.
    ///
    /// The key is what ``reference(_:)`` names. Outside ``Components`` it has no effect.
    public func componentKey(_ key: String) -> Self {
        var copy = self
        copy.componentKey = key
        return copy
    }

    /// A Reusable Object pointing at `$components.successActions.<name>`.
    public static func reference(_ name: String) -> SuccessAction {
        SuccessAction(.reusable(Arazzo.Reusable(.successActions, name)))
    }

    public func apply(to workflow: inout Arazzo.Workflow) {
        workflow.successActions.append(action)
    }

    public func apply(to step: inout Arazzo.Step) {
        step.onSuccess.append(action)
    }

    public func apply(to components: inout Arazzo.Components) {
        guard let action = action.inlineValue else { return }
        components.successActions[componentKey ?? action.name] = action
    }
}

extension Arazzo.SuccessAction: WorkflowComponent, StepComponent, ReusableComponent {
    /// Appends this action to the workflow's `successActions`.
    public func apply(to workflow: inout Arazzo.Workflow) {
        workflow.successActions.append(.inline(self))
    }

    /// Appends this action to the step's `onSuccess`.
    public func apply(to step: inout Arazzo.Step) {
        step.onSuccess.append(.inline(self))
    }

    /// Defines `components.successActions.<name>`. Use ``ArazzoKitBuilder/SuccessAction/componentKey(_:)`` for a key
    /// other than the name.
    public func apply(to components: inout Arazzo.Components) {
        components.successActions[name] = self
    }
}

/// A Failure Action Object or a reference to one, in a ``Workflow``, a ``Step`` or ``Components``.
///
/// In a step it is appended to `onFailure`, in a workflow to `failureActions`, in source order. In ``Components``
/// it defines `components.failureActions.<name>`; a ``reference(_:)`` there is not a definition and is ignored.
public struct FailureAction: WorkflowComponent, StepComponent, ReusableComponent {
    /// The action, inline or as a reference to `$components.failureActions`.
    public var action: Arazzo.ReusableOr<Arazzo.FailureAction>
    var componentKey: String?

    private init(_ action: Arazzo.ReusableOr<Arazzo.FailureAction>) {
        self.action = action
    }

    /// An `end` action: the workflow ends after this step.
    ///
    /// - Parameters:
    ///   - name: The action's `name`.
    ///   - criteria: The `criteria` that must all hold for the action to apply.
    ///   - vendorExtensions: `x-` fields of the object.
    public static func end(
        _ name: String, criteria: [Arazzo.Criterion] = [], vendorExtensions: VendorExtensions = [:]
    ) -> FailureAction {
        FailureAction(
            .inline(
                Arazzo.FailureAction(name: name, kind: .end, criteria: criteria, vendorExtensions: vendorExtensions))
        )
    }

    /// A `retry` action: run the step again, or `target` first, up to `limit` times.
    ///
    /// - Parameters:
    ///   - name: The action's `name`.
    ///   - after: `retryAfter`, in seconds.
    ///   - limit: `retryLimit`; the specification's default is 1.
    ///   - target: A step or workflow to run before retrying.
    ///   - parameters: Parameters for a target workflow.
    ///   - criteria: The `criteria` that must all hold for the action to apply.
    ///   - vendorExtensions: `x-` fields of the object.
    public static func retry(
        _ name: String, after: Double? = nil, limit: Int? = nil, target: Arazzo.ActionTarget? = nil,
        parameters: [Parameter] = [], criteria: [Arazzo.Criterion] = [], vendorExtensions: VendorExtensions = [:]
    ) -> FailureAction {
        let retry = Arazzo.FailureAction.Retry(retryAfter: after, retryLimit: limit, target: target)
        return FailureAction(
            .inline(
                Arazzo.FailureAction(
                    name: name, kind: .retry(retry), parameters: parameters.map(\.parameter), criteria: criteria,
                    vendorExtensions: vendorExtensions)))
    }

    /// A `goto` action to `target`, a step (`.step("id")`) or a workflow (`.workflow("id")`).
    ///
    /// - Parameters:
    ///   - name: The action's `name`.
    ///   - target: The step or workflow to go to.
    ///   - parameters: Parameters for a target workflow.
    ///   - criteria: The `criteria` that must all hold for the action to apply.
    ///   - vendorExtensions: `x-` fields of the object.
    public static func goto(
        _ name: String, _ target: Arazzo.ActionTarget, parameters: [Parameter] = [], criteria: [Arazzo.Criterion] = [],
        vendorExtensions: VendorExtensions = [:]
    ) -> FailureAction {
        FailureAction(
            .inline(
                Arazzo.FailureAction(
                    name: name, kind: .goto(target), parameters: parameters.map(\.parameter), criteria: criteria,
                    vendorExtensions: vendorExtensions)))
    }

    /// Sets the key of this action in ``Components``, which defaults to its `name`.
    ///
    /// The key is what ``reference(_:)`` names. Outside ``Components`` it has no effect.
    public func componentKey(_ key: String) -> Self {
        var copy = self
        copy.componentKey = key
        return copy
    }

    /// A Reusable Object pointing at `$components.failureActions.<name>`.
    public static func reference(_ name: String) -> FailureAction {
        FailureAction(.reusable(Arazzo.Reusable(.failureActions, name)))
    }

    public func apply(to workflow: inout Arazzo.Workflow) {
        workflow.failureActions.append(action)
    }

    public func apply(to step: inout Arazzo.Step) {
        step.onFailure.append(action)
    }

    public func apply(to components: inout Arazzo.Components) {
        guard let action = action.inlineValue else { return }
        components.failureActions[componentKey ?? action.name] = action
    }
}

extension Arazzo.FailureAction: WorkflowComponent, StepComponent, ReusableComponent {
    /// Appends this action to the workflow's `failureActions`.
    public func apply(to workflow: inout Arazzo.Workflow) {
        workflow.failureActions.append(.inline(self))
    }

    /// Appends this action to the step's `onFailure`.
    public func apply(to step: inout Arazzo.Step) {
        step.onFailure.append(.inline(self))
    }

    /// Defines `components.failureActions.<name>`. Use ``ArazzoKitBuilder/FailureAction/componentKey(_:)`` for a key
    /// other than the name.
    public func apply(to components: inout Arazzo.Components) {
        components.failureActions[name] = self
    }
}

/// ``SuccessAction`` under the name of the Step Object field it fills: `OnSuccess.end("done")`.
public typealias OnSuccess = SuccessAction

/// ``FailureAction`` under the name of the Step Object field it fills: `OnFailure.retry("retry", after: 2)`.
public typealias OnFailure = FailureAction
