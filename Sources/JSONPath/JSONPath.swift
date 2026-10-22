/// A compiled JSONPath expression.
///
/// ```swift
/// let document = try JSONValue(parsing: #"{"store": {"book": [{"price": 8.95}, {"price": 22.99}]}}"#)
/// let path = try JSONPath("$.store.book[?@.price < 10]")
/// try path.values(in: document)          // [{"price": 8.95}]
/// try path.paths(in: document)           // [$['store']['book'][0]]
/// ```
///
/// Two dialects are supported:
/// - ``Dialect/rfc9535`` – the IETF standard ([RFC 9535](https://www.rfc-editor.org/rfc/rfc9535)), the default.
/// - ``Dialect/jayway`` – the widely deployed Jayway JsonPath dialect (also implemented by
///   SMJJSONPath and Sextant), with `[?(...)]` filters, extra operators and path functions.
public struct JSONPath: Hashable, Sendable, CustomStringConvertible {
    public enum Dialect: String, Hashable, Sendable, CaseIterable {
        case rfc9535
        case jayway
    }

    /// The text the path was compiled from.
    public let expression: String
    public let dialect: Dialect
    let query: Query

    /// Compiles a JSONPath expression.
    public init(_ expression: String, dialect: Dialect = .rfc9535) throws {
        self.expression = expression
        self.dialect = dialect
        switch dialect {
        case .rfc9535: query = try RFC9535Parser.parse(expression)
        case .jayway: query = try JaywayParser.parse(expression)
        }
    }

    /// Returns a description of why `expression` is invalid, or `nil` if it is valid.
    public static func validate(_ expression: String, dialect: Dialect = .rfc9535) -> String? {
        do {
            _ = try JSONPath(expression, dialect: dialect)
            return nil
        } catch let error as ParseError {
            return error.message
        } catch {
            return "\(error)"
        }
    }

    /// A normalized rendering of the path: `$['store']['book'][*]`.
    public var description: String {
        switch dialect {
        case .rfc9535: query.rfcDescription
        case .jayway: query.jaywayDescription
        }
    }

    /// `true` when the path can select at most one node (RFC 9535 "singular query" /
    /// Jayway "definite path").
    public var isSingular: Bool {
        switch dialect {
        case .rfc9535: query.isSingular
        case .jayway: query.isDefinite
        }
    }

    /// A node selected by a path: its location and value.
    /// `location` is `nil` for values computed by functions (Jayway `.length()`, `.avg()`, ...).
    public struct Node: Hashable, Sendable {
        public let location: NormalizedPath?
        public let value: JSONValue

        public init(location: NormalizedPath?, value: JSONValue) {
            self.location = location
            self.value = value
        }
    }

    /// The nodes selected from `root`, in result order.
    public func nodes(in root: JSONValue) throws -> [Node] {
        switch dialect {
        case .rfc9535: try RFC9535Evaluator(root: root).evaluate(query, current: root)
        case .jayway: try JaywayEvaluator(root: root).evaluate(query, current: root)
        }
    }

    /// The values selected from `root`.
    public func values(in root: JSONValue) throws -> [JSONValue] {
        try nodes(in: root).map(\.value)
    }

    /// The normalized paths of the selected nodes (function results have none).
    public func paths(in root: JSONValue) throws -> [NormalizedPath] {
        try nodes(in: root).compactMap(\.location)
    }

    /// The first selected value, or `nil` when nothing matches.
    public func firstValue(in root: JSONValue) throws -> JSONValue? {
        try nodes(in: root).first?.value
    }

    /// `true` when at least one node is selected.
    public func matches(_ root: JSONValue) throws -> Bool {
        try !nodes(in: root).isEmpty
    }

    /// Paths are equal when they have the same dialect and the same normalized form,
    /// regardless of spelling (`$.a` == `$['a']`).
    public static func == (lhs: JSONPath, rhs: JSONPath) -> Bool {
        lhs.dialect == rhs.dialect && lhs.query.rfcDescription == rhs.query.rfcDescription
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(dialect)
        hasher.combine(query.rfcDescription)
    }
}

extension JSONPath {
    /// A syntax error in a JSONPath expression.
    public struct ParseError: Error, Hashable, Sendable, CustomStringConvertible {
        public let message: String
        /// The offset (in Unicode scalars) where the problem was detected.
        public let position: Int

        public init(message: String, position: Int) {
            self.message = message
            self.position = position
        }

        public var description: String { message }
    }

    /// An error raised while evaluating a valid expression (e.g. averaging an empty array
    /// with the Jayway `avg()` function).
    public struct EvaluationError: Error, Hashable, Sendable, CustomStringConvertible {
        public let message: String

        public init(_ message: String) {
            self.message = message
        }

        public var description: String { message }
    }
}

extension JSONValue {
    /// Evaluates a JSONPath expression against this value.
    public func query(_ path: String, dialect: JSONPath.Dialect = .rfc9535) throws -> [JSONValue] {
        try JSONPath(path, dialect: dialect).values(in: self)
    }

    /// Evaluates a compiled JSONPath against this value.
    public func query(_ path: JSONPath) throws -> [JSONValue] {
        try path.values(in: self)
    }
}
