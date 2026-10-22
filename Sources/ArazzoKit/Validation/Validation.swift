import JSONPath
extension Arazzo {
    /// A problem found while validating an Arazzo Description.
    public struct ValidationIssue: Error, Hashable, Sendable, CustomStringConvertible {
        public enum Severity: String, Hashable, Sendable, Comparable {
            /// Violates a MUST / REQUIRED rule of the specification.
            case error
            /// Violates a SHOULD / RECOMMENDED rule, or is likely a mistake.
            case warning

            public static func < (lhs: Self, rhs: Self) -> Bool { lhs == .warning && rhs == .error }
        }

        public let severity: Severity
        /// A JSON Pointer to the offending location, e.g. `/workflows/0/steps/2/parameters/1`.
        public let path: String
        public let message: String
        /// The identifier of the rule that produced the issue.
        public let rule: String

        public init(severity: Severity, path: String, message: String, rule: String) {
            self.severity = severity
            self.path = path
            self.message = message
            self.rule = rule
        }

        public var description: String {
            "[\(severity.rawValue)] \(path.isEmpty ? "/" : path): \(message) (\(rule))"
        }
    }

    /// Thrown by ``Document/validateOrThrow(using:failingOn:)`` when errors are found.
    public struct ValidationError: Error, Sendable, CustomStringConvertible {
        public let issues: [ValidationIssue]
        public var description: String {
            "The Arazzo Description is invalid:\n" + issues.map { "  - \($0)" }.joined(separator: "\n")
        }
    }

    /// A single validation rule. Create custom ones to enforce house style:
    /// ```swift
    /// let summaries = Arazzo.ValidationRule("workflow-summary") { document, report in
    ///     for (index, workflow) in document.workflows.enumerated() where workflow.summary == nil {
    ///         report.warning("/workflows/\(index)", "Every workflow should have a summary.")
    ///     }
    /// }
    /// let issues = document.validate(using: .default.adding(summaries))
    /// ```
    public struct ValidationRule: Sendable {
        public let name: String
        let check: @Sendable (Document, inout ValidationReporter) -> Void

        public init(_ name: String, check: @escaping @Sendable (Document, inout ValidationReporter) -> Void) {
            self.name = name
            self.check = check
        }
    }

    /// Collects issues for a rule.
    public struct ValidationReporter {
        let rule: String
        public private(set) var issues: [ValidationIssue] = []

        init(rule: String) { self.rule = rule }

        public mutating func error(_ path: String, _ message: String) {
            issues.append(.init(severity: .error, path: path, message: message, rule: rule))
        }

        public mutating func warning(_ path: String, _ message: String) {
            issues.append(.init(severity: .warning, path: path, message: message, rule: rule))
        }

        public mutating func report(_ severity: ValidationIssue.Severity, _ path: String, _ message: String) {
            issues.append(.init(severity: severity, path: path, message: message, rule: rule))
        }
    }

    /// A set of validation rules.
    public struct Validator: Sendable {
        public var rules: [ValidationRule]

        public init(rules: [ValidationRule]) {
            self.rules = rules
        }

        /// No rules at all.
        public static let blank = Validator(rules: [])

        /// Every built-in rule (MUST rules as errors, SHOULD rules as warnings).
        public static let `default` = Validator(rules: BuiltInRules.all)

        public func adding(_ rule: ValidationRule) -> Validator {
            Validator(rules: rules + [rule])
        }

        public func removing(_ ruleNames: String...) -> Validator {
            Validator(rules: rules.filter { !ruleNames.contains($0.name) })
        }

        public func validate(_ document: Document) -> [ValidationIssue] {
            rules.flatMap { rule in
                var reporter = ValidationReporter(rule: rule.name)
                rule.check(document, &reporter)
                return reporter.issues
            }
        }
    }
}

extension Arazzo.Document {
    /// Validates the description against the specification rules that the type system cannot express.
    public func validate(using validator: Arazzo.Validator = .default) -> [Arazzo.ValidationIssue] {
        validator.validate(self)
    }

    /// Throws ``Arazzo/ValidationError`` if validation finds issues of at least `severity`.
    public func validateOrThrow(
        using validator: Arazzo.Validator = .default, failingOn severity: Arazzo.ValidationIssue.Severity = .error
    ) throws {
        let issues = validate(using: validator).filter { $0.severity >= severity }
        if !issues.isEmpty { throw Arazzo.ValidationError(issues: issues) }
    }
}
