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

        /// A ``Segment`` together with the part of ``ExpressionTemplate/rawValue`` it was read from.
        ///
        /// An expression segment's range covers its braces: in `id={$inputs.id}` it is `{$inputs.id}`.
        /// A literal segment's range also covers any invalid `{$...}` sequence merged into it.
        public struct LocatedSegment: Hashable, Sendable {
            public let segment: Segment
            /// The segment's text in ``ExpressionTemplate/rawValue``.
            public let range: Range<String.Index>
        }

        /// A `{$...}` sequence that looked like an embedded expression but failed to parse.
        public struct InvalidExpression: Hashable, Sendable {
            public let text: String
            /// The parse error. Its ``RuntimeExpression/ParseError/range`` indexes ``text``;
            /// ``errorRange`` is the same range in the template.
            public let error: RuntimeExpression.ParseError
            /// The sequence in ``ExpressionTemplate/rawValue``, braces included.
            public let range: Range<String.Index>
            /// The text the parse error refers to, in ``ExpressionTemplate/rawValue``.
            public let errorRange: Range<String.Index>
        }

        public let rawValue: String
        public let segments: [Segment]
        /// ``segments`` with their ranges in ``rawValue``, in the same order.
        ///
        /// The ranges are contiguous and cover all of ``rawValue``.
        public let locatedSegments: [LocatedSegment]
        public let invalidExpressions: [InvalidExpression]

        public init(_ string: String) {
            // Native UTF-8 storage, so that equal strings give equal ranges.
            var native = string
            native.makeContiguousUTF8()
            let string = native
            rawValue = string
            var located: [LocatedSegment] = []
            var invalid: [InvalidExpression] = []
            var literal = ""
            var literalStart = string.startIndex
            var index = string.startIndex
            while index < string.endIndex {
                let character = string[index]
                let next = string.index(after: index)
                if character == "{", next < string.endIndex, string[next] == "$",
                    let close = string[next...].firstIndex(of: "}")
                {
                    let text = String(string[next..<close])
                    let end = string.index(after: close)
                    do {
                        let expression = try RuntimeExpression(text)
                        if !literal.isEmpty {
                            located.append(LocatedSegment(segment: .literal(literal), range: literalStart..<index))
                            literal = ""
                        }
                        located.append(LocatedSegment(segment: .expression(expression), range: index..<end))
                        literalStart = end
                    } catch let error as RuntimeExpression.ParseError {
                        // `text` is a copy of `string[next..<close]`, so UTF-8 offsets carry over.
                        func templateIndex(_ i: String.Index) -> String.Index {
                            string.utf8.index(next, offsetBy: text.utf8.distance(from: text.startIndex, to: i))
                        }
                        let errorRange = templateIndex(error.range.lowerBound)..<templateIndex(error.range.upperBound)
                        invalid.append(
                            InvalidExpression(text: text, error: error, range: index..<end, errorRange: errorRange))
                        literal += string[index...close]
                    } catch {
                        literal += string[index...close]
                    }
                    index = end
                } else {
                    literal.append(character)
                    index = next
                }
            }
            if !literal.isEmpty {
                located.append(LocatedSegment(segment: .literal(literal), range: literalStart..<string.endIndex))
            }
            locatedSegments = located
            segments = located.map(\.segment)
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
