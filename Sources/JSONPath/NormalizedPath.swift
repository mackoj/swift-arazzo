/// The location of a node within a JSON value, e.g. `$['store']['book'][0]`.
///
/// Rendered in the RFC 9535 "Normalized Path" form (§2.7), which Jayway JsonPath also uses.
public struct NormalizedPath: Hashable, Sendable, Comparable, CustomStringConvertible, ExpressibleByArrayLiteral {
    public enum Element: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral,
        ExpressibleByIntegerLiteral
    {
        case name(String)
        case index(Int)

        public init(stringLiteral value: String) { self = .name(value) }
        public init(integerLiteral value: Int) { self = .index(value) }

        public var description: String {
            switch self {
            case .name(let name): "['" + NormalizedPath.escape(name) + "']"
            case .index(let index): "[\(index)]"
            }
        }
    }

    public var elements: [Element]

    public init(_ elements: [Element] = []) {
        self.elements = elements
    }

    public init(arrayLiteral elements: Element...) {
        self.elements = elements
    }

    /// The root path, `$`.
    public static let root = NormalizedPath()

    public var description: String {
        "$" + elements.map(\.description).joined()
    }

    /// The equivalent JSON Pointer (RFC 6901).
    public var jsonPointer: JSONPointer {
        JSONPointer(
            tokens: elements.map {
                switch $0 {
                case .name(let name): name
                case .index(let index): String(index)
                }
            })
    }

    public func appending(_ element: Element) -> NormalizedPath {
        NormalizedPath(elements + [element])
    }

    /// The parent location, or `nil` for the root.
    public var parent: NormalizedPath? {
        elements.isEmpty ? nil : NormalizedPath(Array(elements.dropLast()))
    }

    /// Orders paths so that, within the same container, later array indices come first –
    /// the order in which removals can be applied without invalidating the remaining paths.
    public static func < (lhs: NormalizedPath, rhs: NormalizedPath) -> Bool {
        for (l, r) in zip(lhs.elements, rhs.elements) {
            switch (l, r) {
            case (.index(let a), .index(let b)) where a != b: return a < b
            case (.name(let a), .name(let b)) where a != b: return a < b
            case (.index, .name): return true
            case (.name, .index): return false
            default: continue
            }
        }
        return lhs.elements.count < rhs.elements.count
    }

    /// RFC 9535 §2.7 escaping for member names.
    static func escape(_ name: String) -> String {
        var result = ""
        for scalar in name.unicodeScalars {
            switch scalar {
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "'": result += "\\'"
            case "\\": result += "\\\\"
            case let s where s.value < 0x20:
                let hex = String(s.value, radix: 16)
                result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}

extension JSONValue {
    /// The value at a normalized path, or `nil` if there is none.
    public subscript(path: NormalizedPath) -> JSONValue? {
        var current = self
        for element in path.elements {
            switch element {
            case .name(let name):
                guard let next = current[name] else { return nil }
                current = next
            case .index(let index):
                guard let next = current[index] else { return nil }
                current = next
            }
        }
        return current
    }
}
