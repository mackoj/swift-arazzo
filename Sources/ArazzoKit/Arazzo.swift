@_exported import JSONPath
/// Namespace for the [Arazzo Specification](https://spec.openapis.org/arazzo/latest.html) types.
///
/// ```swift
/// let document = try JSONDecoder().decode(Arazzo.Document.self, from: data)
/// let issues = document.validate()
/// ```
public enum Arazzo {}

extension Arazzo {
    /// The version of the Arazzo Specification a document conforms to (the `arazzo` field).
    ///
    /// Per the specification, tooling only considers `major.minor` when deciding the feature set;
    /// patch versions are clarifications.
    public struct SpecificationVersion: RawRepresentable, Hashable, Sendable, Comparable, Codable,
        CustomStringConvertible, ExpressibleByStringLiteral
    {
        public let rawValue: String
        public let major: Int
        public let minor: Int
        public let patch: Int
        /// Anything after the `major.minor.patch` triple, such as `-rc1`.
        public let suffix: String

        public init?(rawValue: String) {
            let trimmed = rawValue.trimmingWhitespace()
            var core = Substring(trimmed)
            var suffix = ""
            if let index = core.firstIndex(where: { $0 == "-" || $0 == "+" }) {
                suffix = String(core[index...])
                core = core[..<index]
            }
            let parts = core.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3,
                let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]),
                major >= 0, minor >= 0, patch >= 0
            else { return nil }
            self.rawValue = trimmed
            self.major = major
            self.minor = minor
            self.patch = patch
            self.suffix = suffix
        }

        public init(stringLiteral value: String) {
            guard let version = Self(rawValue: value) else {
                preconditionFailure("'\(value)' is not a valid major.minor.patch version")
            }
            self = version
        }

        /// Creates a version from its components. Components must be non-negative.
        public init(major: Int, minor: Int, patch: Int) {
            precondition(major >= 0 && minor >= 0 && patch >= 0, "Version components must be non-negative")
            self.init(rawValue: "\(major).\(minor).\(patch)")!
        }

        public static let v1_0_0: Self = "1.0.0"
        public static let v1_0_1: Self = "1.0.1"
        public static let v1_1_0: Self = "1.1.0"

        /// The most recent version these models were written against.
        public static let latest: Self = .v1_1_0

        /// Versions whose feature set is fully modelled by this library.
        public static let supportedFeatureSets: [(major: Int, minor: Int)] = [(1, 0), (1, 1)]

        /// `true` when the `major.minor` feature set is one this library understands.
        public var isSupported: Bool {
            Self.supportedFeatureSets.contains { $0.major == major && $0.minor == minor }
        }

        /// `true` for Arazzo 1.1 or later (async steps, selectors, `$self`, `querystring`, ...).
        public var supportsV1_1Features: Bool { (major, minor) >= (1, 1) }

        public var description: String { rawValue }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            (lhs.major, lhs.minor, lhs.patch, lhs.suffix) == (rhs.major, rhs.minor, rhs.patch, rhs.suffix)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(major)
            hasher.combine(minor)
            hasher.combine(patch)
            hasher.combine(suffix)
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let string: String
            if let value = try? container.decode(String.self) {
                string = value
            } else if let value = try? container.decode(Double.self) {
                // YAML authors sometimes write `arazzo: 1.0` unquoted.
                string = String(value)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "The `arazzo` field must be a version string.")
            }
            guard let version = Self(rawValue: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "'\(string)' is not a valid Arazzo version (expected major.minor.patch).")
            }
            self = version
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }
}

extension String {
    func trimmingWhitespace() -> String {
        var scalars = Substring(self)
        while let first = scalars.first, first.isWhitespace { scalars.removeFirst() }
        while let last = scalars.last, last.isWhitespace { scalars.removeLast() }
        return String(scalars)
    }
}
