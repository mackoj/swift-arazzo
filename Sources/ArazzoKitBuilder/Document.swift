extension Arazzo.Document {
    /// Builds an Arazzo Description from ``ArazzoKitBuilder/Info``, ``ArazzoKitBuilder/Source``,
    /// ``ArazzoKitBuilder/Workflow`` and ``ArazzoKitBuilder/Components`` in the body.
    ///
    /// ```swift
    /// let document = Arazzo.Document {
    ///     Info(title: "Pets", version: "1.0.0")
    ///     Source("petstore", url: "https://example.com/openapi.yaml", type: .openapi)
    ///     Workflow("adopt") { ... }
    /// }
    /// ```
    ///
    /// The result is a plain value: encode it with `jsonData()` or `yamlString()` and check it with `validate()`. The
    /// builder itself checks nothing, so a body without ``ArazzoKitBuilder/Info`` leaves an empty title and version,
    /// and a missing source description or workflow is reported by `validate()` like in a decoded document.
    ///
    /// - Parameters:
    ///   - arazzo: The `arazzo` field; defaults to the latest version these models describe.
    ///   - selfURI: The `$self` field (Arazzo 1.1).
    ///   - vendorExtensions: `x-` fields of the Arazzo Specification Object.
    ///   - content: The document's parts, applied in source order.
    public init(
        arazzo: Arazzo.SpecificationVersion = .latest,
        selfURI: String? = nil,
        vendorExtensions: VendorExtensions = [:],
        @DocumentBuilder _ content: () -> [any DocumentComponent]
    ) {
        self.init(
            arazzo: arazzo, selfURI: selfURI, info: Arazzo.Info(title: "", version: ""), sourceDescriptions: [],
            workflows: [], vendorExtensions: vendorExtensions)
        for component in content() { component.apply(to: &self) }
    }
}

/// The Info Object of a document built with `Arazzo.Document.init(arazzo:selfURI:vendorExtensions:_:)`.
///
/// With several, the last one wins.
public struct Info: DocumentComponent {
    /// The Info Object this part sets.
    public var info: Arazzo.Info

    /// Creates the Info Object; the parameters are its fields.
    public init(
        title: String, summary: String? = nil, description: String? = nil, version: String,
        vendorExtensions: VendorExtensions = [:]
    ) {
        info = Arazzo.Info(
            title: title, summary: summary, description: description, version: version,
            vendorExtensions: vendorExtensions)
    }

    public func apply(to document: inout Arazzo.Document) {
        document.info = info
    }
}

extension Arazzo.Info: DocumentComponent {
    /// Sets the document's `info`. With several, the last one wins.
    public func apply(to document: inout Arazzo.Document) {
        document.info = self
    }
}

/// A Source Description Object, appended to the document's `sourceDescriptions` in source order.
public struct Source: DocumentComponent {
    /// The Source Description Object this part adds.
    public var sourceDescription: Arazzo.SourceDescription

    /// Creates a Source Description Object.
    ///
    /// - Parameters:
    ///   - name: The `name` that steps use in `operationId` qualifiers and `$sourceDescriptions` expressions.
    ///   - url: The `url` of the OpenAPI, AsyncAPI or Arazzo document.
    ///   - type: The `type` of the document.
    ///   - vendorExtensions: `x-` fields of the object.
    public init(
        _ name: String, url: String, type: Arazzo.SourceDescription.SourceType? = nil,
        vendorExtensions: VendorExtensions = [:]
    ) {
        sourceDescription = Arazzo.SourceDescription(
            name: name, url: url, type: type, vendorExtensions: vendorExtensions)
    }

    public func apply(to document: inout Arazzo.Document) {
        document.sourceDescriptions.append(sourceDescription)
    }
}

extension Arazzo.SourceDescription: DocumentComponent {
    /// Appends this source description to the document's `sourceDescriptions`.
    public func apply(to document: inout Arazzo.Document) {
        document.sourceDescriptions.append(self)
    }
}

/// The Components Object: reusable ``Input`` schemas, ``Parameter``s, ``SuccessAction``s and ``FailureAction``s,
/// each keyed by its name.
///
/// ```swift
/// Components {
///     Parameter("page", in: .query, value: 1)                 // components.parameters.page
///     FailureAction.retry("backoff", after: 5, limit: 10)     // components.failureActions.backoff
/// }
/// ```
///
/// Definitions with the same name replace each other, the last one winning. A reference such as
/// `Parameter.reference("page")` is not a definition and is ignored here. Several `Components` in one document add
/// to the same Components Object.
public struct Components: DocumentComponent {
    /// The definitions this part adds.
    public var components: Arazzo.Components

    /// Creates the Components Object from the definitions in `content`.
    public init(
        vendorExtensions: VendorExtensions = [:], @ComponentsBuilder _ content: () -> [any ReusableComponent]
    ) {
        components = Arazzo.Components(vendorExtensions: vendorExtensions, content)
    }

    public func apply(to document: inout Arazzo.Document) {
        components.apply(to: &document)
    }
}

extension Arazzo.Components: DocumentComponent {
    /// Builds a Components Object from the definitions in `content`, as ``ArazzoKitBuilder/Components`` does.
    ///
    /// ```swift
    /// let components = Arazzo.Components {
    ///     Parameter("X-Trace-Id", in: .header, value: "telaio").componentKey("traceId")
    /// }
    /// ```
    public init(
        vendorExtensions: VendorExtensions = [:], @ComponentsBuilder _ content: () -> [any ReusableComponent]
    ) {
        self.init(vendorExtensions: vendorExtensions)
        for component in content() { component.apply(to: &self) }
    }

    /// Adds these definitions to the document's `components`; one with a name already there replaces it.
    public func apply(to document: inout Arazzo.Document) {
        for (name, value) in inputs { document.components.inputs[name] = value }
        for (name, value) in parameters { document.components.parameters[name] = value }
        for (name, value) in successActions { document.components.successActions[name] = value }
        for (name, value) in failureActions { document.components.failureActions[name] = value }
        for (name, value) in vendorExtensions { document.components.vendorExtensions[name] = value }
    }
}
