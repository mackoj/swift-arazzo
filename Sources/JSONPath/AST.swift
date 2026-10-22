// The syntax tree shared by the RFC 9535 and Jayway dialects.

extension JSONPath {
    /// How a member name was written, kept so expressions can be printed back faithfully.
    enum QuoteStyle: Hashable, Sendable {
        case none  // dot notation: .name
        case single
        case double
    }

    struct Query: Hashable, Sendable {
        enum Root: Hashable, Sendable {
            case root  // $
            case current  // @
        }

        var root: Root
        var segments: [Segment]

        /// RFC 9535 singular query: only child segments with a single name or index selector.
        var isSingular: Bool {
            segments.allSatisfy { segment in
                guard case .child(let selectors) = segment, selectors.count == 1 else { return false }
                switch selectors[0] {
                case .name, .index: return true
                default: return false
                }
            }
        }

        /// Jayway: a path is definite when it can only produce a single value.
        var isDefinite: Bool {
            segments.allSatisfy { $0.isDefinite }
        }
    }

    enum Segment: Hashable, Sendable {
        /// `.name`, `.*`, `[selectors]`
        case child([Selector])
        /// `..name`, `..*`, `..[selectors]`
        case descendant([Selector])
        /// Jayway path function, e.g. `.length()` or `.sum(1, $.x)`.
        case function(FunctionCall)

        var isDefinite: Bool {
            switch self {
            case .child(let selectors):
                guard selectors.count == 1 else { return false }
                switch selectors[0] {
                case .name, .index: return true
                default: return false
                }
            case .descendant: return false
            case .function: return true
            }
        }
    }

    enum Selector: Hashable, Sendable {
        case name(String, QuoteStyle)
        case wildcard
        case index(Int)
        case slice(start: Int?, end: Int?, step: Int?)
        case filter(FilterExpression)
    }

    indirect enum FilterExpression: Hashable, Sendable {
        case or([FilterExpression])
        case and([FilterExpression])
        case not(FilterExpression)
        /// An existence test (`@.a`), optionally negated (`!@.a`).
        case exists(Query, negated: Bool)
        case comparison(Operand, ComparisonOperator, Operand)
        /// A function used as a test, e.g. `match(@.a, 'x')` (RFC 9535 LogicalType / NodesType).
        case function(FunctionCall)
    }

    indirect enum Operand: Hashable, Sendable {
        /// A literal; `raw` is the source text (for printing).
        case literal(JSONValue, raw: String)
        case query(Query)
        /// An RFC 9535 function expression such as `length(@.a)`.
        case function(FunctionCall)
        /// A Jayway regular expression literal `/pattern/flags`.
        case regex(pattern: String, flags: String)
    }

    struct FunctionCall: Hashable, Sendable {
        enum Style: Hashable, Sendable {
            /// `name(arguments)` inside filters.
            case rfc9535
            /// `path.name(arguments)` (Jayway path function).
            case jayway
        }

        var name: String
        var arguments: [FunctionArgument]
        var style: Style
    }

    indirect enum FunctionArgument: Hashable, Sendable {
        case literal(JSONValue, raw: String)
        case query(Query)
        case function(FunctionCall)
        case logical(FilterExpression)
    }

    enum ComparisonOperator: String, Hashable, Sendable, CaseIterable {
        case equal = "=="
        case notEqual = "!="
        case strictEqual = "==="
        case strictNotEqual = "!=="
        case less = "<"
        case lessOrEqual = "<="
        case greater = ">"
        case greaterOrEqual = ">="
        // Jayway extensions
        case regex = "=~"
        case `in` = "IN"
        case nin = "NIN"
        case contains = "CONTAINS"
        case all = "ALL"
        case size = "SIZE"
        case exists = "EXISTS"
        case type = "TYPE"
        case empty = "EMPTY"
        case subsetOf = "SUBSETOF"
        case anyOf = "ANYOF"
        case noneOf = "NONEOF"

        static let wordOperators: [String: ComparisonOperator] = Dictionary(
            uniqueKeysWithValues: allCases.filter { $0.rawValue.first!.isLetter }.map { ($0.rawValue, $0) })
    }
}

// MARK: - Printing

extension JSONPath.Query {
    /// Jayway-style rendering: `$['store']['book'][*]`, filters printed in full.
    var jaywayDescription: String {
        var result = root == .root ? "$" : "@"
        for segment in segments {
            switch segment {
            case .child(let selectors):
                result += JSONPath.jaywayBracket(selectors)
            case .descendant(let selectors):
                result += ".." + JSONPath.jaywayBracket(selectors)
            case .function(let call):
                result += "." + call.jaywayDescription
            }
        }
        return result
    }

    /// RFC 9535 rendering: `$['store']['book'][*][?@.price < 10]`.
    var rfcDescription: String {
        var result = root == .root ? "$" : "@"
        for segment in segments {
            switch segment {
            case .child(let selectors):
                result += "[" + selectors.map(\.rfcDescription).joined(separator: ", ") + "]"
            case .descendant(let selectors):
                result += "..[" + selectors.map(\.rfcDescription).joined(separator: ", ") + "]"
            case .function(let call):
                result += "." + call.jaywayDescription
            }
        }
        return result
    }
}

extension JSONPath {
    static func jaywayBracket(_ selectors: [Selector]) -> String {
        if selectors.count == 1, case .filter(let expression) = selectors[0] {
            return expression.jaywayFilterDescription
        }
        return "[" + selectors.map(\.jaywayDescription).joined(separator: ",") + "]"
    }

    static func quoted(_ string: String, _ style: QuoteStyle) -> String {
        let quote: Character = style == .double ? "\"" : "'"
        var result = String(quote)
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case _ where Character(scalar) == quote: result += "\\" + String(quote)
            case let s where s.value < 0x20:
                let hex = String(s.value, radix: 16)
                result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: result.unicodeScalars.append(scalar)
            }
        }
        result.append(quote)
        return result
    }
}

extension JSONPath.Selector {
    var jaywayDescription: String {
        switch self {
        case .name(let name, let style): JSONPath.quoted(name, style == .double ? .double : .single)
        case .wildcard: "*"
        case .index(let index): String(index)
        case .slice(let start, let end, let step):
            (start.map(String.init) ?? "") + ":" + (end.map(String.init) ?? "") + (step.map { ":\($0)" } ?? "")
        case .filter(let expression): String(expression.jaywayFilterDescription.dropFirst().dropLast())
        }
    }

    var rfcDescription: String {
        switch self {
        case .name(let name, _): JSONPath.quoted(name, .single)
        case .wildcard: "*"
        case .index(let index): String(index)
        case .slice(let start, let end, let step):
            (start.map(String.init) ?? "") + ":" + (end.map(String.init) ?? "") + (step.map { ":\($0)" } ?? "")
        case .filter(let expression): "?" + expression.rfcDescription(topLevel: true)
        }
    }
}

extension JSONPath.FilterExpression {
    /// `[?(...)]` in Jayway's normalized form (`FilterCompiler` output).
    var jaywayFilterDescription: String {
        switch self {
        case .or, .and: "[?" + jaywayDescription + "]"
        default: "[?(" + jaywayDescription + ")]"
        }
    }

    var jaywayDescription: String {
        switch self {
        case .or(let terms): "(" + terms.map(\.jaywayDescription).joined(separator: " || ") + ")"
        case .and(let terms): "(" + terms.map(\.jaywayDescription).joined(separator: " && ") + ")"
        case .not(let inner): "!(" + inner.jaywayDescription + ")"
        case .exists(let query, let negated): (negated ? "!" : "") + query.jaywayDescription
        case .comparison(let lhs, let op, let rhs):
            op == .exists ? lhs.jaywayDescription : "\(lhs.jaywayDescription) \(op.rawValue) \(rhs.jaywayDescription)"
        case .function(let call): call.rfcDescription
        }
    }

    func rfcDescription(topLevel: Bool = false) -> String {
        switch self {
        case .or(let terms):
            let text = terms.map { $0.rfcDescription() }.joined(separator: " || ")
            return topLevel ? text : "(" + text + ")"
        case .and(let terms):
            return terms.map { term in
                if case .or = term { return "(" + term.rfcDescription(topLevel: true) + ")" }
                return term.rfcDescription()
            }.joined(separator: " && ")
        case .not(let inner): return "!(" + inner.rfcDescription(topLevel: true) + ")"
        case .exists(let query, let negated): return (negated ? "!" : "") + query.rfcDescription
        case .comparison(let lhs, let op, let rhs):
            return "\(lhs.rfcDescription) \(op.rawValue) \(rhs.rfcDescription)"
        case .function(let call): return call.rfcDescription
        }
    }
}

extension JSONPath.Operand {
    var jaywayDescription: String {
        switch self {
        case .literal(_, let raw): raw
        case .query(let query): query.jaywayDescription
        case .function(let call): call.rfcDescription
        case .regex(let pattern, let flags): "/" + pattern + "/" + flags
        }
    }

    var rfcDescription: String {
        switch self {
        case .literal(_, let raw): raw
        case .query(let query): query.rfcDescription
        case .function(let call): call.rfcDescription
        case .regex(let pattern, let flags): "/" + pattern + "/" + flags
        }
    }
}

extension JSONPath.FunctionCall {
    var jaywayDescription: String {
        name + "(" + arguments.map(\.jaywayDescription).joined(separator: ",") + ")"
    }

    var rfcDescription: String {
        name + "(" + arguments.map(\.rfcDescription).joined(separator: ", ") + ")"
    }
}

extension JSONPath.FunctionArgument {
    var jaywayDescription: String {
        switch self {
        case .literal(_, let raw): raw
        case .query(let query): query.jaywayDescription
        case .function(let call): call.rfcDescription
        case .logical(let expression): expression.jaywayDescription
        }
    }

    var rfcDescription: String {
        switch self {
        case .literal(_, let raw): raw
        case .query(let query): query.rfcDescription
        case .function(let call): call.rfcDescription
        case .logical(let expression): expression.rfcDescription(topLevel: true)
        }
    }
}
