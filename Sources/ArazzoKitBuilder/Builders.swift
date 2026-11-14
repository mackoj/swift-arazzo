@_exported import ArazzoKit

/// A part of an Arazzo Description that a ``DocumentBuilder`` body can hold: ``Info``, ``Source``, ``Workflow`` or
/// ``Components``.
///
/// Conform your own type to add a document-level part the builder does not cover.
public protocol DocumentComponent: Sendable {
    /// Adds this part to `document`. Parts apply in source order, so a later one can overwrite an earlier one.
    func apply(to document: inout Arazzo.Document)
}

/// A part of a Workflow Object that a ``WorkflowBuilder`` body can hold: ``Input``, ``Step``, ``Parameter``,
/// ``SuccessAction``, ``FailureAction`` or ``Output``.
public protocol WorkflowComponent: Sendable {
    /// Adds this part to `workflow`. Parts apply in source order, so a later one can overwrite an earlier one.
    func apply(to workflow: inout Arazzo.Workflow)
}

/// A part of a Step Object that a ``StepBuilder`` body can hold: ``Parameter``, ``RequestBody``,
/// ``SuccessCriterion``, ``SuccessAction``, ``FailureAction`` or ``Output``.
public protocol StepComponent: Sendable {
    /// Adds this part to `step`. Parts apply in source order, so a later one can overwrite an earlier one.
    func apply(to step: inout Arazzo.Step)
}

/// A definition that a ``ComponentsBuilder`` body can hold: ``Input``, ``Parameter``, ``SuccessAction`` or
/// ``FailureAction``, each keyed by its name in the Components Object.
public protocol ReusableComponent: Sendable {
    /// Adds this definition to `components`. A later definition with the same name replaces an earlier one.
    func apply(to components: inout Arazzo.Components)
}

/// Collects the body of `Arazzo.Document.init(arazzo:selfURI:vendorExtensions:_:)`.
///
/// Supports `if`, `else`, `switch`, `for` and `if #available`, and an expression of type `[any DocumentComponent]`
/// to splice in parts returned by a helper.
@resultBuilder
public enum DocumentBuilder {
    /// Wraps one part of the body.
    public static func buildExpression(_ component: some DocumentComponent) -> [any DocumentComponent] {
        [component]
    }
    /// Wraps one part of the body.
    public static func buildExpression(_ components: [any DocumentComponent]) -> [any DocumentComponent] {
        components
    }
    /// Joins the parts of a block in source order.
    public static func buildBlock(_ parts: [any DocumentComponent]...) -> [any DocumentComponent] {
        parts.flatMap { $0 }
    }
    /// An `if` without `else`: its parts, or none.
    public static func buildOptional(_ part: [any DocumentComponent]?) -> [any DocumentComponent] { part ?? [] }
    /// The first branch of an `if`/`else` or `switch`.
    public static func buildEither(first part: [any DocumentComponent]) -> [any DocumentComponent] { part }
    /// The second branch of an `if`/`else` or `switch`.
    public static func buildEither(second part: [any DocumentComponent]) -> [any DocumentComponent] { part }
    /// The parts of every iteration of a `for` loop, in order.
    public static func buildArray(_ parts: [[any DocumentComponent]]) -> [any DocumentComponent] {
        parts.flatMap { $0 }
    }
    /// An `if #available` branch.
    public static func buildLimitedAvailability(_ part: [any DocumentComponent]) -> [any DocumentComponent] {
        part
    }
}

/// Collects the body of a ``Workflow``.
///
/// Supports `if`, `else`, `switch`, `for` and `if #available`, and an expression of type `[any WorkflowComponent]`
/// to splice in parts returned by a helper.
@resultBuilder
public enum WorkflowBuilder {
    /// Wraps one part of the body.
    public static func buildExpression(_ component: some WorkflowComponent) -> [any WorkflowComponent] {
        [component]
    }
    /// Wraps one part of the body.
    public static func buildExpression(_ components: [any WorkflowComponent]) -> [any WorkflowComponent] {
        components
    }
    /// Joins the parts of a block in source order.
    public static func buildBlock(_ parts: [any WorkflowComponent]...) -> [any WorkflowComponent] {
        parts.flatMap { $0 }
    }
    /// An `if` without `else`: its parts, or none.
    public static func buildOptional(_ part: [any WorkflowComponent]?) -> [any WorkflowComponent] { part ?? [] }
    /// The first branch of an `if`/`else` or `switch`.
    public static func buildEither(first part: [any WorkflowComponent]) -> [any WorkflowComponent] { part }
    /// The second branch of an `if`/`else` or `switch`.
    public static func buildEither(second part: [any WorkflowComponent]) -> [any WorkflowComponent] { part }
    /// The parts of every iteration of a `for` loop, in order.
    public static func buildArray(_ parts: [[any WorkflowComponent]]) -> [any WorkflowComponent] {
        parts.flatMap { $0 }
    }
    /// An `if #available` branch.
    public static func buildLimitedAvailability(_ part: [any WorkflowComponent]) -> [any WorkflowComponent] {
        part
    }
}

/// Collects the body of a ``Step``.
///
/// Supports `if`, `else`, `switch`, `for` and `if #available`, and an expression of type `[any StepComponent]` to
/// splice in parts returned by a helper.
@resultBuilder
public enum StepBuilder {
    /// Wraps one part of the body.
    public static func buildExpression(_ component: some StepComponent) -> [any StepComponent] { [component] }
    /// Wraps one part of the body.
    public static func buildExpression(_ components: [any StepComponent]) -> [any StepComponent] { components }
    /// Joins the parts of a block in source order.
    public static func buildBlock(_ parts: [any StepComponent]...) -> [any StepComponent] { parts.flatMap { $0 } }
    /// An `if` without `else`: its parts, or none.
    public static func buildOptional(_ part: [any StepComponent]?) -> [any StepComponent] { part ?? [] }
    /// The first branch of an `if`/`else` or `switch`.
    public static func buildEither(first part: [any StepComponent]) -> [any StepComponent] { part }
    /// The second branch of an `if`/`else` or `switch`.
    public static func buildEither(second part: [any StepComponent]) -> [any StepComponent] { part }
    /// The parts of every iteration of a `for` loop, in order.
    public static func buildArray(_ parts: [[any StepComponent]]) -> [any StepComponent] { parts.flatMap { $0 } }
    /// An `if #available` branch.
    public static func buildLimitedAvailability(_ part: [any StepComponent]) -> [any StepComponent] { part }
}

/// Collects the body of ``Components``.
///
/// Supports `if`, `else`, `switch`, `for` and `if #available`, and an expression of type `[any ReusableComponent]`
/// to splice in definitions returned by a helper.
@resultBuilder
public enum ComponentsBuilder {
    /// Wraps one part of the body.
    public static func buildExpression(_ component: some ReusableComponent) -> [any ReusableComponent] {
        [component]
    }
    /// Wraps one part of the body.
    public static func buildExpression(_ components: [any ReusableComponent]) -> [any ReusableComponent] {
        components
    }
    /// Joins the parts of a block in source order.
    public static func buildBlock(_ parts: [any ReusableComponent]...) -> [any ReusableComponent] {
        parts.flatMap { $0 }
    }
    /// An `if` without `else`: its parts, or none.
    public static func buildOptional(_ part: [any ReusableComponent]?) -> [any ReusableComponent] { part ?? [] }
    /// The first branch of an `if`/`else` or `switch`.
    public static func buildEither(first part: [any ReusableComponent]) -> [any ReusableComponent] { part }
    /// The second branch of an `if`/`else` or `switch`.
    public static func buildEither(second part: [any ReusableComponent]) -> [any ReusableComponent] { part }
    /// The parts of every iteration of a `for` loop, in order.
    public static func buildArray(_ parts: [[any ReusableComponent]]) -> [any ReusableComponent] {
        parts.flatMap { $0 }
    }
    /// An `if #available` branch.
    public static func buildLimitedAvailability(_ part: [any ReusableComponent]) -> [any ReusableComponent] {
        part
    }
}
