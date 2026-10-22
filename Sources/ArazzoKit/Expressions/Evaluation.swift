import JSONPath
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Arazzo {
    /// Resolves runtime expressions to values while a workflow executes.
    public protocol RuntimeExpressionResolver {
        /// Returns the value of the expression, or `nil` when it has no value in this context.
        func resolve(_ expression: RuntimeExpression) throws -> JSONValue?
    }

    /// Evaluates query languages for Criterion, Selector and Payload Replacement objects.
    ///
    /// JSONPath (RFC 9535 and the Goessner/Jayway draft) and JSON Pointer are built in. Provide a
    /// `QueryEvaluator` to add XPath support or to replace the built-in JSONPath engine; return
    /// `false` from ``supports(_:version:)`` for the languages it does not handle.
    public protocol QueryEvaluator {
        /// Whether this evaluator handles `kind` / `version`. Defaults to `true`.
        func supports(_ kind: ExpressionType.Kind, version: ExpressionType.Version) -> Bool

        /// Evaluates a `jsonpath` / `xpath` condition against `context`, returning pass or fail
        /// (non-empty node list, Effective Boolean Value, ...).
        func evaluateCondition(
            _ condition: String, kind: ExpressionType.Kind, version: ExpressionType.Version, context: JSONValue
        ) throws -> Bool

        /// Selects a value from `context`.
        func select(
            _ selector: String, kind: ExpressionType.Kind, version: ExpressionType.Version, context: JSONValue
        ) throws -> JSONValue?

        /// The locations a target expression selects in `document` (used for payload replacements).
        /// Defaults to unsupported.
        func locate(
            _ target: String, kind: ExpressionType.Kind, version: ExpressionType.Version, in document: JSONValue
        ) throws -> [NormalizedPath]
    }

    public enum EvaluationError: Error, Hashable, Sendable, CustomStringConvertible {
        case missingContext
        case nullContext
        case unsupportedQueryLanguage(ExpressionType.Kind)
        case invalidRegularExpression(String)
        case invalidSelector(String)

        public var description: String {
            switch self {
            case .missingContext: "The criterion requires a context."
            case .nullContext: "The context evaluated to null."
            case .unsupportedQueryLanguage(let kind):
                "'\(kind.rawValue)' expressions need a QueryEvaluator that supports them."
            case .invalidRegularExpression(let message): "Invalid regular expression: \(message)"
            case .invalidSelector(let message): "Invalid selector: \(message)"
            }
        }
    }
}

extension Arazzo.QueryEvaluator {
    public func supports(_ kind: Arazzo.ExpressionType.Kind, version: Arazzo.ExpressionType.Version) -> Bool { true }

    public func locate(
        _ target: String, kind: Arazzo.ExpressionType.Kind, version: Arazzo.ExpressionType.Version,
        in document: JSONValue
    ) throws -> [NormalizedPath] {
        throw Arazzo.EvaluationError.unsupportedQueryLanguage(kind)
    }
}

extension Arazzo {
    /// The query languages ArazzoKit evaluates itself: JSONPath and JSON Pointer.
    public enum BuiltInQueries {
        /// The JSONPath dialect used for an Expression Type version: `rfc9535` (the default) uses
        /// RFC 9535; `draft-goessner-dispatch-jsonpath-00` uses the Goessner-derived Jayway dialect.
        public static func dialect(for version: ExpressionType.Version) -> JSONPath.Dialect {
            version == .draftGoessnerDispatchJSONPath00 ? .jayway : .rfc9535
        }

        /// Compiles a JSONPath expression for an Expression Type version.
        public static func jsonPath(_ expression: String, version: ExpressionType.Version) throws -> JSONPath {
            do {
                return try JSONPath(expression, dialect: dialect(for: version))
            } catch {
                throw EvaluationError.invalidSelector("\(error)")
            }
        }

        /// Structured data stored as JSON text (e.g. an unparsed response body) is parsed first.
        static func structured(_ value: JSONValue) -> JSONValue {
            guard case .string(let text) = value,
                let first = text.first(where: { !$0.isWhitespace }), first == "{" || first == "[",
                let parsed = try? JSONValue(parsing: text)
            else { return value }
            return parsed
        }

        static func evaluateCondition(
            _ condition: String, kind: ExpressionType.Kind, version: ExpressionType.Version, context: JSONValue
        ) throws -> Bool {
            guard kind == .jsonPath else { throw EvaluationError.unsupportedQueryLanguage(kind) }
            return try jsonPath(condition, version: version).matches(structured(context))
        }

        static func select(
            _ selector: String, kind: ExpressionType.Kind, version: ExpressionType.Version, context: JSONValue
        ) throws -> JSONValue? {
            switch kind {
            case .jsonPointer:
                do {
                    return try JSONPointer(selector).resolve(in: structured(context))
                } catch {
                    throw EvaluationError.invalidSelector("\(error)")
                }
            case .jsonPath:
                let values = try jsonPath(selector, version: version).values(in: structured(context))
                switch values.count {
                case 0: return nil
                case 1: return values[0]
                default: return .array(values)
                }
            case .xPath:
                throw EvaluationError.unsupportedQueryLanguage(kind)
            }
        }

        static func locate(
            _ target: String, kind: ExpressionType.Kind, version: ExpressionType.Version, in document: JSONValue
        ) throws -> [NormalizedPath] {
            switch kind {
            case .jsonPath:
                return try jsonPath(target, version: version).paths(in: document)
            case .jsonPointer, .xPath:
                throw EvaluationError.unsupportedQueryLanguage(kind)
            }
        }
    }
}

// MARK: - Criterion evaluation

extension Arazzo.Criterion {
    /// Evaluates the criterion. Errors are thrown so callers can report them; per the specification
    /// an evaluation error means the criterion *fails* – use ``isSatisfied(in:queryEvaluator:)`` for that.
    public func evaluate(
        in resolver: some Arazzo.RuntimeExpressionResolver,
        queryEvaluator: (any Arazzo.QueryEvaluator)? = nil
    ) throws -> Bool {
        let render: (String) throws -> String = { text in
            try Arazzo.ExpressionTemplate(text).render { try resolver.resolve($0) }
        }
        switch effectiveType {
        case .simple:
            return try Arazzo.Condition(condition).evaluate(in: resolver)
        case .regex:
            guard let context else { throw Arazzo.EvaluationError.missingContext }
            guard let value = try resolver.resolve(context), !value.isNull else { return false }
            let pattern = try render(condition)
            let regex: Regex<AnyRegexOutput>
            do {
                regex = try Regex(pattern)
            } catch {
                throw Arazzo.EvaluationError.invalidRegularExpression("\(error)")
            }
            return try regex.firstMatch(in: value.embeddedStringValue) != nil
        case .jsonPath, .xPath, .expressionType:
            let (kind, version): (Arazzo.ExpressionType.Kind, Arazzo.ExpressionType.Version) =
                switch effectiveType {
                case .jsonPath: (.jsonPath, .rfc9535)
                case .xPath: (.xPath, .xpath31)
                case .expressionType(let type): (type.kind, type.version)
                default: (.jsonPath, .rfc9535)
                }
            guard let context else { throw Arazzo.EvaluationError.missingContext }
            guard let value = try resolver.resolve(context), !value.isNull else { return false }
            let rendered = try render(condition)
            if let queryEvaluator, queryEvaluator.supports(kind, version: version) {
                return try queryEvaluator.evaluateCondition(rendered, kind: kind, version: version, context: value)
            }
            return try Arazzo.BuiltInQueries.evaluateCondition(rendered, kind: kind, version: version, context: value)
        }
    }

    /// `true` when the criterion passes; any evaluation error counts as a failure.
    public func isSatisfied(
        in resolver: some Arazzo.RuntimeExpressionResolver,
        queryEvaluator: (any Arazzo.QueryEvaluator)? = nil
    ) -> Bool {
        (try? evaluate(in: resolver, queryEvaluator: queryEvaluator)) ?? false
    }
}

extension Array where Element == Arazzo.Criterion {
    /// All criteria must pass (logical AND). An empty list passes.
    public func areSatisfied(
        in resolver: some Arazzo.RuntimeExpressionResolver,
        queryEvaluator: (any Arazzo.QueryEvaluator)? = nil
    ) -> Bool {
        allSatisfy { $0.isSatisfied(in: resolver, queryEvaluator: queryEvaluator) }
    }
}

// MARK: - Selector & value evaluation

extension Arazzo.Selector {
    /// Applies the selector to its context. JSONPath and JSON Pointer are built in; XPath needs a
    /// ``Arazzo/QueryEvaluator``. A JSONPath selecting several nodes yields an array of their values.
    public func evaluate(
        in resolver: some Arazzo.RuntimeExpressionResolver,
        queryEvaluator: (any Arazzo.QueryEvaluator)? = nil
    ) throws -> JSONValue? {
        guard let contextValue = try resolver.resolve(context) else { return nil }
        switch type.kind {
        case .jsonPointer:
            do {
                return try JSONPointer(selector).resolve(in: contextValue)
            } catch {
                throw Arazzo.EvaluationError.invalidSelector("\(error)")
            }
        case let kind:
            let version = type.effectiveVersion
            if let queryEvaluator, queryEvaluator.supports(kind, version: version) {
                return try queryEvaluator.select(selector, kind: kind, version: version, context: contextValue)
            }
            return try Arazzo.BuiltInQueries.select(selector, kind: kind, version: version, context: contextValue)
        }
    }
}

extension Arazzo.Value {
    /// Computes the concrete value: expressions are resolved, selectors applied, and literal
    /// strings have their embedded `{$...}` expressions substituted. Nested literals are walked.
    public func evaluate(
        in resolver: some Arazzo.RuntimeExpressionResolver,
        queryEvaluator: (any Arazzo.QueryEvaluator)? = nil
    ) throws -> JSONValue {
        switch self {
        case .expression(let expression):
            return try resolver.resolve(expression) ?? .null
        case .selector(let selector):
            return try selector.evaluate(in: resolver, queryEvaluator: queryEvaluator) ?? .null
        case .literal(let json):
            return try Self.evaluateLiteral(json, in: resolver, queryEvaluator: queryEvaluator)
        }
    }

    static func evaluateLiteral(
        _ json: JSONValue,
        in resolver: some Arazzo.RuntimeExpressionResolver,
        queryEvaluator: (any Arazzo.QueryEvaluator)?
    ) throws -> JSONValue {
        switch json {
        case .string(let string):
            let template = Arazzo.ExpressionTemplate(string)
            guard template.hasExpressions else { return json }
            // A string that is exactly one embedded expression keeps the value's type.
            if template.segments.count == 1, case .expression(let e) = template.segments[0] {
                return try resolver.resolve(e) ?? .null
            }
            return .string(try template.render { try resolver.resolve($0) })
        case .array(let values):
            return .array(
                try values.map { try Arazzo.Value(interpreting: $0).evaluate(in: resolver, queryEvaluator: queryEvaluator) })
        case .object(let object):
            return .object(
                try object.mapValues {
                    try Arazzo.Value(interpreting: $0).evaluate(in: resolver, queryEvaluator: queryEvaluator)
                })
        default:
            return json
        }
    }
}

extension Arazzo.OutputValue {
    public func evaluate(
        in resolver: some Arazzo.RuntimeExpressionResolver,
        queryEvaluator: (any Arazzo.QueryEvaluator)? = nil
    ) throws -> JSONValue {
        switch self {
        case .expression(let e): try resolver.resolve(e) ?? .null
        case .selector(let s): try s.evaluate(in: resolver, queryEvaluator: queryEvaluator) ?? .null
        }
    }
}

// MARK: - A ready-made context

extension Arazzo {
    /// A simple, value-based ``RuntimeExpressionResolver`` holding the state of a running workflow.
    ///
    /// ```swift
    /// var context = Arazzo.EvaluationContext()
    /// context.statusCode = 200
    /// context.response = .init(headers: ["Content-Type": "application/json"], body: ["id": 42])
    /// try Arazzo.Condition("$statusCode == 200 && $response.body#/id == 42").evaluate(in: context) // true
    /// ```
    public struct EvaluationContext: RuntimeExpressionResolver, Sendable {
        /// A request, response or AsyncAPI message.
        public struct Message: Sendable, Hashable {
            /// Header names are matched case-insensitively.
            public var headers: [String: String]
            public var query: [String: String]
            public var path: [String: String]
            /// The parsed body (JSON) or the raw text (XML, plain text) as `.string`.
            public var body: JSONValue?

            public init(
                headers: [String: String] = [:], query: [String: String] = [:], path: [String: String] = [:],
                body: JSONValue? = nil
            ) {
                self.headers = headers
                self.query = query
                self.path = path
                self.body = body
            }

            public func header(_ name: String) -> String? {
                if let value = headers[name] { return value }
                let lowercased = name.lowercased()
                return headers.first { $0.key.lowercased() == lowercased }?.value
            }
        }

        public var url: String?
        public var method: String?
        public var statusCode: Int?
        public var request: Message?
        public var response: Message?
        /// The AsyncAPI message (`$message.header...`, `$message.payload...`).
        public var message: Message?
        /// Inputs of the current workflow.
        public var inputs: JSONValue
        /// Outputs of the current workflow (`$outputs.<name>`).
        public var outputs: [String: JSONValue]
        /// Outputs of completed steps, keyed by `stepId`.
        public var stepOutputs: [String: [String: JSONValue]]
        /// Inputs of workflows, keyed by `workflowId`.
        public var workflowInputs: [String: JSONValue]
        /// Outputs of workflows, keyed by `workflowId`.
        public var workflowOutputs: [String: [String: JSONValue]]
        /// The description being executed (for `$self`, `$sourceDescriptions` and `$components`).
        public var document: Document?

        public init(
            url: String? = nil,
            method: String? = nil,
            statusCode: Int? = nil,
            request: Message? = nil,
            response: Message? = nil,
            message: Message? = nil,
            inputs: JSONValue = .object([:]),
            outputs: [String: JSONValue] = [:],
            stepOutputs: [String: [String: JSONValue]] = [:],
            workflowInputs: [String: JSONValue] = [:],
            workflowOutputs: [String: [String: JSONValue]] = [:],
            document: Document? = nil
        ) {
            self.url = url
            self.method = method
            self.statusCode = statusCode
            self.request = request
            self.response = response
            self.message = message
            self.inputs = inputs
            self.outputs = outputs
            self.stepOutputs = stepOutputs
            self.workflowInputs = workflowInputs
            self.workflowOutputs = workflowOutputs
            self.document = document
        }

        public func resolve(_ expression: RuntimeExpression) throws -> JSONValue? {
            switch expression.kind {
            case .invalid(let error): throw error
            case .url: return url.map(JSONValue.string)
            case .method: return method.map(JSONValue.string)
            case .statusCode: return statusCode.map(JSONValue.integer)
            case .self: return document?.selfURI.map(JSONValue.string)
            case .request(let source): return Self.resolve(source, in: request)
            case .response(let source): return Self.resolve(source, in: response)
            case .message(let source): return Self.resolve(source, in: message)
            case .inputs(let name, let pointer):
                return Self.lookup(name, in: inputs, pointer: pointer)
            case .outputs(let name, let pointer):
                return Self.lookup(name, in: .object(OrderedDictionary(outputs.map { ($0.key, $0.value) })), pointer: pointer)
            case .steps(let stepId, let name, let pointer):
                guard let outputs = stepOutputs[stepId] else { return nil }
                return Self.lookup(name, in: .object(OrderedDictionary(outputs.map { ($0.key, $0.value) })), pointer: pointer)
            case .workflows(let workflowId, let field, let name, let pointer):
                switch field {
                case .inputs:
                    guard let inputs = workflowInputs[workflowId] else { return nil }
                    return Self.lookup(name, in: inputs, pointer: pointer)
                case .outputs:
                    guard let outputs = workflowOutputs[workflowId] else { return nil }
                    return Self.lookup(
                        name, in: .object(OrderedDictionary(outputs.map { ($0.key, $0.value) })), pointer: pointer)
                }
            case .sourceDescriptions(let name, let reference):
                guard let source = document?.sourceDescription(named: name) else { return nil }
                switch reference {
                case "name": return .string(source.name)
                case "url": return .string(source.url)
                case "type": return source.type.map { .string($0.rawValue) }
                default: return nil
                }
            case .components(let type, let name):
                guard let components = document?.components else { return nil }
                let encodable: (any Encodable)? =
                    switch type {
                    case .parameters: components.parameters[name]
                    case .successActions: components.successActions[name]
                    case .failureActions: components.failureActions[name]
                    }
                guard let encodable else { return nil }
                let data = try JSONEncoder().encode(encodable)
                return try JSONDecoder().decode(JSONValue.self, from: data)
            }
        }

        static func resolve(_ source: RuntimeExpression.Source, in message: Message?) -> JSONValue? {
            guard let message else { return nil }
            switch source {
            case .header(let name): return message.header(name).map(JSONValue.string)
            case .query(let name): return message.query[name].map(JSONValue.string)
            case .path(let name): return message.path[name].map(JSONValue.string)
            case .body(let pointer), .payload(let pointer):
                guard let body = message.body else { return nil }
                guard let pointer else { return body }
                return pointer.resolve(in: body)
            }
        }

        /// Exact key first, then (for names containing dots) a nested property path.
        static func lookup(_ name: String, in container: JSONValue, pointer: JSONPointer?) -> JSONValue? {
            var value = container[name]
            if value == nil, name.contains(".") {
                var current: JSONValue? = container
                for part in name.split(separator: ".") { current = current?[String(part)] }
                value = current
            }
            guard let value else { return nil }
            guard let pointer else { return value }
            return pointer.resolve(in: value)
        }
    }
}

// MARK: - Request bodies

extension Arazzo.RequestBody {
    /// The payload to send: runtime expressions, Selector Objects and embedded `{$...}` expressions
    /// are evaluated, then each Payload Replacement is applied in order.
    ///
    /// JSON Pointer and JSONPath replacement targets are built in (a JSONPath target replaces every
    /// node it selects); XPath targets need a ``Arazzo/QueryEvaluator`` implementing `locate`.
    /// A JSON payload written as a string template is parsed before replacements are applied.
    public func resolvedPayload(
        in resolver: some Arazzo.RuntimeExpressionResolver,
        queryEvaluator: (any Arazzo.QueryEvaluator)? = nil
    ) throws -> JSONValue? {
        guard let payload else { return nil }
        var document = try Arazzo.Value.evaluateLiteral(payload, in: resolver, queryEvaluator: queryEvaluator)
        guard !replacements.isEmpty else { return document }
        if isJSON, case .string = document {
            document = Arazzo.BuiltInQueries.structured(document)
        }
        for replacement in replacements {
            let value = try replacement.value.evaluate(in: resolver, queryEvaluator: queryEvaluator)
            let kind = replacement.effectiveTargetKind(in: self)
            let version = replacement.targetSelectorType?.effectiveVersion ?? kind.defaultVersion
            if let queryEvaluator, queryEvaluator.supports(kind, version: version), kind != .jsonPointer {
                for location in try queryEvaluator.locate(replacement.target, kind: kind, version: version, in: document) {
                    try document.set(value, at: location)
                }
                continue
            }
            switch kind {
            case .jsonPointer:
                do {
                    try document.set(value, at: JSONPointer(replacement.target))
                } catch {
                    throw Arazzo.EvaluationError.invalidSelector("\(error)")
                }
            case .jsonPath, .xPath:
                for location in try Arazzo.BuiltInQueries.locate(replacement.target, kind: kind, version: version, in: document) {
                    try document.set(value, at: location)
                }
            }
        }
        return document
    }
}
