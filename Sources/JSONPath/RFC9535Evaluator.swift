/// Evaluates queries with RFC 9535 semantics.
struct RFC9535Evaluator {
    let root: JSONValue

    typealias Node = JSONPath.Node

    func evaluate(_ query: JSONPath.Query, current: JSONValue) throws -> [Node] {
        var nodes = [Node(location: .root, value: query.root == .root ? root : current)]
        for segment in query.segments {
            var next: [Node] = []
            switch segment {
            case .child(let selectors):
                for node in nodes { apply(selectors, to: node, into: &next) }
            case .descendant(let selectors):
                for node in nodes { descend(selectors, from: node, into: &next) }
            case .function:
                throw JSONPath.EvaluationError("Path functions are not part of RFC 9535")
            }
            nodes = next
        }
        return nodes
    }

    func descend(_ selectors: [JSONPath.Selector], from node: Node, into results: inout [Node]) {
        apply(selectors, to: node, into: &results)
        switch node.value {
        case .object(let object):
            for (key, child) in object {
                descend(
                    selectors, from: Node(location: node.location?.appending(.name(key)), value: child), into: &results)
            }
        case .array(let array):
            for (index, child) in array.enumerated() {
                descend(
                    selectors, from: Node(location: node.location?.appending(.index(index)), value: child),
                    into: &results)
            }
        default:
            break
        }
    }

    func apply(_ selectors: [JSONPath.Selector], to node: Node, into results: inout [Node]) {
        for selector in selectors {
            apply(selector, to: node, into: &results)
        }
    }

    func apply(_ selector: JSONPath.Selector, to node: Node, into results: inout [Node]) {
        func child(_ element: NormalizedPath.Element, _ value: JSONValue) -> Node {
            Node(location: node.location?.appending(element), value: value)
        }
        switch selector {
        case .name(let name, _):
            if let value = node.value.member(name) {
                results.append(child(.name(name), value))
            }
        case .wildcard:
            switch node.value {
            case .object(let object):
                for (key, value) in object { results.append(child(.name(key), value)) }
            case .array(let array):
                for (index, value) in array.enumerated() { results.append(child(.index(index), value)) }
            default: break
            }
        case .index(let index):
            if case .array(let array) = node.value {
                let resolved = index < 0 ? array.count + index : index
                if array.indices.contains(resolved) { results.append(child(.index(resolved), array[resolved])) }
            }
        case .slice(let start, let end, let step):
            if case .array(let array) = node.value {
                for index in Self.sliceIndices(count: array.count, start: start, end: end, step: step) {
                    results.append(child(.index(index), array[index]))
                }
            }
        case .filter(let expression):
            switch node.value {
            case .object(let object):
                for (key, value) in object where test(expression, current: value) {
                    results.append(child(.name(key), value))
                }
            case .array(let array):
                for (index, value) in array.enumerated() where test(expression, current: value) {
                    results.append(child(.index(index), value))
                }
            default: break
            }
        }
    }

    /// RFC 9535 §2.3.4.2.2 slice semantics.
    static func sliceIndices(count: Int, start: Int?, end: Int?, step: Int?) -> [Int] {
        let step = step ?? 1
        guard step != 0 else { return [] }
        func normalize(_ i: Int) -> Int { i >= 0 ? i : count + i }
        if step > 0 {
            let lower = min(max(normalize(start ?? 0), 0), count)
            let upper = min(max(normalize(end ?? count), 0), count)
            guard lower < upper else { return [] }
            return Array(stride(from: lower, to: upper, by: step))
        } else {
            let upper = min(max(start.map(normalize) ?? count - 1, -1), count - 1)
            let lower = min(max(end.map(normalize) ?? -1, -1), count - 1)
            guard lower < upper else { return [] }
            return Array(stride(from: upper, to: lower, by: step))
        }
    }

    // MARK: - Filters

    func test(_ expression: JSONPath.FilterExpression, current: JSONValue) -> Bool {
        switch expression {
        case .or(let terms): return terms.contains { test($0, current: current) }
        case .and(let terms): return terms.allSatisfy { test($0, current: current) }
        case .not(let inner): return !test(inner, current: current)
        case .exists(let query, let negated):
            let exists = !((try? evaluate(query, current: current)) ?? []).isEmpty
            return exists != negated
        case .function(let call):
            return (try? RFC9535Functions.evaluateLogical(call, current: current, root: root, jayway: nil)) ?? false
        case .comparison(let lhs, let op, let rhs):
            return Self.compare(value(lhs, current: current), op, value(rhs, current: current))
        }
    }

    /// The value of a comparable; `nil` means "Nothing".
    func value(_ operand: JSONPath.Operand, current: JSONValue) -> JSONValue? {
        switch operand {
        case .literal(let value, _): return value
        case .query(let query):
            guard let nodes = try? evaluate(query, current: current), nodes.count == 1 else { return nil }
            return nodes[0].value
        case .function(let call):
            return (try? RFC9535Functions.evaluateValue(call, current: current, root: root, jayway: nil)) ?? nil
        case .regex: return nil
        }
    }

    /// RFC 9535 §2.3.5.2.2 comparison semantics.
    static func compare(_ lhs: JSONValue?, _ op: JSONPath.ComparisonOperator, _ rhs: JSONValue?) -> Bool {
        switch op {
        case .equal: return equal(lhs, rhs)
        case .notEqual: return !equal(lhs, rhs)
        case .less: return less(lhs, rhs)
        case .lessOrEqual: return less(lhs, rhs) || equal(lhs, rhs)
        case .greater: return less(rhs, lhs)
        case .greaterOrEqual: return less(rhs, lhs) || equal(lhs, rhs)
        default: return false
        }
    }

    static func equal(_ lhs: JSONValue?, _ rhs: JSONValue?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (let l?, let r?): return l.isDeepEqual(to: r)
        default: return false
        }
    }

    static func less(_ lhs: JSONValue?, _ rhs: JSONValue?) -> Bool {
        guard let lhs, let rhs else { return false }
        if let l = lhs.doubleValue, let r = rhs.doubleValue {
            if case .integer(let a) = lhs, case .integer(let b) = rhs { return a < b }
            return l < r
        }
        if case .string(let l) = lhs, case .string(let r) = rhs {
            return l.unicodeScalars.lexicographicallyPrecedes(r.unicodeScalars)
        }
        return false
    }
}

extension JSONValue {
    /// JSON value equality: numbers compare by value (`1 == 1.0`), objects ignore member order.
    public func isDeepEqual(to other: JSONValue) -> Bool {
        switch (self, other) {
        case (.integer(let a), .integer(let b)): return a == b
        case (.integer, .number), (.number, .integer), (.number, .number):
            return doubleValue == other.doubleValue
        case (.array(let a), .array(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.isDeepEqual(to: $1) }
        case (.object(let a), .object(let b)):
            return a.count == b.count
                && a.allSatisfy { key, value in b[key].map { value.isDeepEqual(to: $0) } ?? false }
        default:
            return self == other
        }
    }
}

// MARK: - Functions

/// The RFC 9535 function extensions: `length`, `count`, `match`, `search`, `value`.
enum RFC9535Functions {
    enum ResultType {
        case value, logical, nodes
    }

    enum ParameterType {
        case value, logical, nodes
    }

    static let signatures: [String: (parameters: [ParameterType], result: ResultType)] = [
        "length": ([.value], .value),
        "count": ([.nodes], .value),
        "match": ([.value, .value], .logical),
        "search": ([.value, .value], .logical),
        "value": ([.nodes], .value),
    ]

    static func resultType(of call: JSONPath.FunctionCall) -> ResultType? {
        signatures[call.name]?.result
    }

    /// RFC 9535 §2.4.3 well-typedness.
    static func typeCheck(_ call: JSONPath.FunctionCall, at position: Int) throws {
        guard let signature = signatures[call.name] else {
            throw JSONPath.ParseError(message: "Unknown function '\(call.name)'", position: position)
        }
        guard signature.parameters.count == call.arguments.count else {
            throw JSONPath.ParseError(
                message:
                    "\(call.name)() expects \(signature.parameters.count) argument(s), got \(call.arguments.count)",
                position: position)
        }
        for (parameter, argument) in zip(signature.parameters, call.arguments) {
            let ok: Bool
            switch (parameter, argument) {
            case (.value, .literal): ok = true
            case (.value, .query(let query)): ok = query.isSingular
            case (.value, .function(let inner)): ok = resultType(of: inner) == .value
            case (.value, .logical): ok = false
            case (.logical, .logical), (.logical, .query): ok = true
            case (.logical, .function(let inner)): ok = resultType(of: inner) != .value
            case (.logical, .literal): ok = false
            case (.nodes, .query): ok = true
            case (.nodes, .function(let inner)): ok = resultType(of: inner) == .nodes
            case (.nodes, _): ok = false
            }
            guard ok else {
                throw JSONPath.ParseError(
                    message: "Invalid argument \(argument.rfcDescription) for \(call.name)()", position: position)
            }
        }
    }

    enum Argument {
        case value(JSONValue?)
        case nodes([JSONValue])
        case logical(Bool)
    }

    static func arguments(
        _ call: JSONPath.FunctionCall, current: JSONValue, root: JSONValue, jayway: JaywayEvaluator?
    ) throws -> [Argument] {
        let rfc = RFC9535Evaluator(root: root)
        let parameters = signatures[call.name]?.parameters ?? []
        return try call.arguments.enumerated().map { index, argument in
            let parameter = index < parameters.count ? parameters[index] : .value
            switch argument {
            case .literal(let value, _):
                return .value(value)
            case .query(let query):
                let nodes: [JSONValue]
                if let jayway {
                    nodes = try jayway.evaluate(query, current: current).map(\.value)
                } else {
                    nodes = try rfc.evaluate(query, current: current).map(\.value)
                }
                switch parameter {
                case .nodes: return .nodes(nodes)
                case .logical: return .logical(!nodes.isEmpty)
                case .value: return .value(nodes.count == 1 ? nodes[0] : nil)
                }
            case .function(let inner):
                if resultType(of: inner) == .logical {
                    return .logical(try evaluateLogical(inner, current: current, root: root, jayway: jayway))
                }
                return .value(try evaluateValue(inner, current: current, root: root, jayway: jayway))
            case .logical(let expression):
                if let jayway { return .logical(jayway.accept(expression, current: current)) }
                return .logical(rfc.test(expression, current: current))
            }
        }
    }

    /// Evaluates a ValueType function (`length`, `count`, `value`). `nil` is "Nothing".
    static func evaluateValue(
        _ call: JSONPath.FunctionCall, current: JSONValue, root: JSONValue, jayway: JaywayEvaluator?
    ) throws -> JSONValue? {
        let args = try arguments(call, current: current, root: root, jayway: jayway)
        switch call.name {
        case "length":
            guard case .value(let value?) = args.first else { return nil }
            switch value {
            case .string(let s): return .integer(s.unicodeScalars.count)
            case .array(let a): return .integer(a.count)
            case .object(let o): return .integer(o.count)
            default: return nil
            }
        case "count":
            guard case .nodes(let nodes) = args.first else { return nil }
            return .integer(nodes.count)
        case "value":
            guard case .nodes(let nodes) = args.first, nodes.count == 1 else { return nil }
            return nodes[0]
        default:
            throw JSONPath.EvaluationError("Function '\(call.name)' does not return a value")
        }
    }

    /// Evaluates a LogicalType function (`match`, `search`).
    static func evaluateLogical(
        _ call: JSONPath.FunctionCall, current: JSONValue, root: JSONValue, jayway: JaywayEvaluator?
    ) throws -> Bool {
        let args = try arguments(call, current: current, root: root, jayway: jayway)
        switch call.name {
        case "match", "search":
            guard args.count == 2, case .value(.string(let subject)?) = args[0],
                case .value(.string(let pattern)?) = args[1],
                let regex = IRegexp.compile(pattern)
            else { return false }
            let target = subject
            if call.name == "match" {
                return (try? regex.wholeMatch(in: target)) != nil
            }
            return (try? regex.firstMatch(in: target)) != nil
        default:
            // NodesType results convert to LogicalType: non-empty means true.
            if let value = try evaluateValue(call, current: current, root: root, jayway: jayway) {
                return value.boolValue ?? true
            }
            return false
        }
    }
}

/// I-Regexp (RFC 9485) on top of Swift `Regex`.
enum IRegexp {
    /// Validates the I-Regexp subset and translates it to Swift regex syntax:
    /// `.` matches any character except `\n` and `\r`, and matching is done on Unicode scalars.
    static func compile(_ pattern: String) -> Regex<AnyRegexOutput>? {
        guard let translated = translate(pattern) else { return nil }
        return (try? Regex(translated))?.matchingSemantics(.unicodeScalar)
    }

    static func translate(_ pattern: String) -> String? {
        let scalars = Array(pattern.unicodeScalars)
        var output = ""
        var index = 0
        var inClass = false
        var depth = 0
        while index < scalars.count {
            let c = scalars[index]
            switch c {
            case "\\":
                guard index + 1 < scalars.count else { return nil }
                let e = scalars[index + 1]
                switch e {
                case "p", "P":
                    guard index + 2 < scalars.count, scalars[index + 2] == "{",
                        let close = scalars[(index + 2)...].firstIndex(of: "}")
                    else { return nil }
                    output.unicodeScalars.append(contentsOf: scalars[index...close])
                    index = close + 1
                    continue
                case "n", "r", "t", "\\", "|", ".", "-", "^", "?", "*", "+", "{", "}", "(", ")", "[", "]":
                    output.unicodeScalars.append(c)
                    output.unicodeScalars.append(e)
                    index += 2
                    continue
                default:
                    return nil  // not an I-Regexp escape
                }
            case "[":
                if inClass {
                    output += "\\["
                } else {
                    inClass = true
                    output += "["
                    if index + 1 < scalars.count, scalars[index + 1] == "^" {
                        output += "^"
                        index += 1
                    }
                }
            case "]":
                if inClass {
                    inClass = false
                    output += "]"
                } else {
                    output += "\\]"
                }
            case ".":
                output += inClass ? "." : "[^\\n\\r]"
            case "(":
                if inClass {
                    output += "\\("
                } else {
                    if index + 1 < scalars.count, scalars[index + 1] == "?" { return nil }  // no groups extensions
                    depth += 1
                    output += "(?:"
                }
            case ")":
                if inClass {
                    output += "\\)"
                } else {
                    depth -= 1
                    if depth < 0 { return nil }
                    output += ")"
                }
            case "^", "$":
                // Anchors outside character classes (as the compliance suite expects); literal inside.
                output += inClass ? "\\" + String(c) : String(c)
            default:
                output.unicodeScalars.append(c)
            }
            index += 1
        }
        guard !inClass, depth == 0 else { return nil }
        return output
    }
}
