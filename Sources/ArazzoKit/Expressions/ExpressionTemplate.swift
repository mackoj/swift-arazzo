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
            // `{`, `$` and `}` are ASCII, so they are found on the UTF-8 view, and the literal text between
            // expressions is appended run by run (from `run`) rather than one `Character` at a time.
            let utf8 = string.utf8
            var run = string.startIndex
            var index = string.startIndex
            while let open = utf8[index...].firstIndex(of: UInt8(ascii: "{")) {
                let next = utf8.index(after: open)
                guard next < utf8.endIndex, utf8[next] == UInt8(ascii: "$"),
                    let close = utf8[next...].firstIndex(of: UInt8(ascii: "}"))
                else {
                    index = next
                    continue
                }
                let text = String(string[next..<close])
                let end = utf8.index(after: close)
                literal += string[run..<open]
                do {
                    let expression = try RuntimeExpression(text)
                    if !literal.isEmpty {
                        located.append(LocatedSegment(segment: .literal(literal), range: literalStart..<open))
                        literal = ""
                    }
                    located.append(LocatedSegment(segment: .expression(expression), range: open..<end))
                    literalStart = end
                } catch let error as RuntimeExpression.ParseError {
                    // `text` is a copy of `string[next..<close]`, so UTF-8 offsets carry over.
                    func templateIndex(_ i: String.Index) -> String.Index {
                        string.utf8.index(next, offsetBy: text.utf8.distance(from: text.startIndex, to: i))
                    }
                    let errorRange = templateIndex(error.range.lowerBound)..<templateIndex(error.range.upperBound)
                    invalid.append(
                        InvalidExpression(text: text, error: error, range: open..<end, errorRange: errorRange))
                    literal += string[open...close]
                } catch {
                    literal += string[open...close]
                }
                run = end
                index = end
            }
            literal += string[run...]
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
