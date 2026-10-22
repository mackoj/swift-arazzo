// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Source: Tests/SextantTests/Jayway/ExamplesTest.swift, ThreadedTest.swift, PerformanceTest.swift
//
// Adaptations: Sextant-specific conveniences (tuple results, `Decodable` coercion, `parsed {}` blocks,
// `Date` parsing) are expressed with `JSONValue` and `Codable`. The threaded and performance tests read
// a large local file in Sextant; here they run against a generated document.

import Foundation
import JSONPath
import Testing

private func jayway(_ path: String) throws -> JSONPath { try JSONPath(path, dialect: .jayway) }

@Suite("Sextant: Examples")
struct ExamplesTestPorted: SextantTestCase {
    @Test func testSimple0() throws {
        let results = try #require(sextantQuery(#"["Hello","World"]"#, "$[0]"))
        #expect(results[0] == "Hello")
    }

    @Test func testSimple2() throws {
        let data: JSONValue = ["Hello", "World"]
        #expect(try jayway("$[0]").values(in: data) == ["Hello"])
    }

    @Test func testSimple3_multiplePropertiesInOrder() throws {
        let json = #"{"name":"Rocco","age":42}"#
        #expect(sextantQuery(json, "$.['name','age']") == ["Rocco", 42])
        #expect(sextantQuery(json, "$.['name','age2']") == ["Rocco"])
    }

    @Test func testSimple4_decodable() throws {
        struct Person: Decodable {
            let name: String
            let age: Int
        }
        let json = #"{"data":{"people":[{"name":"Rocco","age":42},{"name":"John","age":12},{"name":"Elizabeth","age":35},{"name":"Victoria","age":85}]}}"#
        let matches = try #require(sextantQuery(json, "$..[?(@.name)]"))
        let persons = try JSONDecoder().decode([Person].self, from: JSONEncoder().encode(matches))
        #expect(persons[0].name == "Rocco")
        #expect(persons[0].age == 42)
        #expect(persons[2].name == "Elizabeth")
        #expect(persons[2].age == 35)
    }

    @Test func testSimple5_combineQueries() throws {
        let json1 = #"{"error": "invalid_request", "error_description": "Mismatching redirect URI."}"#
        let json2 = #"{"errors":[{"title":"Error!","detail":"Error format 2"}]}"#
        let queries = ["$.['error','error_description']", "$.errors[0].['title','detail']"]
        func union(_ json: String) -> [JSONValue] { queries.flatMap { sextantQuery(json, $0) ?? [] } }
        #expect(sextantEqual(union(json1), ["Mismatching redirect URI.", "invalid_request"]))
        #expect(sextantEqual(union(json2), ["Error format 2", "Error!"]))
    }

    @Test func testSimple6_noMatches() throws {
        let json = #"{"access_token":"aex-0u-7Yq09sBls123456789","expires_in":2678400,"token_type":"Bearer"}"#
        #expect(sextantQuery(json, "$.['error','error_description']") == [])
        #expect(sextantQuery(json, "$.errors[0].['title','detail']") == [])
    }

    @Test func testSimple7_missingMembers() throws {
        let json = #"{"data":{"attributes":{"about":null,"first_name":"John","full_name":"John Doe","last_name":"Doe","thumb_url":"https://www.example.com/image.png"}}}"#
        let results = try #require(sextantQuery(json, "$.data.attributes['full_name','first_name','last_name','email','thumb_url']"))
        #expect(results == ["John Doe", "John", "Doe", "https://www.example.com/image.png"])
    }

    @Test func testSimple8() throws {
        let json = #"{"data":{"attributes":{"about":null,"social_connections":{"deviantart":null}},"id":"66480799","type":"user"}}"#
        #expect(sextantQuery(json, "$.data.id") == ["66480799"])
    }

    @Test func testSimple9() throws {
        let json = #"{"DtCutOff":"2018-01-01 00:00:00","ServiceGroups":[{"ServiceName":"Service1","DtUpdate":"2021-11-22 00:00:00","OrderNumber":"123456","Active":"true"},{"ServiceName":"Service2","DtUpdate":"2021-11-20 00:00:00","OrderNumber":"123456","Active":true},{"ServiceName":"Service3","DtUpdate":"2021-11-10 00:00:00","OrderNumber":"123456","Active":false}]}"#
        // Adapted: Sextant coerces the string "true" to a Bool and parses dates.
        #expect(sextantQuery(json, "$.ServiceGroups[*][?(@.ServiceName=='Service1')].Active") == ["true"])
        #expect(sextantQuery(json, "$.ServiceGroups[*][?(@.ServiceName=='Service1')].DtUpdate") == ["2021-11-22 00:00:00"])
    }

    @Test func testSimple10_removeAndMap() throws {
        var root = try JSONValue(parsing: #"{"data":{"people":[{"name":"Rocco","age":42,"gender":"m"},{"name":"John","age":12,"gender":"m"},{"name":"Elizabeth","age":35,"gender":"f"},{"name":"Victoria","age":85,"gender":"f"}]}}"#)
        try root.remove(jayway("$..people[?(@.gender=='f')]"))
        try root.map(jayway("$..age")) { $0.intValue.map { .integer($0 + 1) } ?? $0 }
        try root.map(jayway("$..name")) { $0.stringValue.map { .string($0.lowercased()) } }
        #expect(root.jsonString == #"{"data":{"people":[{"name":"rocco","age":43,"gender":"m"},{"name":"john","age":13,"gender":"m"}]}}"#)
    }

    @Test func testSimple11_singleMap() throws {
        var root = try JSONValue(parsing: #"{"data":{"people":[{"name":"Rocco","age":42,"gender":"m"},{"name":"John","age":12,"gender":"m"},{"name":"Elizabeth","age":35,"gender":"f"},{"name":"Victoria","age":85,"gender":"f"}]}}"#)
        try root.map(jayway("$..people[*] ")) { person in
            guard var object = person.objectValue, object["gender"] == "m" else { return nil }
            if let age = object["age"]?.intValue { object["age"] = .integer(age + 1) }
            if let name = object["name"]?.stringValue { object["name"] = .string(name.lowercased()) }
            return .object(object)
        }
        #expect(root.jsonString == #"{"data":{"people":[{"name":"rocco","age":43,"gender":"m"},{"name":"john","age":13,"gender":"m"}]}}"#)
    }

    @Test func testSimple12_replaceWithAnyStructure() throws {
        var root = try JSONValue(parsing: #"{"someValue": ["elem1", "elem2", "elem3"]}"#)
        try root.map(jayway("$.someValue")) { _ in ["elem4", "elem5"] }
        #expect(root.jsonString == #"{"someValue":["elem4","elem5"]}"#)
    }

    @Test func testSimple14_heterogeneousArray() throws {
        let json = try JSONValue(parsing: #"[{"name":"add","inputs":[3,4]},{"name":"subtract","inputs":[6,3]},{"echo":"Hello, world"},{"name":"increment","input":41},{"echo":"Hello, world"}]"#)
        let operations: [String: (JSONValue) -> Int?] = [
            "add": { input in
                guard let lhs = input["inputs"]?[0]?.intValue, let rhs = input["inputs"]?[1]?.intValue else { return nil }
                return lhs + rhs
            },
            "subtract": { input in
                guard let lhs = input["inputs"]?[0]?.intValue, let rhs = input["inputs"]?[1]?.intValue else { return nil }
                return lhs - rhs
            },
            "increment": { input in input["input"]?.intValue.map { $0 + 1 } },
        ]
        var results: [Int] = []
        try json.forEach(jayway("$[?(@.name)]")) { operation in
            if let name = operation["name"]?.stringValue, let function = operations[name] {
                results.append(function(operation) ?? 0)
            }
        }
        #expect(results == [7, 3, 42])
    }

    @Test func testSimple15_elements() throws {
        let root = try JSONValue(parsing: #"[{"name":"Rocco","age":42},{"name":"John","age":36}]"#)
        let persons = try jayway("$[*]").values(in: root)
        #expect(persons[0]["name"] == "Rocco")
        #expect(persons[0]["age"] == 42)
        #expect(persons[1]["name"] == "John")
        #expect(try jayway("$[1]").firstValue(in: root)?["age"] == 36)
    }

    @Test func testSimple16_codable() throws {
        struct LikedPost: Codable, Equatable {
            let title: String
            let timestamp: Int
        }
        let root = try JSONValue(parsing: #"[{"title":"Post 1","timestamp":1},{"title":"Post 2","timestamp":2}]"#)
        let posts = try JSONDecoder().decode([LikedPost].self, from: JSONEncoder().encode(try jayway("$[*]").values(in: root)))
        #expect(posts == [LikedPost(title: "Post 1", timestamp: 1), LikedPost(title: "Post 2", timestamp: 2)])
        let titles = try jayway("$..title").values(in: root).compactMap(\.stringValue)
        let timestamps = try jayway("$..timestamp").values(in: root).compactMap(\.intValue)
        #expect(titles == ["Post 1", "Post 2"])
        #expect(timestamps == [1, 2])
    }

    @Test func testSimple17_validate() {
        #expect(JSONPath.validate("$", dialect: .jayway) == nil)
        #expect(JSONPath.validate("", dialect: .jayway) == "Path must start with $ or @")
        #expect(JSONPath.validate("$.", dialect: .jayway) == "Path must not end with a '.' or '..'")
        #expect(JSONPath.validate("$..", dialect: .jayway) == "Path must not end with a '.' or '..'")
        #expect(JSONPath.validate("$.store.book[[", dialect: .jayway) == "Could not parse token starting at position 12.")
        #expect(JSONPath.validate("@.category", dialect: .jayway) == nil)
    }

    @Test func testSimple18_mapToScalar() throws {
        var root = try JSONValue(parsing: #"{"users":[{"name":"John","age":30},{"name":"Jane","age":29}]}"#)
        try root.map(jayway("$.users[0]")) { _ in "x" }
        #expect(root.jsonString == #"{"users":["x",{"name":"Jane","age":29}]}"#)
    }

    @Test func testSimple19_exists() throws {
        let root = try JSONValue(parsing: #"{"users":[{"name":"John","age":30},{"name":"Jane","age":29}]}"#)
        #expect(try jayway("$..nothing").matches(root) == false)
        #expect(try jayway("$..name").matches(root))
        #expect(try jayway("$..nothing").firstValue(in: root) == nil)
        #expect(try jayway("$..name").firstValue(in: root) == "John")
    }
}

/// Generates a document similar in shape to the GitHub events archive used by Sextant's
/// performance tests.
private let largeDocument: JSONValue = {
    var events: [JSONValue] = []
    for index in 0..<2_000 {
        let commits: [JSONValue] = (0..<(index % 3)).map { commit in
            ["sha": .string("sha-\(index)-\(commit)"), "author": ["name": .string("author \(commit)")], "type": "commit"]
        }
        events.append([
            "id": .string(String(index)),
            "type": index % 2 == 0 ? "PushEvent" : "WatchEvent",
            "actor": ["id": .integer(index), "login": .string("user\(index)")],
            "repo": ["id": .integer(index * 10), "name": .string("repo/\(index)")],
            "payload": ["size": .integer(index % 3), "commits": .array(commits)],
        ])
    }
    return .array(events)
}()

@Suite("Sextant: Threaded & Performance")
struct ThreadedAndPerformanceTestPorted {
    @Test func testThreads0() async throws {
        let path = try jayway("$..type")
        let expected = try path.values(in: largeDocument).count
        // Every event has a type, and each commit has one: 2,000 + Σ(index % 3) = 3,999.
        #expect(expected == 3_999)
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    var count = 0
                    for _ in 0..<5 { count = try path.values(in: largeDocument).count }
                    return count
                }
            }
            for try await count in group { #expect(count == expected) }
        }
    }

    @Test func testPerformance0() throws {
        let clock = ContinuousClock()
        var count = 0
        let elapsed = try clock.measure {
            count = try jayway("$[?(@.type == 'PushEvent')].payload.commits[*].sha").values(in: largeDocument).count
        }
        #expect(count == (0..<2_000).filter { $0 % 2 == 0 }.map { $0 % 3 }.reduce(0, +))
        #expect(elapsed < .seconds(5))
    }

    @Test func testPerformance1() throws {
        #expect(try jayway("$..[?(@.payload.commits.length() == 1)]").values(in: largeDocument).count == 667)
        #expect(try jayway("$[*].actor.login").values(in: largeDocument).count == 2_000)
    }
}
