/// A Workflow Object, appended to the document's `workflows` in source order.
///
/// ```swift
/// Workflow("adopt", summary: "Adopt a pet") {
///     Input("petId", schema: ["type": "integer"], required: true)
///     Step("getPet", operationId: "getPetById") { ... }
///     Output("adoptedName", "$steps.getPet.outputs.name")
/// }
/// ```
///
/// Scalar fields are initialiser parameters or modifiers; the body holds the collections: ``Input``, ``Step``,
/// ``Parameter``, ``SuccessAction``, ``FailureAction`` and ``Output``.
public struct Workflow: DocumentComponent {
    /// The Workflow Object built so far.
    public var workflow: Arazzo.Workflow

    /// Creates a Workflow Object from the parts in `content`.
    ///
    /// - Parameters:
    ///   - workflowId: The `workflowId`.
    ///   - summary: The `summary`.
    ///   - description: The `description`.
    ///   - vendorExtensions: `x-` fields of the object.
    ///   - content: The workflow's parts, applied in source order.
    public init(
        _ workflowId: String, summary: String? = nil, description: String? = nil,
        vendorExtensions: VendorExtensions = [:], @WorkflowBuilder _ content: () -> [any WorkflowComponent]
    ) {
        workflow = Arazzo.Workflow(
            workflowId: workflowId, summary: summary, description: description, steps: [],
            vendorExtensions: vendorExtensions)
        for component in content() { component.apply(to: &workflow) }
    }

    /// Sets the `inputs` schema, such as `.reference("#/components/inputs/pagination")`.
    ///
    /// It replaces the schema that ``Input``s in the body built.
    public func inputs(_ schema: Arazzo.JSONSchema) -> Self {
        var copy = self
        copy.workflow.inputs = schema
        return copy
    }

    /// Sets `dependsOn`: the workflows that must complete before this one runs.
    public func dependsOn(_ workflowIds: [String]) -> Self {
        var copy = self
        copy.workflow.dependsOn = workflowIds
        return copy
    }

    public func apply(to document: inout Arazzo.Document) {
        document.workflows.append(workflow)
    }
}

/// A workflow input, or a reusable input schema in ``Components``.
///
/// In a ``Workflow``, it adds the property `name` to the `inputs` object schema, and to its `required` list when
/// `required` is `true`, so these two build the same schema:
///
/// ```swift
/// Input("petId", schema: ["type": "integer"], required: true)
/// // inputs: .object(properties: ["petId": ["type": "integer"]], required: ["petId"])
/// ```
///
/// In ``Components``, it defines `components.inputs.<name>` as `schema`, and `required` has no effect.
public struct Input: WorkflowComponent, ReusableComponent {
    /// The property or component name.
    public var name: String
    /// The property's schema.
    public var schema: Arazzo.JSONSchema
    /// Whether the property is listed in the workflow schema's `required` keyword.
    public var isRequired: Bool

    /// Creates an input named `name`.
    public init(_ name: String, schema: Arazzo.JSONSchema, required: Bool = false) {
        self.name = name
        self.schema = schema
        self.isRequired = required
    }

    public func apply(to workflow: inout Arazzo.Workflow) {
        var object = workflow.inputs?.value.objectValue ?? ["type": "object"]
        var properties = object["properties"]?.objectValue ?? [:]
        properties[name] = schema.value
        object["properties"] = .object(properties)
        if isRequired {
            var required = object["required"]?.arrayValue ?? []
            if !required.contains(.string(name)) { required.append(.string(name)) }
            object["required"] = .array(required)
        }
        workflow.inputs = Arazzo.JSONSchema(.object(object))
    }

    public func apply(to components: inout Arazzo.Components) {
        components.inputs[name] = schema
    }
}

/// An output of a ``Workflow`` or a ``Step``, kept in source order.
///
/// Two outputs with the same name in one workflow or step leave only the last one's value.
public struct Output: WorkflowComponent, StepComponent {
    /// The output name.
    public var name: String
    /// The runtime expression or Selector Object that gives the output's value.
    public var value: Arazzo.OutputValue

    /// Creates the output `name`, such as `Output("name", "$response.body#/name")`.
    public init(_ name: String, _ value: Arazzo.OutputValue) {
        self.name = name
        self.value = value
    }

    public func apply(to workflow: inout Arazzo.Workflow) {
        workflow.outputs[name] = value
    }

    public func apply(to step: inout Arazzo.Step) {
        step.outputs[name] = value
    }
}
