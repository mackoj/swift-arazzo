/// A coding key that can represent any string or integer key.
public struct AnyCodingKey: CodingKey, Hashable, Sendable, ExpressibleByStringLiteral {
    public var stringValue: String
    public var intValue: Int?

    public init(_ string: String) {
        stringValue = string
        intValue = nil
    }

    public init(stringValue: String) { self.init(stringValue) }

    public init(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }

    public init(stringLiteral value: String) { self.init(value) }
}
