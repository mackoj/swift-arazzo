/// Evaluates queries with Jayway JsonPath semantics.
///
/// Key differences from RFC 9535:
/// - A filter applied to an *object* tests the object itself; applied to an array it tests the elements.
/// - Comparisons are loose (`'1' == 1`), numeric strings compare as numbers, and Jayway operators
///   (`in`, `nin`, `contains`, `size`, `empty`, `subsetof`, `anyof`, `noneof`, `type`, `exists`, `=~`) are available.
/// - A relation whose path does not resolve is an *error*, which makes the whole filter fail.
/// - Path functions (`.length()`, `.avg()`, ...) compute values; failures make the query fail.
struct JaywayEvaluator {
    let root: JSONValue

    typealias Node = JSONPath.Node

    func evaluate(_ query: JSONPath.Query, current: JSONValue) throws -> [Node] {
        let start = query.root == .root ? root : current
        var results: [Node] = []
        try run(query.segments[...], value: start, location: .root, upstreamDefinite: true) { results.append($0) }
        return results
    }

    // MARK: - Segments

    func run(
        _ segments: ArraySlice<JSONPath.Segment>, value: JSONValue, location: NormalizedPath?,
        upstreamDefinite: Bool, emit: (Node) throws -> Void
    ) throws {
        guard let segment = segments.first else {
            try emit(Node(location: location, value: value))
            return
        }
        let rest = segments.dropFirst()
        switch segment {
        case .child(let selectors):
            try applyChild(
                selectors, value: value, location: location, upstreamDefinite: upstreamDefinite,
                rest: rest, emit: emit)
        case .descendant(let selectors):
            try scan(selectors, value: value, location: location, rest: rest, emit: emit)
        case .function(let call):
            let result = try JaywayFunctions.invoke(call, input: value, evaluator: self)
            try run(rest, value: result, location: nil, upstreamDefinite: upstreamDefinite, emit: emit)
        }
    }

    func applyChild(
        _ selectors: [JSONPath.Selector], value: JSONValue, location: NormalizedPath?, upstreamDefinite: Bool,
        rest: ArraySlice<JSONPath.Segment>, emit: (Node) throws -> Void
    ) throws {
        let definite = upstreamDefinite && JSONPath.Segment.child(selectors).isDefinite
        func next(_ child: JSONValue, _ element: NormalizedPath.Element?) throws {
            try run(
                rest, value: child, location: element.flatMap { location?.appending($0) } ?? location,
                upstreamDefinite: definite, emit: emit)
        }
        for selector in selectors {
            switch selector {
            case .name(let name, _):
                if let child = value.member(name) {
                    try next(child, .name(name))
                }
            case .wildcard:
                switch value {
                case .object(let object):
                    for (key, child) in object { try next(child, .name(key)) }
                case .array(let array):
                    for (index, child) in array.enumerated() { try next(child, .index(index)) }
                default: break
                }
            case .index(let index):
                if case .array(let array) = value {
                    let resolved = index < 0 ? array.count + index : index
                    if array.indices.contains(resolved) { try next(array[resolved], .index(resolved)) }
                }
            case .slice(let start, let end, let step):
                if case .array(let array) = value {
                    for index in Self.sliceIndices(count: array.count, start: start, end: end, step: step) {
                        try next(array[index], .index(index))
                    }
                }
            case .filter(let expression):
                switch value {
                case .object:
                    if accept(expression, current: value) {
                        try run(rest, value: value, location: location, upstreamDefinite: false, emit: emit)
                    }
                case .array(let array):
                    for (index, child) in array.enumerated() where accept(expression, current: child) {
                        try run(
                            rest, value: child, location: location?.appending(.index(index)), upstreamDefinite: false,
                            emit: emit)
                    }
                default:
                    if upstreamDefinite {
                        throw JSONPath.EvaluationError("Filter can not be applied to primitives.")
                    }
                    if accept(expression, current: value) {
                        try run(rest, value: value, location: location, upstreamDefinite: false, emit: emit)
                    }
                }
            }
        }
    }

    /// Jayway slice semantics: negative bounds count from the end, bounds are clamped, a step of
    /// 0 or none means 1.
    static func sliceIndices(count: Int, start: Int?, end: Int?, step: Int?) -> [Int] {
        let step = (step == nil || step == 0) ? 1 : step!
        if step > 0 {
            var from = start ?? 0
            var to = end ?? count
            if from < 0 { from = max(0, count + from) }
            if to < 0 { to = max(0, count + to) }
            from = min(from, count)
            to = min(to, count)
            guard from < to else { return [] }
            return Array(stride(from: from, to: to, by: step))
        } else {
            var from = start ?? (count - 1)
            var to = end ?? -count - 1
            if from < 0 { from = count + from }
            if to < 0 { to = count + to }
            from = min(from, count - 1)
            to = max(to, -1)
            guard from > to else { return [] }
            return Array(stride(from: from, to: to, by: step))
        }
    }

    // MARK: - Deep scan (`..`)

    func scan(
        _ selectors: [JSONPath.Selector], value: JSONValue, location: NormalizedPath?,
        rest: ArraySlice<JSONPath.Segment>, emit: (Node) throws -> Void
    ) throws {
        let isFilter: Bool
        if selectors.count == 1, case .filter = selectors[0] { isFilter = true } else { isFilter = false }

        func matches(_ node: JSONValue) -> Bool {
            if selectors.count == 1 {
                switch selectors[0] {
                case .name(let name, _):
                    if case .object = node { return node.member(name) != nil }
                    return false
                case .wildcard: return true
                case .index, .slice:
                    if case .array = node { return true }
                    return false
                case .filter(let expression): return accept(expression, current: node)
                }
            }
            if selectors.allSatisfy({ if case .name = $0 { true } else { false } }) {
                if case .object = node { return true }
                return false
            }
            if case .array = node { return true }
            return false
        }

        func walk(_ node: JSONValue, _ location: NormalizedPath?) throws {
            guard node.isStructured else { return }
            if matches(node) {
                try applyChild(
                    selectors, value: node, location: location, upstreamDefinite: false, rest: rest, emit: emit)
            }
            switch node {
            case .object(let object):
                for (key, child) in object where child.isStructured { try walk(child, location?.appending(.name(key))) }
                if isFilter {
                    for (key, child) in object where !child.isStructured && matches(child) {
                        try run(
                            rest, value: child, location: location?.appending(.name(key)), upstreamDefinite: false,
                            emit: emit)
                    }
                }
            case .array(let array):
                for (index, child) in array.enumerated() where child.isStructured {
                    try walk(child, location?.appending(.index(index)))
                }
                if isFilter {
                    for (index, child) in array.enumerated() where !child.isStructured && matches(child) {
                        try run(
                            rest, value: child, location: location?.appending(.index(index)), upstreamDefinite: false,
                            emit: emit)
                    }
                }
            default:
                break
            }
        }
        try walk(value, location)
    }

    // MARK: - Filters

    enum Truth {
        case `true`, `false`, error

        var inverted: Truth {
            switch self {
            case .true: .false
            case .false: .true
            case .error: .error
            }
        }
    }

    func accept(_ expression: JSONPath.FilterExpression, current: JSONValue) -> Bool {
        apply(expression, current: current) == .true
    }

    func apply(_ expression: JSONPath.FilterExpression, current: JSONValue) -> Truth {
        switch expression {
        case .or(let terms):
            for term in terms {
                let result = apply(term, current: current)
                if result != .false { return result }
            }
            return .false
        case .and(let terms):
            for term in terms {
                let result = apply(term, current: current)
                if result != .true { return result }
            }
            return .true
        case .not(let inner):
            return apply(inner, current: current).inverted
        case .exists(let query, let negated):
            let exists = self.exists(query, current: current)
            return (exists != negated) ? .true : .false
        case .function(let call):
            guard let value = try? RFC9535Functions.evaluateLogical(call, current: current, root: root, jayway: self)
            else { return .error }
            return value ? .true : .false
        case .comparison(let lhs, let op, let rhs):
            if op == .exists {
                guard case .query(let query) = lhs else { return .error }
                guard let expected = valueNode(rhs, current: current), case .bool(let flag) = expected else {
                    return .error
                }
                return (self.exists(query, current: current) == flag) ? .true : .false
            }
            guard let left = valueNode(lhs, current: current), let right = valueNode(rhs, current: current) else {
                return .error
            }
            return JaywayValue.evaluate(left, op, right)
        }
    }

    func exists(_ query: JSONPath.Query, current: JSONValue) -> Bool {
        guard let nodes = try? evaluate(query, current: current) else { return false }
        return !nodes.isEmpty
    }

    /// Resolves an operand: literals as-is, paths to their value (definite) or the array of values
    /// (indefinite). `nil` means "does not resolve" (an error for the relation).
    func valueNode(_ operand: JSONPath.Operand, current: JSONValue) -> JaywayValue? {
        switch operand {
        case .literal(let value, _):
            return JaywayValue(value)
        case .regex(let pattern, let flags):
            return .pattern(pattern: pattern, flags: flags)
        case .query(let query):
            guard let value = resolve(query, current: current) else { return nil }
            return JaywayValue(value)
        case .function(let call):
            guard
                let value = (try? RFC9535Functions.evaluateValue(call, current: current, root: root, jayway: self))
                    ?? nil
            else { return nil }
            return JaywayValue(value)
        }
    }

    func resolve(_ query: JSONPath.Query, current: JSONValue) -> JSONValue? {
        guard let nodes = try? evaluate(query, current: current) else { return nil }
        if query.isDefinite { return nodes.first?.value }
        return .array(nodes.map(\.value))
    }
}

/// A Jayway "value node": the typed view used by filter comparisons.
enum JaywayValue {
    case string(String)
    case number(Double, description: String)
    case bool(Bool)
    case null
    case json(JSONValue)
    case pattern(pattern: String, flags: String)

    init(_ value: JSONValue) {
        switch value {
        case .null: self = .null
        case .bool(let b): self = .bool(b)
        case .integer(let i): self = .number(Double(i), description: String(i))
        case .number(let d): self = .number(d, description: JaywayValue.describe(d))
        case .string(let s): self = .string(s)
        case .array, .object: self = .json(value)
        }
    }

    static func describe(_ double: Double) -> String {
        if double.rounded() == double, abs(double) < 1e15 { return String(Int(double)) + ".0" }
        return String(double)
    }

    var typeName: String {
        switch self {
        case .string: "string"
        case .number: "number"
        case .bool: "bool"
        case .null: "null"
        case .json: "json"
        case .pattern: "pattern"
        }
    }

    var numericValue: Double? {
        switch self {
        case .number(let d, _): d
        case .string(let s): Double(s.trimmingWhitespace()).flatMap { $0.isFinite ? $0 : nil }
        case .bool(let b): b ? 1 : 0
        default: nil
        }
    }

    var literalValue: String? {
        switch self {
        case .string(let s): s
        case .number(_, let description): description
        case .bool(let b): b ? "true" : "false"
        case .json(let value): value.canonicalJSONString
        case .null, .pattern: nil
        }
    }

    var jsonArray: [JSONValue]? {
        if case .json(.array(let array)) = self { return array }
        return nil
    }

    func equals(_ other: JaywayValue) -> Bool {
        if let a = numericValue, let b = other.numericValue { return a == b }
        return literalValue == other.literalValue
    }

    func compare(_ other: JaywayValue) -> Int? {
        if let a = numericValue, let b = other.numericValue {
            return a == b ? 0 : (a < b ? -1 : 1)
        }
        if let a = literalValue, let b = other.literalValue {
            return a == b ? 0 : (Array(a.utf8).lexicographicallyPrecedes(b.utf8) ? -1 : 1)
        }
        return literalValue == other.literalValue ? 0 : nil
    }

    static func evaluate(
        _ left: JaywayValue, _ op: JSONPath.ComparisonOperator, _ right: JaywayValue
    )
        -> JaywayEvaluator.Truth
    {
        func truth(_ value: Bool) -> JaywayEvaluator.Truth { value ? .true : .false }
        func contains(_ array: [JSONValue], _ value: JaywayValue) -> Bool {
            array.contains { JaywayValue($0).equals(value) }
        }
        switch op {
        case .equal: return truth(left.equals(right))
        case .notEqual: return truth(!left.equals(right))
        case .strictEqual: return truth(left.equals(right) && left.typeName == right.typeName)
        case .strictNotEqual: return truth(!(left.equals(right) && left.typeName == right.typeName))
        case .less: return truth(left.compare(right) == -1)
        case .lessOrEqual: return truth(left.compare(right).map { $0 <= 0 } ?? false)
        case .greater: return truth(left.compare(right) == 1)
        case .greaterOrEqual: return truth(left.compare(right).map { $0 >= 0 } ?? false)
        case .regex:
            let (patternValue, subject): (JaywayValue, JaywayValue)
            if case .pattern = left {
                (patternValue, subject) = (left, right)
            } else {
                (patternValue, subject) = (right, left)
            }
            guard case .pattern(let pattern, let flags) = patternValue else { return .error }
            guard let regex = JaywayRegex.compile(pattern, flags: flags) else { return .error }
            guard let text = subject.regexSubject else { return .false }
            return truth((try? regex.firstMatch(in: text)) != nil)
        case .in:
            guard let array = right.jsonArray else { return .false }
            return truth(contains(array, left))
        case .nin:
            guard let array = right.jsonArray else { return .true }
            return truth(!contains(array, left))
        case .contains:
            if case .string(let l) = left, case .string(let r) = right { return truth(l.contains(r)) }
            if let array = left.jsonArray { return truth(contains(array, right)) }
            return .false
        case .all:
            guard let l = left.jsonArray, let r = right.jsonArray else { return .false }
            return truth(r.allSatisfy { contains(l, JaywayValue($0)) })
        case .subsetOf:
            guard let l = left.jsonArray, let r = right.jsonArray else { return .false }
            return truth(l.allSatisfy { contains(r, JaywayValue($0)) })
        case .anyOf:
            guard let l = left.jsonArray, let r = right.jsonArray else { return .false }
            return truth(l.contains { contains(r, JaywayValue($0)) })
        case .noneOf:
            guard let l = left.jsonArray, let r = right.jsonArray else { return .false }
            return truth(!l.contains { contains(r, JaywayValue($0)) })
        case .size:
            guard case .number(let expected, _) = right else { return .false }
            return truth(left.size == Int(expected))
        case .empty:
            guard case .bool(let flag) = right else { return .false }
            guard left.literalValue != nil else { return .false }
            let isEmpty = left.size == 0
            return truth(isEmpty == flag)
        case .type:
            if case .string(let name) = right { return truth(left.typeName == name) }
            return truth(left.typeName == right.typeName)
        case .exists:
            return .error  // handled by the evaluator
        }
    }

    var size: Int? {
        switch self {
        case .string(let s): s.unicodeScalars.count
        case .json(.array(let a)): a.count
        case .json(.object(let o)): o.count
        default: nil
        }
    }

    var regexSubject: String? {
        switch self {
        case .string(let s): s
        case .number(_, let description): description
        case .bool(let b): b ? "true" : "false"
        case .json(let value): value.jsonString
        case .null, .pattern: nil
        }
    }
}

extension JSONValue {
    /// Compact JSON with object keys sorted, for order-insensitive comparisons.
    var canonicalJSONString: String {
        switch self {
        case .object(let object):
            return "{"
                + object.keys.sorted().map { JSONValue.string($0).jsonString + ":" + object[$0]!.canonicalJSONString }
                .joined(separator: ",") + "}"
        case .array(let array):
            return "[" + array.map(\.canonicalJSONString).joined(separator: ",") + "]"
        default:
            return jsonString
        }
    }
}

extension String {
    func trimmingWhitespace() -> String {
        var s = Substring(self)
        while let f = s.first, f.isWhitespace { s.removeFirst() }
        while let l = s.last, l.isWhitespace { s.removeLast() }
        return String(s)
    }
}

/// Jayway regular expressions `/pattern/flags`.
enum JaywayRegex {
    /// Flags: `i` case-insensitive, `m` multi-line anchors, `s` dot matches newlines,
    /// `x` extended (comments and whitespace); `d`, `u` and `U` are accepted and ignored.
    static func options(_ flags: String) -> Set<Character> {
        Set(flags.filter { "imsx".contains($0) })
    }

    static func compile(_ pattern: String, flags: String) -> Regex<AnyRegexOutput>? {
        let options = options(flags)
        let prefix = options.isEmpty ? "" : "(?" + String(options.sorted()) + ")"
        return try? Regex(prefix + translateEscapes(pattern))
    }

    /// Converts `\uXXXX` escapes (Java/ICU) to Swift's `\u{XXXX}`.
    static func translateEscapes(_ pattern: String) -> String {
        var result = ""
        var scalars = Array(pattern.unicodeScalars)[...]
        while let c = scalars.first {
            scalars.removeFirst()
            if c == "\\", let next = scalars.first {
                if next == "u", scalars.count >= 5,
                    scalars.dropFirst().prefix(4).allSatisfy({ $0.properties.isASCIIHexDigit })
                {
                    result += "\\u{" + String(String.UnicodeScalarView(scalars.dropFirst().prefix(4))) + "}"
                    scalars = scalars.dropFirst(5)
                    continue
                }
                result.unicodeScalars.append(c)
                result.unicodeScalars.append(next)
                scalars.removeFirst()
                continue
            }
            result.unicodeScalars.append(c)
        }
        return result
    }
}
