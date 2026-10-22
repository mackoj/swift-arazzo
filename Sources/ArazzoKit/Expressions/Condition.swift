import JSONPath
extension Arazzo {
    /// A parsed `simple` condition, e.g. `$statusCode == 200 && $response.body#/items/0 != null`.
    ///
    /// Grammar (lowest to highest precedence):
    /// ```
    /// or         = and *( "||" and )
    /// and        = comparison *( "&&" comparison )
    /// comparison = unary [ ( "==" / "!=" / "<" / "<=" / ">" / ">=" ) unary ]
    /// unary      = "!" unary / primary
    /// primary    = literal / runtime-expression *accessor / "(" or ")"
    /// accessor   = "[" ( integer / 'string' ) "]" / "." name
    /// literal    = true / false / null / number / 'single-quoted string'   ; '' escapes a quote
    /// ```
    public indirect enum Condition: Hashable, Sendable, CustomStringConvertible {
        public enum Accessor: Hashable, Sendable {
            case index(Int)
            case property(String)
        }

        public enum BinaryOperator: String, Hashable, Sendable {
            case equal = "=="
            case notEqual = "!="
            case less = "<"
            case lessOrEqual = "<="
            case greater = ">"
            case greaterOrEqual = ">="
            case and = "&&"
            case or = "||"
        }

        case literal(JSONValue)
        case expression(RuntimeExpression, accessors: [Accessor])
        case not(Condition)
        case binary(Condition, BinaryOperator, Condition)

        public struct ParseError: Error, Hashable, Sendable, CustomStringConvertible {
            public let condition: String
            public let message: String
            public var description: String { "Invalid condition '\(condition)': \(message)" }
        }

        /// Parses a simple condition.
        public init(_ string: String) throws {
            var parser = try ConditionParser(string)
            self = try parser.parseCondition()
        }

        /// The runtime expressions the condition reads.
        public var runtimeExpressions: [RuntimeExpression] {
            switch self {
            case .literal: []
            case .expression(let e, _): [e]
            case .not(let c): c.runtimeExpressions
            case .binary(let l, _, let r): l.runtimeExpressions + r.runtimeExpressions
            }
        }

        public var description: String {
            switch self {
            case .literal(.string(let s)): "'" + s.replacingAll("'", with: "''") + "'"
            case .literal(let v): v.jsonString
            case .expression(let e, let accessors):
                e.rawValue
                    + accessors.map {
                        switch $0 {
                        case .index(let i): "[\(i)]"
                        case .property(let p): ".\(p)"
                        }
                    }.joined()
            case .not(let c): "!(\(c))"
            case .binary(let l, let op, let r): "(\(l) \(op.rawValue) \(r))"
            }
        }
    }
}

// MARK: - Evaluation

extension Arazzo.Condition {
    public enum EvaluationError: Error, Hashable, Sendable, CustomStringConvertible {
        case unresolvable(String)
        case typeMismatch(String)

        public var description: String {
            switch self {
            case .unresolvable(let message): "Cannot resolve \(message)"
            case .typeMismatch(let message): "Type mismatch: \(message)"
            }
        }
    }

    /// Evaluates the condition to a value.
    public func value(in resolver: some Arazzo.RuntimeExpressionResolver) throws -> JSONValue {
        switch self {
        case .literal(let value):
            return value
        case .expression(let expression, let accessors):
            var value = try resolver.resolve(expression) ?? .null
            for accessor in accessors {
                switch accessor {
                case .index(let index): value = value[index] ?? .null
                case .property(let name): value = value[name] ?? .null
                }
            }
            return value
        case .not(let condition):
            return .bool(!(try condition.value(in: resolver).isTruthyCondition))
        case .binary(let lhs, let op, let rhs):
            switch op {
            case .and:
                guard try lhs.value(in: resolver).isTruthyCondition else { return false }
                return .bool(try rhs.value(in: resolver).isTruthyCondition)
            case .or:
                if try lhs.value(in: resolver).isTruthyCondition { return true }
                return .bool(try rhs.value(in: resolver).isTruthyCondition)
            default:
                return .bool(
                    Self.compare(try lhs.value(in: resolver), op, try rhs.value(in: resolver)))
            }
        }
    }

    /// Evaluates the condition: passes only when it evaluates to `true`.
    public func evaluate(in resolver: some Arazzo.RuntimeExpressionResolver) throws -> Bool {
        try value(in: resolver).isTruthyCondition
    }

    /// Comparison semantics from the specification:
    /// string comparisons are case-insensitive, numeric strings are coerced for numeric operators,
    /// and `null` only equals itself.
    static func compare(_ lhs: JSONValue, _ op: BinaryOperator, _ rhs: JSONValue) -> Bool {
        if lhs.isNull || rhs.isNull {
            switch op {
            case .equal: return lhs.isNull && rhs.isNull
            case .notEqual: return !(lhs.isNull && rhs.isNull)
            default: return false
            }
        }
        // Numeric comparison (with numeric-string coercion).
        if let l = lhs.numericValueForComparison, let r = rhs.numericValueForComparison,
            lhs.doubleValue != nil || rhs.doubleValue != nil
        {
            switch op {
            case .equal: return l == r
            case .notEqual: return l != r
            case .less: return l < r
            case .lessOrEqual: return l <= r
            case .greater: return l > r
            case .greaterOrEqual: return l >= r
            case .and, .or: return false
            }
        }
        switch (lhs, rhs) {
        case (.string(let l), .string(let r)):
            let a = l.lowercased()
            let b = r.lowercased()
            switch op {
            case .equal: return a == b
            case .notEqual: return a != b
            case .less: return a < b
            case .lessOrEqual: return a <= b
            case .greater: return a > b
            case .greaterOrEqual: return a >= b
            case .and, .or: return false
            }
        case (.bool(let l), .bool(let r)):
            switch op {
            case .equal: return l == r
            case .notEqual: return l != r
            default: return false
            }
        default:
            switch op {
            case .equal: return lhs == rhs
            case .notEqual: return lhs != rhs
            default: return false
            }
        }
    }
}

extension JSONValue {
    /// Truthiness for conditions: only `true` passes.
    var isTruthyCondition: Bool { boolValue == true }

    var numericValueForComparison: Double? {
        switch self {
        case .integer(let v): Double(v)
        case .number(let v): v
        case .string(let s): Double(s.trimmingWhitespace())
        default: nil
        }
    }
}

// MARK: - Lexer & parser

private enum ConditionToken: Equatable {
    case expression(String)
    case number(Double, isInteger: Bool)
    case string(String)
    case identifier(String)  // true, false, null
    case op(String)
    case leftParen, rightParen, leftBracket, rightBracket, dot
}

private struct ConditionParser {
    let source: String
    var tokens: [ConditionToken]
    var position = 0

    init(_ source: String) throws {
        self.source = source
        tokens = try Self.tokenize(source)
    }

    func fail(_ message: String) -> Arazzo.Condition.ParseError {
        .init(condition: source, message: message)
    }

    static func tokenize(_ source: String) throws -> [ConditionToken] {
        let characters = Array(source)
        var tokens: [ConditionToken] = []
        var i = 0
        func fail(_ message: String) -> Arazzo.Condition.ParseError {
            .init(condition: source, message: message)
        }
        let expressionTerminators: Set<Character> = ["(", ")", "<", ">", "=", "!", "&", "|", "[", "]", " ", "\t", "\n", "\r"]
        while i < characters.count {
            let c = characters[i]
            if c.isWhitespace {
                i += 1
                continue
            }
            switch c {
            case "$":
                var j = i
                while j < characters.count, !expressionTerminators.contains(characters[j]) { j += 1 }
                tokens.append(.expression(String(characters[i..<j])))
                i = j
            case "'":
                var value = ""
                var j = i + 1
                var closed = false
                while j < characters.count {
                    if characters[j] == "'" {
                        if j + 1 < characters.count, characters[j + 1] == "'" {
                            value.append("'")
                            j += 2
                            continue
                        }
                        closed = true
                        j += 1
                        break
                    }
                    value.append(characters[j])
                    j += 1
                }
                guard closed else { throw fail("unterminated string literal") }
                tokens.append(.string(value))
                i = j
            case "(":
                tokens.append(.leftParen)
                i += 1
            case ")":
                tokens.append(.rightParen)
                i += 1
            case "[":
                tokens.append(.leftBracket)
                i += 1
            case "]":
                tokens.append(.rightBracket)
                i += 1
            case ".":
                // A leading '.' followed by digits is a number (e.g. .5).
                if i + 1 < characters.count, characters[i + 1].isASCIIDigit,
                    tokens.last.map({ if case .rightBracket = $0 { false } else { true } }) ?? true
                {
                    fallthrough
                }
                tokens.append(.dot)
                i += 1
            case "-", "0"..."9":
                var j = i
                if characters[j] == "-" { j += 1 }
                var isInteger = true
                while j < characters.count,
                    characters[j].isASCIIDigit || characters[j] == "." || characters[j] == "e" || characters[j] == "E"
                        || ((characters[j] == "+" || characters[j] == "-") && (characters[j - 1] == "e" || characters[j - 1] == "E"))
                {
                    if !characters[j].isASCIIDigit { isInteger = false }
                    j += 1
                }
                let text = String(characters[i..<j])
                guard let number = Double(text) else { throw fail("invalid number '\(text)'") }
                tokens.append(.number(number, isInteger: isInteger))
                i = j
            case "=", "!", "<", ">":
                if i + 1 < characters.count, characters[i + 1] == "=" {
                    tokens.append(.op(String(c) + "="))
                    i += 2
                } else if c == "=" {
                    throw fail("use '==' for equality")
                } else {
                    tokens.append(.op(String(c)))
                    i += 1
                }
            case "&", "|":
                guard i + 1 < characters.count, characters[i + 1] == c else {
                    throw fail("use '\(c)\(c)' for logical operators")
                }
                tokens.append(.op(String(c) + String(c)))
                i += 2
            default:
                if c.isLetter || c == "_" {
                    var j = i
                    while j < characters.count, characters[j].isLetter || characters[j].isNumber || characters[j] == "_"
                        || characters[j] == "-"
                    {
                        j += 1
                    }
                    tokens.append(.identifier(String(characters[i..<j])))
                    i = j
                } else {
                    throw fail("unexpected character '\(c)'")
                }
            }
        }
        return tokens
    }

    var current: ConditionToken? { position < tokens.count ? tokens[position] : nil }

    mutating func advance() -> ConditionToken? {
        defer { position += 1 }
        return current
    }

    mutating func parseCondition() throws -> Arazzo.Condition {
        guard !tokens.isEmpty else { throw fail("empty condition") }
        let condition = try parseOr()
        guard current == nil else { throw fail("unexpected token after end of condition") }
        return condition
    }

    mutating func parseOr() throws -> Arazzo.Condition {
        var lhs = try parseAnd()
        while current == .op("||") {
            position += 1
            lhs = .binary(lhs, .or, try parseAnd())
        }
        return lhs
    }

    mutating func parseAnd() throws -> Arazzo.Condition {
        var lhs = try parseComparison()
        while current == .op("&&") {
            position += 1
            lhs = .binary(lhs, .and, try parseComparison())
        }
        return lhs
    }

    mutating func parseComparison() throws -> Arazzo.Condition {
        let lhs = try parseUnary()
        if case .op(let symbol) = current, let op = Arazzo.Condition.BinaryOperator(rawValue: symbol),
            op != .and, op != .or
        {
            position += 1
            return .binary(lhs, op, try parseUnary())
        }
        return lhs
    }

    mutating func parseUnary() throws -> Arazzo.Condition {
        if current == .op("!") {
            position += 1
            return .not(try parseUnary())
        }
        return try parsePrimary()
    }

    mutating func parsePrimary() throws -> Arazzo.Condition {
        guard let token = advance() else { throw fail("unexpected end of condition") }
        switch token {
        case .leftParen:
            let inner = try parseOr()
            guard advance() == .rightParen else { throw fail("missing ')'") }
            return inner
        case .number(let value, let isInteger):
            if isInteger, let int = Int(exactly: value) { return .literal(.integer(int)) }
            return .literal(.number(value))
        case .string(let value):
            return .literal(.string(value))
        case .identifier(let name):
            switch name {
            case "true": return .literal(.bool(true))
            case "false": return .literal(.bool(false))
            case "null": return .literal(.null)
            default: throw fail("unknown identifier '\(name)'")
            }
        case .expression(let text):
            let expression: Arazzo.RuntimeExpression
            do {
                expression = try Arazzo.RuntimeExpression(text)
            } catch {
                throw fail("\(error)")
            }
            var accessors: [Arazzo.Condition.Accessor] = []
            while true {
                if current == .leftBracket {
                    position += 1
                    switch advance() {
                    case .number(let n, true)?:
                        guard let index = Int(exactly: n) else { throw fail("invalid index") }
                        accessors.append(.index(index))
                    case .string(let key)?:
                        accessors.append(.property(key))
                    default:
                        throw fail("expected an index or quoted key inside '[]'")
                    }
                    guard advance() == .rightBracket else { throw fail("missing ']'") }
                } else if current == .dot, accessors.isEmpty == false {
                    position += 1
                    guard case .identifier(let name)? = advance() else { throw fail("expected a property name after '.'") }
                    accessors.append(.property(name))
                } else {
                    break
                }
            }
            return .expression(expression, accessors: accessors)
        default:
            throw fail("unexpected token")
        }
    }
}
