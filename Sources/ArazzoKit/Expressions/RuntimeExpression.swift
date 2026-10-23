import JSONPath
extension Arazzo {
    /// A [Runtime Expression](https://spec.openapis.org/arazzo/latest.html#runtime-expressions),
    /// such as `$response.body#/id` or `$steps.login.outputs.token`.
    ///
    /// Parsing follows the ABNF in the specification. Two widely used (and spec-example) shorthands
    /// are also accepted and flagged with ``usesNonStandardNotation``:
    /// - dotted paths after `body` / `payload` (`$response.body.data.id` ≡ `$response.body#/data/id`)
    /// - bracket indices in those paths (`$response.body.items[0].id`)
    public struct RuntimeExpression: Hashable, Sendable, CustomStringConvertible {
        /// The exact text the expression was parsed from.
        public let rawValue: String
        public let kind: Kind
        /// `true` when the expression relied on a shorthand not described by the ABNF.
        public let usesNonStandardNotation: Bool

        public enum Kind: Hashable, Sendable {
            /// `$url`
            case url
            /// `$method`
            case method
            /// `$statusCode`
            case statusCode
            /// `$self`
            case `self`
            /// `$request.<source>`
            case request(Source)
            /// `$response.<source>`
            case response(Source)
            /// `$message.<source>` (AsyncAPI, Arazzo 1.1)
            case message(Source)
            /// `$inputs.<name>[#pointer]`
            case inputs(name: String, pointer: JSONPointer?)
            /// `$outputs.<name>[#pointer]`
            case outputs(name: String, pointer: JSONPointer?)
            /// `$steps.<stepId>.outputs.<name>[#pointer]`
            case steps(stepId: String, outputName: String, pointer: JSONPointer?)
            /// `$workflows.<workflowId>.(inputs|outputs).<name>[#pointer]`
            case workflows(workflowId: String, field: WorkflowField, name: String, pointer: JSONPointer?)
            /// `$sourceDescriptions.<name>.<reference>`
            case sourceDescriptions(name: String, reference: String)
            /// `$components.<type>.<name>`
            case components(type: ComponentType, name: String)
            /// A string that failed to parse. Only produced when decoding in lenient mode (the default),
            /// so that one bad expression does not prevent reading a document; validation reports it.
            case invalid(ParseError)
        }

        /// A request, response or message source.
        public enum Source: Hashable, Sendable {
            /// `header.<token>` – header names are case-insensitive.
            case header(String)
            case query(String)
            case path(String)
            /// `body[#pointer]`
            case body(JSONPointer?)
            /// `payload[#pointer]` (AsyncAPI messages)
            case payload(JSONPointer?)
        }

        public enum WorkflowField: String, Hashable, Sendable {
            case inputs, outputs
        }

        public enum ComponentType: String, Hashable, Sendable, CaseIterable {
            case parameters, successActions, failureActions
        }

        public struct ParseError: Error, Hashable, Sendable, CustomStringConvertible {
            public let expression: String
            public let message: String
            /// The part of ``expression`` the error refers to: the offending text, or the unparsed
            /// rest of the expression from where parsing stopped. It is empty at the end of
            /// ``expression`` when text is missing there.
            ///
            /// Two errors compare equal when their ``expression`` and ``message`` do, whatever their range.
            public let range: Range<String.Index>

            init(expression: String, message: String, range: Range<String.Index>? = nil) {
                self.expression = expression
                self.message = message
                self.range = range ?? expression.startIndex..<expression.endIndex
            }

            public var description: String { "Invalid runtime expression '\(expression)': \(message)" }

            public static func == (lhs: Self, rhs: Self) -> Bool {
                lhs.expression == rhs.expression && lhs.message == rhs.message
            }

            public func hash(into hasher: inout Hasher) {
                hasher.combine(expression)
                hasher.combine(message)
            }
        }

        /// Parses a runtime expression. The whole string must be a single expression.
        public init(_ string: String) throws {
            var parser = Parser(string)
            let (kind, nonStandard) = try parser.parse()
            rawValue = string
            self.kind = kind
            usesNonStandardNotation = nonStandard
        }

        /// Creates an expression from its structured form. `rawValue` is rendered canonically.
        public init(_ kind: Kind) {
            self.kind = kind
            rawValue = Self.render(kind)
            usesNonStandardNotation = false
        }

        /// Parses `string`, keeping it as an ``Kind/invalid(_:)`` expression if it does not parse.
        public init(lenient string: String) {
            var parser = Parser(string)
            do {
                let (kind, nonStandard) = try parser.parse()
                self.init(rawValue: string, kind: kind, usesNonStandardNotation: nonStandard)
            } catch {
                let parseError = error as? ParseError ?? ParseError(expression: string, message: "\(error)")
                self.init(rawValue: string, kind: .invalid(parseError), usesNonStandardNotation: false)
            }
        }

        private init(rawValue: String, kind: Kind, usesNonStandardNotation: Bool) {
            self.rawValue = rawValue
            self.kind = kind
            self.usesNonStandardNotation = usesNonStandardNotation
        }

        public var description: String { rawValue }

        /// The parse error, for expressions decoded leniently from invalid text.
        public var parseError: ParseError? {
            if case .invalid(let error) = kind { return error }
            return nil
        }

        /// `false` for expressions that failed to parse.
        public var isValid: Bool { parseError == nil }

        /// The canonical (ABNF-conformant) text of the expression.
        public var canonicalString: String {
            if case .invalid = kind { return rawValue }
            return Self.render(kind)
        }

        /// Returns `true` if `string` parses as a runtime expression.
        public static func isValid(_ string: String) -> Bool {
            (try? RuntimeExpression(string)) != nil
        }

        public static func == (lhs: Self, rhs: Self) -> Bool { lhs.kind == rhs.kind }
        public func hash(into hasher: inout Hasher) { hasher.combine(kind) }
    }
}

// MARK: - Convenience accessors

extension Arazzo.RuntimeExpression {
    /// The step referenced by a `$steps.<stepId>...` expression.
    public var referencedStepID: String? {
        if case .steps(let stepId, _, _) = kind { return stepId }
        return nil
    }

    /// The source description referenced by a `$sourceDescriptions.<name>...` expression.
    public var referencedSourceDescriptionName: String? {
        if case .sourceDescriptions(let name, _) = kind { return name }
        return nil
    }

    /// The workflow referenced by a `$workflows.<workflowId>...` expression.
    public var referencedWorkflowID: String? {
        if case .workflows(let id, _, _, _) = kind { return id }
        return nil
    }

    /// The workflow input referenced by an `$inputs.<name>` expression.
    public var referencedInputName: String? {
        if case .inputs(let name, _) = kind { return name }
        return nil
    }

    /// `true` for expressions that only make sense while a step executes
    /// (`$url`, `$method`, `$statusCode`, `$request`, `$response`, `$message`).
    public var isStepRuntimeOnly: Bool {
        switch kind {
        case .url, .method, .statusCode, .request, .response, .message: true
        default: false
        }
    }
}

// MARK: - Rendering

extension Arazzo.RuntimeExpression {
    static func render(_ kind: Kind) -> String {
        func pointer(_ pointer: JSONPointer?) -> String {
            pointer.map { "#" + $0.description } ?? ""
        }
        func source(_ source: Source) -> String {
            switch source {
            case .header(let name): "header." + name
            case .query(let name): "query." + name
            case .path(let name): "path." + name
            case .body(let p): "body" + pointer(p)
            case .payload(let p): "payload" + pointer(p)
            }
        }
        switch kind {
        case .url: return "$url"
        case .method: return "$method"
        case .statusCode: return "$statusCode"
        case .self: return "$self"
        case .request(let s): return "$request." + source(s)
        case .response(let s): return "$response." + source(s)
        case .message(let s): return "$message." + source(s)
        case .inputs(let name, let p): return "$inputs." + name + pointer(p)
        case .outputs(let name, let p): return "$outputs." + name + pointer(p)
        case .steps(let id, let name, let p): return "$steps.\(id).outputs.\(name)" + pointer(p)
        case .workflows(let id, let field, let name, let p):
            return "$workflows.\(id).\(field.rawValue).\(name)" + pointer(p)
        case .sourceDescriptions(let name, let reference): return "$sourceDescriptions.\(name).\(reference)"
        case .components(let type, let name): return "$components.\(type.rawValue).\(name)"
        case .invalid(let error): return error.expression
        }
    }
}

// MARK: - Codable

extension Arazzo.RuntimeExpression: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        if decoder.arazzoOptions.strict {
            do {
                try self.init(string)
            } catch {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "\(error)")
            }
        } else {
            self.init(lenient: string)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Character classes

enum ExpressionGrammar {
    /// `identifier-strict = 1*( ALPHA / DIGIT / "-" / "_" )`
    static func isStrictIdentifierCharacter(_ c: Character) -> Bool {
        c.isASCIILetter || c.isASCIIDigit || c == "-" || c == "_"
    }

    /// `identifier = 1*( ALPHA / DIGIT / "." / "-" / "_" )`
    static func isIdentifierCharacter(_ c: Character) -> Bool {
        isStrictIdentifierCharacter(c) || c == "."
    }

    /// RFC 9110 `tchar`.
    static func isTokenCharacter(_ c: Character) -> Bool {
        c.isASCIILetter || c.isASCIIDigit || "!#$%&'*+-.^_`|~".contains(c)
    }

    static func isStrictIdentifier(_ s: some StringProtocol) -> Bool {
        !s.isEmpty && s.allSatisfy(isStrictIdentifierCharacter)
    }

    static func isIdentifier(_ s: some StringProtocol) -> Bool {
        !s.isEmpty && s.allSatisfy(isIdentifierCharacter)
    }
}

// MARK: - Parser

extension Arazzo.RuntimeExpression {
    struct Parser {
        let original: String
        var rest: Substring
        var nonStandard = false

        init(_ string: String) {
            original = string
            rest = Substring(string)
        }

        /// An error about `range`, by default the unparsed rest of the expression.
        func fail(_ message: String, at range: Range<String.Index>? = nil) -> ParseError {
            ParseError(expression: original, message: message, range: range ?? rest.startIndex..<original.endIndex)
        }

        mutating func consume(_ prefix: String) -> Bool {
            guard rest.hasPrefix(prefix) else { return false }
            rest = rest.dropFirst(prefix.count)
            return true
        }

        mutating func parse() throws -> (Kind, Bool) {
            guard rest.first == "$" else { throw fail("expressions must start with '$'") }
            if let brace = rest.firstIndex(where: { $0 == "{" || $0 == "}" }) {
                throw fail("'{' and '}' are not allowed inside an expression", at: brace..<rest.index(after: brace))
            }
            let kind: Kind
            if consume("$url") {
                kind = .url
            } else if consume("$method") {
                kind = .method
            } else if consume("$statusCode") {
                kind = .statusCode
            } else if consume("$self") {
                kind = .self
            } else if consume("$request.") {
                kind = .request(try parseSource())
            } else if consume("$response.") {
                kind = .response(try parseSource())
            } else if consume("$message.") {
                kind = .message(try parseSource())
            } else if consume("$inputs.") {
                let (name, pointer) = try parseIdentifierWithPointer(what: "input name")
                kind = .inputs(name: name, pointer: pointer)
            } else if consume("$outputs.") {
                let (name, pointer) = try parseIdentifierWithPointer(what: "output name")
                kind = .outputs(name: name, pointer: pointer)
            } else if consume("$steps.") {
                let stepId = try parseStrictIdentifier(what: "step id")
                guard consume(".outputs.") else { throw fail("expected '.outputs.' after the step id") }
                let (name, pointer) = try parseIdentifierWithPointer(what: "output name")
                kind = .steps(stepId: stepId, outputName: name, pointer: pointer)
            } else if consume("$workflows.") {
                let workflowId = try parseStrictIdentifier(what: "workflow id")
                let field: WorkflowField
                if consume(".inputs.") {
                    field = .inputs
                } else if consume(".outputs.") {
                    field = .outputs
                } else {
                    throw fail("expected '.inputs.' or '.outputs.' after the workflow id")
                }
                let (name, pointer) = try parseIdentifierWithPointer(what: "\(field.rawValue) name")
                kind = .workflows(workflowId: workflowId, field: field, name: name, pointer: pointer)
            } else if consume("$sourceDescriptions.") {
                let name = try parseStrictIdentifier(what: "source description name")
                guard consume("."), !rest.isEmpty else {
                    throw fail("expected '.<reference>' after the source description name")
                }
                kind = .sourceDescriptions(name: name, reference: String(rest))
                rest = rest[rest.endIndex...]
            } else if consume("$components.") {
                guard let typeEnd = rest.firstIndex(of: "."),
                    let type = ComponentType(rawValue: String(rest[..<typeEnd]))
                else {
                    throw fail("expected 'parameters', 'successActions' or 'failureActions' after '$components.'")
                }
                rest = rest[rest.index(after: typeEnd)...]
                let name = String(rest)
                guard ExpressionGrammar.isIdentifier(name) else {
                    throw fail("component name must match [a-zA-Z0-9.\\-_]+")
                }
                rest = rest[rest.endIndex...]
                kind = .components(type: type, name: name)
            } else {
                throw fail("unknown expression prefix")
            }
            guard rest.isEmpty else { throw fail("unexpected trailing characters '\(rest)'") }
            return (kind, nonStandard)
        }

        mutating func parseStrictIdentifier(what: String) throws -> String {
            let identifier = rest.prefix(while: ExpressionGrammar.isStrictIdentifierCharacter)
            guard !identifier.isEmpty else { throw fail("expected a \(what)") }
            rest = rest.dropFirst(identifier.count)
            return String(identifier)
        }

        mutating func parseIdentifierWithPointer(what: String) throws -> (String, JSONPointer?) {
            let identifier = rest.prefix(while: ExpressionGrammar.isIdentifierCharacter)
            guard !identifier.isEmpty else { throw fail("expected a \(what)") }
            rest = rest.dropFirst(identifier.count)
            return (String(identifier), try parseOptionalPointer())
        }

        mutating func parseOptionalPointer() throws -> JSONPointer? {
            guard consume("#") else { return nil }
            let pointerRange = rest.startIndex..<rest.endIndex
            let text = String(rest)
            rest = rest[rest.endIndex...]
            guard !text.hasPrefix("#") else { throw fail("a JSON Pointer cannot start with '#'", at: pointerRange) }
            do {
                return try JSONPointer(text)
            } catch {
                throw fail("\(error)", at: pointerRange)
            }
        }

        mutating func parseSource() throws -> Source {
            if consume("header.") {
                let token = String(rest)
                guard !token.isEmpty, token.allSatisfy(ExpressionGrammar.isTokenCharacter) else {
                    throw fail("header names must be RFC 9110 tokens")
                }
                rest = rest[rest.endIndex...]
                return .header(token)
            }
            if consume("query.") {
                defer { rest = rest[rest.endIndex...] }
                return .query(String(rest))
            }
            if consume("path.") {
                defer { rest = rest[rest.endIndex...] }
                return .path(String(rest))
            }
            if consume("body") {
                return .body(try parseBodyPath())
            }
            if consume("payload") {
                return .payload(try parseBodyPath())
            }
            throw fail("expected 'header.', 'query.', 'path.', 'body' or 'payload'")
        }

        /// `["#" json-pointer]`, or the non-standard dotted form `.a.b[0].c`.
        mutating func parseBodyPath() throws -> JSONPointer? {
            if rest.isEmpty { return nil }
            if rest.first == "#" { return try parseOptionalPointer() }
            guard rest.first == "." || rest.first == "[" else {
                throw fail("expected '#<json-pointer>' after body/payload")
            }
            nonStandard = true
            var tokens: [String] = []
            while !rest.isEmpty {
                if consume(".") {
                    let segment = rest.prefix { $0 != "." && $0 != "[" }
                    guard !segment.isEmpty else { throw fail("empty property name in path") }
                    tokens.append(String(segment))
                    rest = rest.dropFirst(segment.count)
                } else if consume("[") {
                    let openBracket = original.index(before: rest.startIndex)
                    guard let close = rest.firstIndex(of: "]") else {
                        throw fail("unterminated '['", at: openBracket..<rest.endIndex)
                    }
                    let bracket = openBracket..<rest.index(after: close)
                    var index = String(rest[..<close])
                    if let q = index.first, q == "'" || q == "\"" {
                        guard index.count >= 2, index.last == q else {
                            throw fail("unbalanced quote in '[\(index)]'", at: bracket)
                        }
                        index = String(index.dropFirst().dropLast())
                    } else if let last = index.last, last == "'" || last == "\"" {
                        throw fail("unbalanced quote in '[\(index)]'", at: bracket)
                    }
                    tokens.append(index)
                    rest = rest[rest.index(after: close)...]
                } else {
                    let character = rest.startIndex..<rest.index(after: rest.startIndex)
                    throw fail("unexpected character '\(rest.first!)' in path", at: character)
                }
            }
            return JSONPointer(tokens: tokens)
        }
    }
}
