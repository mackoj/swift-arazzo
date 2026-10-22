import JSONPath
extension Arazzo {
    /// A string that may embed runtime expressions in curly braces, e.g.
    /// `https://{$inputs.host}/api/{$steps.create.outputs.id}/status`.
    ///
    /// Only `{` immediately followed by `$` starts an embedded expression, so JSON or XML
    /// templates such as `{"petId": "{$inputs.pet_id}"}` are handled naturally.
    public struct ExpressionTemplate: Hashable, Sendable, CustomStringConvertible {
        public enum Segment: Hashable, Sendable {
            case literal(String)
            case expression(RuntimeExpression)
        }

        /// A `{$...}` sequence that looked like an embedded expression but failed to parse.
        public struct InvalidExpression: Hashable, Sendable {
            public let text: String
            public let error: RuntimeExpression.ParseError
        }

        public let rawValue: String
        public let segments: [Segment]
        public let invalidExpressions: [InvalidExpression]

        public init(_ string: String) {
            rawValue = string
            var segments: [Segment] = []
            var invalid: [InvalidExpression] = []
            var literal = ""
            var index = string.startIndex
            while index < string.endIndex {
                let character = string[index]
                let next = string.index(after: index)
                if character == "{", next < string.endIndex, string[next] == "$",
                    let close = string[next...].firstIndex(of: "}")
                {
                    let text = String(string[next..<close])
                    do {
                        let expression = try RuntimeExpression(text)
                        if !literal.isEmpty {
                            segments.append(.literal(literal))
                            literal = ""
                        }
                        segments.append(.expression(expression))
                    } catch let error as RuntimeExpression.ParseError {
                        invalid.append(InvalidExpression(text: text, error: error))
                        literal += string[index...close]
                    } catch {
                        literal += string[index...close]
                    }
                    index = string.index(after: close)
                } else {
                    literal.append(character)
                    index = next
                }
            }
            if !literal.isEmpty { segments.append(.literal(literal)) }
            self.segments = segments
            invalidExpressions = invalid
        }

        /// The embedded runtime expressions in order of appearance.
        public var expressions: [RuntimeExpression] {
            segments.compactMap {
                if case .expression(let e) = $0 { e } else { nil }
            }
        }

        /// `true` if the string contains at least one embedded expression.
        public var hasExpressions: Bool { !expressions.isEmpty }

        public var description: String { rawValue }

        /// Substitutes every embedded expression using `resolve`.
        ///
        /// Scalars are inserted as their string representation, structured values as JSON
        /// (RFC 8259); unresolved (`nil`) values become `null`.
        public func render(_ resolve: (RuntimeExpression) throws -> JSONValue?) rethrows -> String {
            var output = ""
            for segment in segments {
                switch segment {
                case .literal(let text): output += text
                case .expression(let expression):
                    output += (try resolve(expression) ?? .null).embeddedStringValue
                }
            }
            return output
        }
    }
}
