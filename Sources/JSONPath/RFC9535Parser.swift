/// A strict parser for RFC 9535 JSONPath, including the well-typedness rules of §2.4.3.
struct RFC9535Parser {
    let scalars: [Unicode.Scalar]
    var position = 0

    /// The I-JSON safe integer range required for indices and slice bounds.
    static let maxSafeInteger = 9_007_199_254_740_991

    static func parse(_ text: String) throws -> JSONPath.Query {
        var parser = RFC9535Parser(scalars: Array(text.unicodeScalars))
        guard parser.current == "$" else { throw parser.error("A JSONPath query must start with '$'") }
        parser.position += 1
        let segments = try parser.parseSegments(inFilter: false)
        guard parser.position == parser.scalars.count else {
            throw parser.error("Unexpected character '\(parser.scalars[parser.position])'")
        }
        return JSONPath.Query(root: .root, segments: segments)
    }

    var current: Unicode.Scalar? { position < scalars.count ? scalars[position] : nil }

    func peek(_ offset: Int = 1) -> Unicode.Scalar? {
        position + offset < scalars.count ? scalars[position + offset] : nil
    }

    func error(_ message: String, at position: Int? = nil) -> JSONPath.ParseError {
        JSONPath.ParseError(message: message, position: position ?? self.position)
    }

    static func isBlank(_ c: Unicode.Scalar?) -> Bool {
        c == " " || c == "\t" || c == "\n" || c == "\r"
    }

    mutating func skipBlanks() {
        while Self.isBlank(current) { position += 1 }
    }

    static func isNameFirst(_ c: Unicode.Scalar) -> Bool {
        (c >= "A" && c <= "Z") || (c >= "a" && c <= "z") || c == "_" || c.value >= 0x80
    }

    static func isDigit(_ c: Unicode.Scalar?) -> Bool {
        guard let c else { return false }
        return c >= "0" && c <= "9"
    }

    // MARK: Segments

    mutating func parseSegments(inFilter: Bool) throws -> [JSONPath.Segment] {
        var segments: [JSONPath.Segment] = []
        while true {
            let save = position
            skipBlanks()
            guard let c = current else {
                position = save
                return segments
            }
            if c == "[" {
                segments.append(.child(try parseBracketedSelection()))
            } else if c == ".", peek() == "." {
                position += 2
                if current == "[" {
                    segments.append(.descendant(try parseBracketedSelection()))
                } else if current == "*" {
                    position += 1
                    segments.append(.descendant([.wildcard]))
                } else if let n = current, Self.isNameFirst(n) {
                    segments.append(.descendant([.name(parseMemberName(), .none)]))
                } else {
                    throw error("Expected a selector after '..'")
                }
            } else if c == "." {
                position += 1
                if current == "*" {
                    position += 1
                    segments.append(.child([.wildcard]))
                } else if let n = current, Self.isNameFirst(n) {
                    segments.append(.child([.name(parseMemberName(), .none)]))
                } else {
                    throw error("Expected a member name or '*' after '.'")
                }
            } else {
                position = save
                return segments
            }
        }
    }

    mutating func parseMemberName() -> String {
        let start = position
        while let c = current, Self.isNameFirst(c) || Self.isDigit(c) { position += 1 }
        return String(String.UnicodeScalarView(scalars[start..<position]))
    }

    mutating func parseBracketedSelection() throws -> [JSONPath.Selector] {
        position += 1  // [
        var selectors: [JSONPath.Selector] = []
        while true {
            skipBlanks()
            selectors.append(try parseSelector())
            skipBlanks()
            if current == "," {
                position += 1
                continue
            }
            guard current == "]" else { throw error("Expected ',' or ']'") }
            position += 1
            return selectors
        }
    }

    mutating func parseSelector() throws -> JSONPath.Selector {
        guard let c = current else { throw error("Unexpected end of query") }
        switch c {
        case "'", "\"":
            let quote = c
            return .name(try parseStringLiteral(), quote == "'" ? .single : .double)
        case "*":
            position += 1
            return .wildcard
        case "?":
            position += 1
            skipBlanks()
            return .filter(try parseLogicalOr())
        case ":", "-", "0"..."9":
            let start = try parseOptionalInt()
            skipBlanks()
            if current == ":" {
                position += 1
                skipBlanks()
                let end = try parseOptionalInt()
                skipBlanks()
                var step: Int?
                if current == ":" {
                    position += 1
                    skipBlanks()
                    step = try parseOptionalInt()
                }
                return .slice(start: start, end: end, step: step)
            }
            guard let index = start else { throw error("Expected an index") }
            return .index(index)
        default:
            throw error("Invalid selector")
        }
    }

    /// `int = "0" / (["-"] DIGIT1 *DIGIT)` within the I-JSON range.
    mutating func parseOptionalInt() throws -> Int? {
        guard current == "-" || Self.isDigit(current) else { return nil }
        let start = position
        if current == "-" { position += 1 }
        guard let first = current, Self.isDigit(first) else { throw error("Invalid integer") }
        if first == "0" {
            position += 1
            if scalars[start] == "-" { throw error("'-0' is not a valid index", at: start) }
            if Self.isDigit(current) { throw error("Leading zeros are not allowed", at: start) }
            return 0
        }
        while Self.isDigit(current) { position += 1 }
        let text = String(String.UnicodeScalarView(scalars[start..<position]))
        guard let value = Int(text), abs(value) <= Self.maxSafeInteger else {
            throw error("Integer \(text) is out of range", at: start)
        }
        return value
    }

    mutating func parseStringLiteral() throws -> String {
        let quote = current!
        let start = position
        position += 1
        var result = String.UnicodeScalarView()
        while let c = current {
            if c == quote {
                position += 1
                return String(result)
            }
            if c.value < 0x20 { throw error("Control characters must be escaped in string literals") }
            if c == "\\" {
                position += 1
                guard let e = current else { break }
                position += 1
                switch e {
                case "b": result.append("\u{08}")
                case "f": result.append("\u{0C}")
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "/": result.append("/")
                case "\\": result.append("\\")
                case "u":
                    result.append(try parseUnicodeEscape())
                default:
                    if e == quote {
                        result.append(e)
                    } else {
                        throw error("Invalid escape sequence '\\\(e)'", at: position - 2)
                    }
                }
                continue
            }
            result.append(c)
            position += 1
        }
        throw error("Unterminated string literal", at: start)
    }

    mutating func parseHex4() throws -> UInt32 {
        guard position + 4 <= scalars.count else { throw error("Invalid unicode escape") }
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let digit = scalars[position].properties.isASCIIHexDigit ? UInt32(String(scalars[position]), radix: 16) : nil
            else { throw error("Invalid unicode escape") }
            value = value * 16 + digit
            position += 1
        }
        return value
    }

    mutating func parseUnicodeEscape() throws -> Unicode.Scalar {
        let high = try parseHex4()
        if (0xD800...0xDBFF).contains(high) {
            guard current == "\\", peek() == "u" else { throw error("Unpaired surrogate in unicode escape") }
            position += 2
            let low = try parseHex4()
            guard (0xDC00...0xDFFF).contains(low) else { throw error("Invalid low surrogate in unicode escape") }
            return Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00))!
        }
        guard !(0xDC00...0xDFFF).contains(high), let scalar = Unicode.Scalar(high) else {
            throw error("Unpaired surrogate in unicode escape")
        }
        return scalar
    }

    // MARK: Logical expressions

    mutating func parseLogicalOr() throws -> JSONPath.FilterExpression {
        var terms = [try parseLogicalAnd()]
        while true {
            let save = position
            skipBlanks()
            guard current == "|", peek() == "|" else {
                position = save
                break
            }
            position += 2
            skipBlanks()
            terms.append(try parseLogicalAnd())
        }
        return terms.count == 1 ? terms[0] : .or(terms)
    }

    mutating func parseLogicalAnd() throws -> JSONPath.FilterExpression {
        var terms = [try parseBasic()]
        while true {
            let save = position
            skipBlanks()
            guard current == "&", peek() == "&" else {
                position = save
                break
            }
            position += 2
            skipBlanks()
            terms.append(try parseBasic())
        }
        return terms.count == 1 ? terms[0] : .and(terms)
    }

    mutating func parseBasic() throws -> JSONPath.FilterExpression {
        if current == "!" {
            position += 1
            skipBlanks()
            if current == "(" {
                return .not(try parseParenthesized())
            }
            if current == "@" || current == "$" {
                return .exists(try parseFilterQuery(), negated: true)
            }
            if let c = current, c >= "a" && c <= "z" {
                let call = try parseFunction()
                try requireTestable(call)
                return .not(.function(call))
            }
            throw error("Expected '(', a query or a function after '!'")
        }
        if current == "(" {
            return try parseParenthesized()
        }
        let start = position
        let lhs = try parseComparableOrTest()
        let save = position
        skipBlanks()
        if let op = parseComparisonOperator() {
            skipBlanks()
            let left = try comparable(lhs, at: start)
            let rhsStart = position
            let right = try comparable(try parseComparableOrTest(), at: rhsStart)
            return .comparison(left, op, right)
        }
        position = save
        switch lhs {
        case .query(let query): return .exists(query, negated: false)
        case .function(let call):
            try requireTestable(call)
            return .function(call)
        case .literal: throw error("A literal must be compared to something", at: start)
        case .regex: throw error("Unexpected regular expression", at: start)
        }
    }

    mutating func parseParenthesized() throws -> JSONPath.FilterExpression {
        position += 1  // (
        skipBlanks()
        let inner = try parseLogicalOr()
        skipBlanks()
        guard current == ")" else { throw error("Expected ')'") }
        position += 1
        return inner
    }

    mutating func parseComparisonOperator() -> JSONPath.ComparisonOperator? {
        guard let c = current else { return nil }
        let next = peek()
        switch (c, next) {
        case ("=", "="): position += 2; return .equal
        case ("!", "="): position += 2; return .notEqual
        case ("<", "="): position += 2; return .lessOrEqual
        case (">", "="): position += 2; return .greaterOrEqual
        case ("<", _): position += 1; return .less
        case (">", _): position += 1; return .greater
        default: return nil
        }
    }

    /// Validates that an operand can appear in a comparison (literal, singular query, ValueType function).
    func comparable(_ operand: JSONPath.Operand, at position: Int) throws -> JSONPath.Operand {
        switch operand {
        case .literal: return operand
        case .query(let query):
            guard query.isSingular else { throw error("Only singular queries can be compared", at: position) }
            return operand
        case .function(let call):
            guard RFC9535Functions.resultType(of: call) == .value else {
                throw error("Function \(call.name)() does not return a value and cannot be compared", at: position)
            }
            return operand
        case .regex: throw error("Unexpected regular expression", at: position)
        }
    }

    func requireTestable(_ call: JSONPath.FunctionCall) throws {
        guard RFC9535Functions.resultType(of: call) != .value else {
            throw error("Function \(call.name)() returns a value; compare it instead of testing it")
        }
    }

    mutating func parseComparableOrTest() throws -> JSONPath.Operand {
        guard let c = current else { throw error("Unexpected end of filter") }
        switch c {
        case "@", "$":
            return .query(try parseFilterQuery())
        case "'", "\"":
            let start = position
            let value = try parseStringLiteral()
            return .literal(.string(value), raw: String(String.UnicodeScalarView(scalars[start..<position])))
        case "-", "0"..."9":
            return try parseNumber()
        default:
            if consumeKeyword("true") { return .literal(.bool(true), raw: "true") }
            if consumeKeyword("false") { return .literal(.bool(false), raw: "false") }
            if consumeKeyword("null") { return .literal(.null, raw: "null") }
            if c >= "a" && c <= "z" { return .function(try parseFunction()) }
            throw error("Unexpected character '\(c)' in filter")
        }
    }

    mutating func consumeKeyword(_ keyword: String) -> Bool {
        let target = Array(keyword.unicodeScalars)
        guard position + target.count <= scalars.count, Array(scalars[position..<position + target.count]) == target
        else { return false }
        // Must not continue as a function name (e.g. `nullable(...)`).
        if let next = position + target.count < scalars.count ? scalars[position + target.count] : nil,
            (next >= "a" && next <= "z") || next == "_" || Self.isDigit(next) || next == "("
        {
            return false
        }
        position += target.count
        return true
    }

    mutating func parseFilterQuery() throws -> JSONPath.Query {
        let root: JSONPath.Query.Root = current == "$" ? .root : .current
        position += 1
        return JSONPath.Query(root: root, segments: try parseSegments(inFilter: true))
    }

    /// `number = (int / "-0") [ frac ] [ exp ]`
    mutating func parseNumber() throws -> JSONPath.Operand {
        let start = position
        if current == "-" { position += 1 }
        guard let first = current, Self.isDigit(first) else { throw error("Invalid number", at: start) }
        if first == "0" {
            position += 1
            if Self.isDigit(current) { throw error("Leading zeros are not allowed", at: start) }
        } else {
            while Self.isDigit(current) { position += 1 }
        }
        var isInteger = true
        if current == "." {
            isInteger = false
            position += 1
            guard Self.isDigit(current) else { throw error("Invalid fraction", at: start) }
            while Self.isDigit(current) { position += 1 }
        }
        if current == "e" || current == "E" {
            isInteger = false
            position += 1
            if current == "+" || current == "-" { position += 1 }
            guard Self.isDigit(current) else { throw error("Invalid exponent", at: start) }
            while Self.isDigit(current) { position += 1 }
        }
        let raw = String(String.UnicodeScalarView(scalars[start..<position]))
        if isInteger, raw != "-0", let int = Int(raw) { return .literal(.integer(int), raw: raw) }
        guard let double = Double(raw) else { throw error("Invalid number", at: start) }
        return .literal(.number(double), raw: raw)
    }

    // MARK: Functions

    mutating func parseFunction() throws -> JSONPath.FunctionCall {
        let start = position
        while let c = current, (c >= "a" && c <= "z") || c == "_" || Self.isDigit(c) { position += 1 }
        let name = String(String.UnicodeScalarView(scalars[start..<position]))
        guard current == "(" else { throw error("Expected '(' after function name '\(name)'", at: start) }
        position += 1
        skipBlanks()
        var arguments: [JSONPath.FunctionArgument] = []
        if current != ")" {
            while true {
                skipBlanks()
                arguments.append(try parseFunctionArgument())
                skipBlanks()
                if current == "," {
                    position += 1
                    continue
                }
                break
            }
        }
        skipBlanks()
        guard current == ")" else { throw error("Expected ')' to close \(name)(") }
        position += 1
        let call = JSONPath.FunctionCall(name: name, arguments: arguments, style: .rfc9535)
        try RFC9535Functions.typeCheck(call, at: start)
        return call
    }

    mutating func parseFunctionArgument() throws -> JSONPath.FunctionArgument {
        let start = position
        // A literal, query or function followed by ',' or ')' is a plain argument;
        // anything else is a logical expression.
        if let operand = try? parseComparableOrTest() {
            let afterOperand = position
            skipBlanks()
            if current == "," || current == ")" {
                switch operand {
                case .literal(let value, let raw): return .literal(value, raw: raw)
                case .query(let query): return .query(query)
                case .function(let call): return .function(call)
                case .regex: break
                }
            }
            position = afterOperand
        }
        position = start
        return .logical(try parseLogicalOr())
    }
}
