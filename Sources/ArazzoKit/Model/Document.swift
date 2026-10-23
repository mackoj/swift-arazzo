import JSONPath
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Arazzo {
    /// The root object of an Arazzo Description (the "Arazzo Specification Object").
    public struct Document: Hashable, Sendable, VendorExtendable {
        /// The version of the Arazzo Specification the description uses (`arazzo`).
        public var arazzo: SpecificationVersion
        /// The self-assigned URI of this description (`$self`, Arazzo 1.1+).
        public var selfURI: String?
        public var info: Info
        public var sourceDescriptions: [SourceDescription]
        public var workflows: [Workflow]
        public var components: Components
        public var vendorExtensions: VendorExtensions

        public init(
            arazzo: SpecificationVersion = .latest,
            selfURI: String? = nil,
            info: Info,
            sourceDescriptions: [SourceDescription],
            workflows: [Workflow],
            components: Components = .init(),
            vendorExtensions: VendorExtensions = [:]
        ) {
            self.arazzo = arazzo
            self.selfURI = selfURI
            self.info = info
            self.sourceDescriptions = sourceDescriptions
            self.workflows = workflows
            self.components = components
            self.vendorExtensions = vendorExtensions
        }
    }
}

extension Arazzo.Document: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case arazzo
        case selfURI = "$self"
        case info
        case sourceDescriptions
        case workflows
        case components
    }

    public init(from decoder: any Decoder) throws {
        try decoder.ensureNoUnknownKeys(CodingKeys.self, objectName: "Arazzo Specification Object")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        arazzo = try container.decode(Arazzo.SpecificationVersion.self, forKey: .arazzo)
        selfURI = try container.decodeIfPresent(String.self, forKey: .selfURI)
        info = try container.decode(Arazzo.Info.self, forKey: .info)
        sourceDescriptions = try container.decode([Arazzo.SourceDescription].self, forKey: .sourceDescriptions)
        workflows = try container.decode([Arazzo.Workflow].self, forKey: .workflows)
        components = try container.decodeIfPresent(Arazzo.Components.self, forKey: .components) ?? .init()
        vendorExtensions = try decoder.decodeVendorExtensions()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(arazzo, forKey: .arazzo)
        try container.encodeIfPresent(selfURI, forKey: .selfURI)
        try container.encode(info, forKey: .info)
        try container.encode(sourceDescriptions, forKey: .sourceDescriptions)
        try container.encode(workflows, forKey: .workflows)
        if !components.isEmpty { try container.encode(components, forKey: .components) }
        try encoder.encodeVendorExtensions(vendorExtensions)
    }
}

// MARK: - JSON convenience

extension Arazzo.Document {
    /// Decodes an Arazzo Description from JSON data. Object member order is preserved.
    public init(json data: Data, options: Arazzo.DecodingOptions = .init()) throws {
        let value: JSONValue
        do {
            value = try JSONValue(parsing: data)
        } catch {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "\(error)", underlyingError: error))
        }
        self = try JSONValueDecoder(userInfo: [Arazzo.DecodingOptions.key: options]).decode(Self.self, from: value)
    }

    /// Encodes the description as JSON, keeping field and map order (unless `sortedKeys`).
    public func jsonData(prettyPrinted: Bool = true, sortedKeys: Bool = false) throws -> Data {
        Data(try jsonValue().jsonString(prettyPrinted: prettyPrinted, sortedKeys: sortedKeys).utf8)
    }

    /// The description as a `JSONValue` tree (from the `JSONPath` module).
    public func jsonValue() throws -> JSONValue {
        try JSONValueEncoder().encode(self)
    }
}

// MARK: - Lookup

extension Arazzo.Document {
    /// The workflow with the given `workflowId` (case-sensitive).
    public func workflow(id: String) -> Arazzo.Workflow? {
        workflows.first { $0.workflowId == id }
    }

    /// The source description with the given `name`.
    public func sourceDescription(named name: String) -> Arazzo.SourceDescription? {
        sourceDescriptions.first { $0.name == name }
    }

    /// Source descriptions that are not other Arazzo documents.
    public var apiSourceDescriptions: [Arazzo.SourceDescription] {
        sourceDescriptions.filter { $0.type != .arazzo }
    }
}
