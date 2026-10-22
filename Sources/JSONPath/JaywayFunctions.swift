/// Jayway path functions: `$.numbers.avg()`, `$.text.concat("-")`, `$.list.length()`, ...
enum JaywayFunctions {
    static let supported: Set<String> = [
        "avg", "stddev", "sum", "min", "max", "concat", "length", "size", "append", "keys", "first", "last", "index",
    ]

    static func invoke(_ call: JSONPath.FunctionCall, input: JSONValue, evaluator: JaywayEvaluator) throws -> JSONValue
    {
        let name = call.name.lowercased()
        func arguments() throws -> [JSONValue] {
            try call.arguments.map { try argument($0, input: input, evaluator: evaluator) }
        }
        func numerals() throws -> [Double] {
            var values: [Double] = []
            if case .array(let array) = input { values += array.compactMap(\.doubleValue) }
            for argument in try arguments() {
                switch argument {
                case .integer, .number: values.append(argument.doubleValue!)
                case .array(let array): values += array.compactMap(\.doubleValue)
                default: break
                }
            }
            guard !values.isEmpty else {
                throw JSONPath.EvaluationError("Aggregation function attempted to calculate value using empty array")
            }
            return values
        }

        switch name {
        case "avg":
            let values = try numerals()
            return .number(values.reduce(0, +) / Double(values.count))
        case "stddev":
            let values = try numerals()
            let count = Double(values.count)
            let sum = values.reduce(0, +)
            let sumSquares = values.reduce(0) { $0 + $1 * $1 }
            return .number(((sumSquares / count) - (sum * sum / count / count)).squareRoot())
        case "sum":
            return .number(try numerals().reduce(0, +))
        case "min":
            return .number(try numerals().min()!)
        case "max":
            return .number(try numerals().max()!)
        case "concat":
            var parts: [String] = []
            if case .array(let array) = input { parts += array.compactMap(\.stringValue) }
            for argument in try arguments() {
                switch argument {
                case .string(let s): parts.append(s)
                case .null: break
                case .array(let array): parts += array.compactMap(\.stringValue)
                default: parts.append(argument.jsonString)
                }
            }
            guard !parts.isEmpty else {
                throw JSONPath.EvaluationError("Aggregation function attempted to calculate value using empty array")
            }
            return .string(parts.joined())
        case "length", "size":
            switch input {
            case .array(let array): return .integer(array.count)
            case .object(let object): return .integer(object.count)
            case .string(let string): return .integer(string.unicodeScalars.count)
            default: throw JSONPath.EvaluationError("length() can only be applied to arrays, objects and strings")
            }
        case "append":
            guard case .array(let array) = input else { return input }
            return .array(array + (try arguments()))
        case "keys":
            guard case .object(let object) = input else {
                throw JSONPath.EvaluationError("keys() can only be applied to objects")
            }
            return .array(object.keys.map(JSONValue.string))
        case "first":
            guard case .array(let array) = input, let first = array.first else {
                throw JSONPath.EvaluationError("first() requires a non-empty array")
            }
            return first
        case "last":
            guard case .array(let array) = input, let last = array.last else {
                throw JSONPath.EvaluationError("last() requires a non-empty array")
            }
            return last
        case "index":
            guard case .array(let array) = input, let index = try arguments().first?.intValue else {
                throw JSONPath.EvaluationError("index(n) requires an array and an integer")
            }
            let resolved = index < 0 ? array.count + index : index
            guard array.indices.contains(resolved) else {
                throw JSONPath.EvaluationError("index(\(index)) is out of bounds")
            }
            return array[resolved]
        default:
            throw JSONPath.EvaluationError("Function '\(call.name)' is not supported")
        }
    }

    static func argument(
        _ argument: JSONPath.FunctionArgument, input: JSONValue, evaluator: JaywayEvaluator
    ) throws
        -> JSONValue
    {
        switch argument {
        case .literal(let value, _):
            return value
        case .query(let query):
            let nodes = try evaluator.evaluate(query, current: input)
            if query.isDefinite {
                guard let first = nodes.first else {
                    throw JSONPath.EvaluationError("Function argument \(query.jaywayDescription) did not resolve")
                }
                return first.value
            }
            return .array(nodes.map(\.value))
        case .function(let call):
            guard
                let value = try RFC9535Functions.evaluateValue(
                    call, current: input, root: evaluator.root, jayway: evaluator)
            else { throw JSONPath.EvaluationError("Function argument did not resolve") }
            return value
        case .logical:
            throw JSONPath.EvaluationError("Logical expressions are not valid path function arguments")
        }
    }
}
