/// Parses the Jayway JsonPath dialect (as implemented by Jayway JsonPath, SMJJSONPath and Sextant).
///
/// Notable differences from RFC 9535: paths may omit the leading `$`, dot-notation names may contain
/// `-`, `@`, `:` and start with digits, filters are written `[?(...)]`, Jayway operators
/// (`=~`, `in`, `nin`, `contains`, `size`, `empty`, `anyof`, ...) and path functions
/// (`.length()`, `.avg()`, `.concat(...)`, ...) are supported.
struct JaywayParser {
    let scalars: [Unicode.Scalar]
    var position = 0
    /// Offset added to reported positions (when the input was prefixed with `$.`).
    let reportedOffset: Int

    static func parse(_ text: String) throws -> JSONPath.Query {
        var trimmed = Substring(text)
        while let last = trimmed.last, last.isWhitespace { trimmed.removeLast() }
        while let first = trimmed.first, first.isWhitespace { trimmed.removeFirst() }
        guard !trimmed.isEmpty else { throw JSONPath.ParseError(message: "Path must start with $ or @", position: 0) }
        var source = String(trimmed)
        var offset = 0
        if source.first != "$" && source.first != "@" {
            source = "$." + source
            offset = -2
        }
        if source.hasSuffix(".") {
            throw JSONPath.ParseError(message: "Path must not end with a '.' or '..'", position: source.count + offset)
        }
        var parser = JaywayParser(scalars: Array(source.unicodeScalars), reportedOffset: offset)
        let query = try parser.parsePath(context: .topLevel)
        guard parser.position == parser.scalars.count else {
            throw parser.tokenError(at: parser.position)
        }
        return query
    }

    enum Context {
        case topLevel
        case filter
        case argument
    }

    init(scalars: [Unicode.Scalar], reportedOffset: Int = 0) {
        self.scalars = scalars
        self.reportedOffset = reportedOffset
    }

    // MARK: Helpers

    var current: Unicode.Scalar? { position < scalars.count ? scalars[position] : nil }

    func peek(_ offset: Int = 1) -> Unicode.Scalar? {
        position + offset < scalars.count ? scalars[position + offset] : nil
    }

    func error(_ message: String, at position: Int? = nil) -> JSONPath.ParseError {
        JSONPath.ParseError(message: message, position: max(0, (position ?? self.position) + reportedOffset))
    }

    func tokenError(at position: Int) -> JSONPath.ParseError {
        error("Could not parse token starting at position \(max(0, position + reportedOffset)).", at: position)
    }

    mutating func skipWhitespace() {
        while let c = current, c.properties.isWhitespace { position += 1 }
    }

    mutating func consume(_ string: String) -> Bool {
        let target = Array(string.unicodeScalars)
        guard position + target.count <= scalars.count else { return false }
        for (offset, scalar) in target.enumerated() where scalars[position + offset] != scalar { return false }
        position += target.count
        return true
    }

    func text(_ range: Range<Int>) -> String {
        var string = ""
        string.unicodeScalars.append(contentsOf: scalars[range])
        return string
    }

    static func isNameTerminator(_ c: Unicode.Scalar, context: Context) -> Bool {
        switch c {
        case ".", "[", "(": return true
        case " ", "\t", "\n", "\r": return true
        default: break
        }
        guard context != .topLevel else { return c == ")" || c == "]" || c == "," }
        return "()]=!<>&|,~'\"".unicodeScalars.contains(c)
    }

    // MARK: Paths

    mutating func parsePath(context: Context) throws -> JSONPath.Query {
        let root: JSONPath.Query.Root
        switch current {
        case "$": root = .root
        case "@": root = .current
        default: throw error("Path must start with $ or @")
        }
        position += 1
        var segments: [JSONPath.Segment] = []
        var afterBracket = false

        loop: while let c = current {
            let tokenStart = position
            switch c {
            case ".":
                afterBracket = false
                if peek() == "." {
                    position += 2
                    if current == "." || current == nil {
                        throw error("Path must not end with a '.' or '..'", at: tokenStart)
                    }
                    if current == "[" {
                        segments.append(.descendant(try parseBracket(context: context)))
                        afterBracket = true
                    } else if current == "*" {
                        position += 1
                        segments.append(.descendant([.wildcard]))
                    } else {
                        let name = try parseDotName(context: context, tokenStart: tokenStart)
                        if current == "(" { throw tokenError(at: tokenStart) }
                        segments.append(.descendant([.name(name, .none)]))
                    }
                    continue loop
                }
                position += 1
                guard let next = current else {
                    throw error("Path must not end with a '.' or '..'", at: tokenStart)
                }
                if next == "[" {
                    segments.append(.child(try parseBracket(context: context)))
                    afterBracket = true
                } else if next == "*" {
                    position += 1
                    segments.append(.child([.wildcard]))
                } else {
                    let name = try parseDotName(context: context, tokenStart: tokenStart)
                    if current == "(" {
                        segments.append(.function(try parseFunctionCall(name: name, tokenStart: tokenStart)))
                    } else {
                        segments.append(.child([.name(name, .none)]))
                    }
                }
            case "[":
                segments.append(.child(try parseBracket(context: context)))
                afterBracket = true
                continue loop
            default:
                // Jayway accepts a property directly after a bracket: `$..[*]foo`.
                if afterBracket, !Self.isNameTerminator(c, context: context), c != "*" {
                    afterBracket = false
                    let name = try parseDotName(context: context, tokenStart: tokenStart)
                    if current == "(" {
                        segments.append(.function(try parseFunctionCall(name: name, tokenStart: tokenStart)))
                    } else {
                        segments.append(.child([.name(name, .none)]))
                    }
                    continue loop
                }
                if context == .topLevel {
                    throw tokenError(at: tokenStart)
                }
                break loop
            }
        }
        if context == .topLevel, position < scalars.count { throw tokenError(at: position) }
        return JSONPath.Query(root: root, segments: segments)
    }

    mutating func parseDotName(context: Context, tokenStart: Int) throws -> String {
        let start = position
        while let c = current, !Self.isNameTerminator(c, context: context) { position += 1 }
        guard position > start else { throw tokenError(at: tokenStart) }
        if context == .topLevel, let c = current, c.properties.isWhitespace {
            throw error("Use bracket notation ['my prop'] if your property contains blank characters.", at: position)
        }
        return text(start..<position)
    }

    mutating func parseFunctionCall(name: String, tokenStart: Int) throws -> JSONPath.FunctionCall {
        position += 1  // (
        var arguments: [JSONPath.FunctionArgument] = []
        skipWhitespace()
        if current == ")" {
            position += 1
            return JSONPath.FunctionCall(name: name, arguments: [], style: .jayway)
        }
        while true {
            skipWhitespace()
            guard current != nil else { throw error("Function call is not closed", at: tokenStart) }
            let operand = try parseValue()
            switch operand {
            case .literal(let value, let raw): arguments.append(.literal(value, raw: raw))
            case .query(let query): arguments.append(.query(query))
            case .function(let call): arguments.append(.function(call))
            case .regex: throw tokenError(at: tokenStart)
            }
            skipWhitespace()
            if current == "," {
                position += 1
                continue
            }
            if current == ")" {
                position += 1
                return JSONPath.FunctionCall(name: name, arguments: arguments, style: .jayway)
            }
            throw error("Arguments to function '\(name)' must be separated by commas", at: position)
        }
    }

    // MARK: Brackets

    mutating func parseBracket(context: Context) throws -> [JSONPath.Selector] {
        let tokenStart = position
        position += 1  // [
        skipWhitespace()
        guard let c = current else { throw tokenError(at: tokenStart) }
        var selectors: [JSONPath.Selector] = []
        switch c {
        case "?":
            position += 1
            skipWhitespace()
            // Jayway writes `[?(expr)]`; RFC 9535 style `[?expr]` is accepted too.
            let expression = try parseFilterExpression()
            selectors = [.filter(expression)]
        case "*":
            position += 1
            selectors = [.wildcard]
        case "'", "\"":
            while true {
                skipWhitespace()
                guard let quote = current, quote == "'" || quote == "\"" else { throw tokenError(at: tokenStart) }
                let name = try parseQuotedString()
                selectors.append(.name(name, quote == "'" ? .single : .double))
                skipWhitespace()
                if current == "," {
                    position += 1
                    continue
                }
                break
            }
        case "-", ":", "0"..."9":
            let start = position
            while let c = current, c != "]" { position += 1 }
            let body = text(start..<position)
            selectors = try parseIndices(body, tokenStart: tokenStart)
        default:
            throw tokenError(at: tokenStart)
        }
        skipWhitespace()
        guard current == "]" else { throw tokenError(at: tokenStart) }
        position += 1
        return selectors
    }

    func parseIndices(_ body: String, tokenStart: Int) throws -> [JSONPath.Selector] {
        if body.contains(":") {
            let parts = body.split(separator: ":", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters()
            }
            guard parts.count <= 3 else { throw tokenError(at: tokenStart) }
            func number(_ s: String) throws -> Int? {
                if s.isEmpty { return nil }
                guard !s.hasPrefix("+"), let value = Int(s) else { throw tokenError(at: tokenStart) }
                return value
            }
            return [
                .slice(
                    start: try number(parts[0]), end: try number(parts.count > 1 ? parts[1] : ""),
                    step: try number(parts.count > 2 ? parts[2] : ""))
            ]
        }
        let items = body.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters() }
        return try items.map { item in
            guard !item.isEmpty, !item.hasPrefix("+"), let index = Int(item) else { throw tokenError(at: tokenStart) }
            return .index(index)
        }
    }

    mutating func parseQuotedString() throws -> String {
        let quote = current!
        let start = position
        position += 1
        var result = String.UnicodeScalarView()
        while let c = current {
            if c == quote {
                position += 1
                return String(result)
            }
            if c == "\\" {
                position += 1
                guard let escaped = current else { break }
                position += 1
                switch escaped {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "b": result.append("\u{08}")
                case "f": result.append("\u{0C}")
                case "u":
                    func hex4() -> UInt32? {
                        guard position + 4 <= scalars.count,
                            scalars[position..<position + 4].allSatisfy({ $0.properties.isASCIIHexDigit })
                        else { return nil }
                        defer { position += 4 }
                        return UInt32(text(position..<position + 4), radix: 16)
                    }
                    guard let high = hex4() else { throw tokenError(at: start) }
                    if (0xD800...0xDBFF).contains(high) {
                        // UTF-16 surrogate pair: \uD834\uDD1E
                        guard current == "\\", peek() == "u" else { throw tokenError(at: start) }
                        position += 2
                        guard let low = hex4(), (0xDC00...0xDFFF).contains(low) else { throw tokenError(at: start) }
                        result.append(Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00))!)
                    } else {
                        guard let scalar = Unicode.Scalar(high) else { throw tokenError(at: start) }
                        result.append(scalar)
                    }
                default: result.append(escaped)
                }
                continue
            }
            result.append(c)
            position += 1
        }
        throw error("String literal is not closed", at: start)
    }

    // MARK: Filters

    mutating func parseFilterExpression() throws -> JSONPath.FilterExpression {
        try parseOr()
    }

    mutating func parseOr() throws -> JSONPath.FilterExpression {
        var terms = [try parseAnd()]
        while true {
            skipWhitespace()
            guard consume("||") else { break }
            terms.append(try parseAnd())
        }
        return terms.count == 1 ? terms[0] : .or(terms)
    }

    mutating func parseAnd() throws -> JSONPath.FilterExpression {
        var terms = [try parseUnary()]
        while true {
            skipWhitespace()
            guard consume("&&") else { break }
            terms.append(try parseUnary())
        }
        return terms.count == 1 ? terms[0] : .and(terms)
    }

    mutating func parseUnary() throws -> JSONPath.FilterExpression {
        skipWhitespace()
        let start = position
        if current == "!", peek() != "=" {
            position += 1
            skipWhitespace()
            if current == "@" || current == "$" {
                let query = try parsePath(context: .filter)
                return .exists(query, negated: true)
            }
            if current == "(" {
                return .not(try parseUnary())
            }
            throw error("Unexpected character after '!'", at: start)
        }
        if current == "(" {
            position += 1
            let inner = try parseOr()
            skipWhitespace()
            guard current == ")" else { throw error("Expected ')'", at: position) }
            position += 1
            return inner
        }
        return try parseRelational()
    }

    mutating func parseRelational() throws -> JSONPath.FilterExpression {
        skipWhitespace()
        let start = position
        let lhs = try parseValue()
        skipWhitespace()
        guard let op = parseOperator() else {
            switch lhs {
            case .query(let query): return .exists(query, negated: false)
            case .function(let call) where call.style == .rfc9535: return .function(call)
            default: throw error("Expected a comparison operator", at: start)
            }
        }
        skipWhitespace()
        let rhs = try parseValue()
        return .comparison(lhs, op, rhs)
    }

    mutating func parseOperator() -> JSONPath.ComparisonOperator? {
        for symbol in ["===", "!==", "==", "!=", "<=", ">=", "=~", "<", ">"] where consume(symbol) {
            return JSONPath.ComparisonOperator(rawValue: symbol)
        }
        // Word operators: letters followed by a non-letter.
        let start = position
        while let c = current, c.properties.isAlphabetic { position += 1 }
        let word = text(start..<position).uppercased()
        if let op = JSONPath.ComparisonOperator.wordOperators[word],
            current.map({ !$0.properties.isAlphabetic }) ?? true
        {
            return op
        }
        position = start
        return nil
    }

    mutating func parseValue() throws -> JSONPath.Operand {
        skipWhitespace()
        let start = position
        guard let c = current else { throw error("Expected a value", at: start) }
        switch c {
        case "@", "$":
            return .query(try parsePath(context: .filter))
        case "'", "\"":
            let value = try parseQuotedString()
            return .literal(.string(value), raw: text(start..<position))
        case "/":
            return try parseRegex()
        case "[", "{":
            return try parseJSONLiteral()
        case "-", "0"..."9":
            position += 1
            while let d = current,
                d.properties.numericType != nil || d == "." || d == "e" || d == "E"
                    || ((d == "+" || d == "-") && (scalars[position - 1] == "e" || scalars[position - 1] == "E"))
            {
                position += 1
            }
            let raw = text(start..<position)
            if let int = Int(raw) { return .literal(.integer(int), raw: raw) }
            guard let double = Double(raw) else { throw error("Invalid number '\(raw)'", at: start) }
            return .literal(.number(double), raw: raw)
        default:
            if consume("true") { return .literal(.bool(true), raw: "true") }
            if consume("false") { return .literal(.bool(false), raw: "false") }
            if consume("null") { return .literal(.null, raw: "null") }
            // RFC 9535 style function call: name(args)
            let nameStart = position
            while let d = current,
                d.properties.isAlphabetic || d == "_" || (position > nameStart && d.properties.numericType != nil)
            {
                position += 1
            }
            if position > nameStart, current == "(" {
                let name = text(nameStart..<position)
                return .function(try parseRFCFunction(name: name, start: nameStart))
            }
            position = start
            throw error("Unexpected token in filter", at: start)
        }
    }

    mutating func parseRFCFunction(name: String, start: Int) throws -> JSONPath.FunctionCall {
        position += 1  // (
        var arguments: [JSONPath.FunctionArgument] = []
        skipWhitespace()
        if current == ")" {
            position += 1
            return JSONPath.FunctionCall(name: name, arguments: [], style: .rfc9535)
        }
        while true {
            skipWhitespace()
            let argumentStart = position
            // Try a plain value first; fall back to a logical expression.
            if let operand = try? parseValue() {
                skipWhitespace()
                if current == "," || current == ")" {
                    switch operand {
                    case .literal(let v, let raw): arguments.append(.literal(v, raw: raw))
                    case .query(let q): arguments.append(.query(q))
                    case .function(let f): arguments.append(.function(f))
                    case .regex: throw error("Unexpected regular expression", at: argumentStart)
                    }
                } else {
                    position = argumentStart
                    arguments.append(.logical(try parseOr()))
                }
            } else {
                position = argumentStart
                arguments.append(.logical(try parseOr()))
            }
            skipWhitespace()
            if current == "," {
                position += 1
                continue
            }
            if current == ")" {
                position += 1
                return JSONPath.FunctionCall(name: name, arguments: arguments, style: .rfc9535)
            }
            throw error("Expected ',' or ')' in function call", at: position)
        }
    }

    mutating func parseRegex() throws -> JSONPath.Operand {
        let start = position
        position += 1
        var pattern = ""
        while let c = current, c != "/" {
            if c == "\\", let next = peek() {
                if next == "/" {
                    pattern.unicodeScalars.append("/")
                } else {
                    pattern.unicodeScalars.append(c)
                    pattern.unicodeScalars.append(next)
                }
                position += 2
                continue
            }
            pattern.unicodeScalars.append(c)
            position += 1
        }
        guard current == "/" else { throw error("Regular expression is not closed", at: start) }
        position += 1
        let flagsStart = position
        while let c = current, c.properties.isAlphabetic { position += 1 }
        return .regex(pattern: pattern, flags: text(flagsStart..<position))
    }

    /// A JSON array or object literal; single-quoted strings are accepted.
    mutating func parseJSONLiteral() throws -> JSONPath.Operand {
        let start = position
        var depth = 0
        var quote: Unicode.Scalar?
        while let c = current {
            position += 1
            if let q = quote {
                if c == "\\" {
                    position += 1
                } else if c == q {
                    quote = nil
                }
                continue
            }
            switch c {
            case "'", "\"": quote = c
            case "[", "{": depth += 1
            case "]", "}":
                depth -= 1
                if depth == 0 {
                    let raw = text(start..<position)
                    guard let value = try? JSONValue(parsing: Self.normalizeQuotes(raw)) else {
                        throw error("Invalid JSON literal \(raw)", at: start)
                    }
                    return .literal(value, raw: raw)
                }
            default: break
            }
        }
        throw error("JSON literal is not closed", at: start)
    }

    /// Converts single-quoted JSON strings to double-quoted ones.
    static func normalizeQuotes(_ raw: String) -> String {
        var output = ""
        var inSingle = false
        var inDouble = false
        var escaped = false
        for c in raw {
            if escaped {
                if inSingle, c == "'" { output.append("'") } else { output.append("\\"); output.append(c) }
                escaped = false
                continue
            }
            if c == "\\", inSingle || inDouble {
                escaped = true
                continue
            }
            if c == "'" && !inDouble {
                inSingle.toggle()
                output.append("\"")
            } else if c == "\"" && inSingle {
                output += "\\\""
            } else {
                if c == "\"" { inDouble.toggle() }
                output.append(c)
            }
        }
        return output
    }
}

extension Substring {
    func trimmingCharacters() -> String {
        var s = self
        while let f = s.first, f.isWhitespace { s.removeFirst() }
        while let l = s.last, l.isWhitespace { s.removeLast() }
        return String(s)
    }
}
