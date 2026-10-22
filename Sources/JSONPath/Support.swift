/// A coding key that can represent any string or integer key.
struct JSONCodingKey: CodingKey, Hashable, Sendable {
    var stringValue: String
    var intValue: Int?

    init(_ string: String) {
        stringValue = string
        intValue = nil
    }

    init(stringValue: String) { self.init(stringValue) }

    init(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isASCIILetter: Bool { isASCII && isLetter }
}

extension String {
    func replacingAll(_ target: Character, with replacement: String) -> String {
        var result = ""
        for character in self {
            if character == target { result += replacement } else { result.append(character) }
        }
        return result
    }
}
