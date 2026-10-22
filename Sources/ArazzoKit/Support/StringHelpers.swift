import JSONPath

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

extension JSONValue {
    /// The string representation used when a value is embedded in a string with `{$expression}`:
    /// scalars become their plain text form, structured values are serialized as JSON.
    public var embeddedStringValue: String {
        switch self {
        case .string(let v): v
        default: jsonString
        }
    }
}
