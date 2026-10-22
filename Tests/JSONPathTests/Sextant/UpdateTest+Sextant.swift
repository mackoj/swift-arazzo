// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Source: Tests/SextantTests/Jayway/UpdateTest.swift
//
// Adaptations: Sextant mutates parsed `JsonElement`s in place (`replace`, `remove`, `map`, `filter`,
// `forEach` with `append`/`set`/`rename`). `JSONValue` is a value type: the same operations are
// `replace(_:with:)`, `remove(_:)` and `map(_:_:)` (returning `nil` removes). `forEach` mutations are
// expressed with `map`.

import JSONPath
import Testing

private func jayway(_ path: String) throws -> JSONPath { try JSONPath(path, dialect: .jayway) }

private func document(_ json: String) throws -> JSONValue { try JSONValue(parsing: json) }

private func values(_ value: JSONValue, _ path: String) throws -> [JSONValue] {
    try jayway(path).values(in: value)
}

@Suite("Sextant: Update")
struct UpdateTestPorted: SextantTestCase {
    @Test func test_replace_index_in_array() throws {
        var json = try document(#"["Hello","World"]"#)
        try json.replace(jayway("$[0]"), with: "Goodbye")
        #expect(json.jsonString == #"["Goodbye","World"]"#)

        var both = try document(#"["Hello","World"]"#)
        for path in ["$[0]", "$[1]"] { try both.replace(jayway(path), with: "Goodbye") }
        #expect(both.jsonString == #"["Goodbye","Goodbye"]"#)

        var sequential = try document(#"["Hello","World"]"#)
        try sequential.replace(jayway("$[0]"), with: "Goodbye")
        try sequential.replace(jayway("$[1]"), with: "Moon")
        #expect(sequential.jsonString == #"["Goodbye","Moon"]"#)
    }

    @Test func test_foreach_index_in_array() throws {
        var total = 0
        try document("[0,1,2,3,4,5,6,7,8,9]").forEach(jayway("$[*]")) { total += $0.intValue ?? 0 }
        #expect(total == 45)

        var names = try document(#"["John","Jackie","Jason"]"#)
        try names.map(jayway("$[*]")) { $0.stringValue.map { .string($0.lowercased()) } }
        #expect(names.jsonString == #"["john","jackie","jason"]"#)
        try names.map(jayway("$[*]")) { $0.stringValue.map { .string($0.uppercased()) } }
        #expect(names.jsonString == #"["JOHN","JACKIE","JASON"]"#)
    }

    @Test func test_filter_index_in_array() throws {
        var json = try document(#"["Hello","World"]"#)
        // `cond ? $0 : nil` would infer `nil` as `JSONValue.null`; return `Optional.none` explicitly.
        try json.map(jayway("$[0]")) { value -> JSONValue? in
            if value == "Goodbye" { return value }
            return nil
        }
        #expect(json.jsonString == #"["World"]"#)
    }

    @Test func test_an_array_child_property_can_be_updated() throws {
        var json = try document(jsonDocument)
        try json.replace(jayway("$.store.book[*].display-price"), with: 1)
        #expect(try values(json, "$.store.book[*].display-price") == [1, 1, 1, 1])
    }

    @Test func test_an_root_property_can_be_updated() throws {
        var json = try document(jsonDocument)
        try json.replace(jayway("$.int-max-property"), with: 1)
        #expect(try values(json, "$.int-max-property") == [1])
    }

    @Test func test_an_deep_scan_can_update() throws {
        var json = try document(jsonDocument)
        try json.replace(jayway("$..display-price"), with: 1)
        #expect(try values(json, "$..display-price") == [1, 1, 1, 1, 1])
    }

    @Test func test_an_filter_can_update() throws {
        var json = try document(jsonDocument)
        try json.replace(jayway("$.store.book[?(@.display-price)].display-price"), with: 1)
        #expect(try values(json, "$.store.book[?(@.display-price)].display-price") == [1, 1, 1, 1])
    }

    @Test func test_a_path_can_be_deleted() throws {
        var json = try document(jsonDocument)
        try json.remove(jayway("$.store.book[*].display-price"))
        #expect(try values(json, "$.store.book[*].display-price") == [])
    }

    @Test func test_an_array_can_be_updated() throws {
        var json = try document("[0,1,2,3]")
        try json.replace(jayway("$[?(@ == 1)]"), with: 9)
        #expect(try values(json, "$[*]") == [0, 9, 2, 3])
        #expect(json.jsonString == "[0,9,2,3]")
    }

    @Test func test_an_array_index_can_be_updated() throws {
        var json = try document(jsonDocument)
        try json.replace(jayway("$.store.book[0]"), with: "a")
        #expect(try values(json, "$.store.book[0]") == ["a"])
    }

    @Test func test_an_array_slice_can_be_updated() throws {
        var json = try document(jsonDocument)
        try json.replace(jayway("$.store.book[0:2]"), with: "a")
        #expect(try values(json, "$.store.book[0:2]") == ["a", "a"])
    }

    @Test func test_an_array_criteria_can_be_updated() throws {
        var json = try document(jsonDocument)
        try json.replace(jayway("$.store.book[?(@.category == 'fiction')]"), with: "a")
        #expect(try values(json, "$.store.book[?(@ == 'a')]") == ["a", "a", "a"])
    }

    @Test func test_an_array_criteria_can_be_deleted() throws {
        var json = try document(jsonDocument)
        try json.remove(jayway("$.store.book[?(@.category == 'fiction')]"))
        #expect(try values(json, "$.store.book[*].category") == ["reference"])
    }

    @Test func test_multi_prop_delete() throws {
        var json = try document(jsonDocument)
        try json.remove(jayway("$.store.book[*]['author','category']"))
        // Adapted: the original query has a stray trailing `]`, which Sextant ignores and we reject.
        let remaining = try values(json, "$.store.book[*]['author','category','display-price']")
        #expect(sextantEqual(remaining, [8.95, 12.99, 8.99, 22.99]))
    }

    @Test func test_multi_prop_update_not_all_defined() throws {
        var json = try document(jsonDocument)
        try json.replace(jayway("$.store.book[*]['author', 'isbn']"), with: "a")
        #expect(try values(json, "$.store.book[*]['author', 'isbn']") == ["a", "a", "a", "a", "a", "a"])
    }

    @Test func test_add_to_array() throws {
        var json = try document(jsonDocument)
        try json.map(jayway("$.store.book")) { $0.arrayValue.map { .array($0 + [1]) } ?? $0 }
        #expect(try values(json, "$.store.book[4]") == [1])
    }

    @Test func test_add_to_object() throws {
        var json = try document(jsonDocument)
        try json.map(jayway("$.store.book[0]")) { book in
            guard var object = book.objectValue else { return book }
            object["new-key"] = "new-value"
            return .object(object)
        }
        #expect(try values(json, "$.store.book[0].new-key") == ["new-value"])
    }

    @Test func test_item_can_be_added_to_root_array() throws {
        var json = try document("[1,2]")
        try json.map(jayway("$")) { $0.arrayValue.map { .array($0 + [3]) } ?? $0 }
        #expect(try values(json, "$") == [[1, 2, 3]])
    }

    @Test func test_key_val_can_be_added_to_root_object() throws {
        var json = try document(#"{"a":"a-val"}"#)
        try json.map(jayway("$")) { root in
            guard var object = root.objectValue else { return root }
            object["new-key"] = "new-value"
            return .object(object)
        }
        #expect(try values(json, "$.new-key") == ["new-value"])
    }

    @Test func test_add_to_object_on_array() throws {
        var json = try document(jsonDocument)
        try json.map(jayway("$.store.book")) { value in
            guard var object = value.objectValue else { return value }  // not an object: unchanged
            object["new-key"] = "new-value"
            return .object(object)
        }
        #expect(try values(json, "$.store.book.new-key") == [])
    }

    @Test func test_add_to_array_on_object() throws {
        var json = try document(jsonDocument)
        try json.map(jayway("$.store.book[0]")) { $0.arrayValue.map { .array($0 + ["new-value"]) } ?? $0 }
        #expect(
            try values(json, "$.store.book[0]") == [
                [
                    "category": "reference", "author": "Nigel Rees", "title": "Sayings of the Century",
                    "display-price": 8.95,
                ]
            ])
    }

    @Test func test_root_object_can_be_updated() throws {
        var json = try document(#"{"a":"a-val"}"#)
        try json.replace(jayway("$[?(@.a == 'a-val')]"), with: 1)
        #expect(try values(json, "$") == [1])
    }

    private func renaming(_ old: String, to new: String) -> (JSONValue) -> JSONValue? {
        { value in
            guard case .object(let object) = value, let moved = object[old] else { return value }
            var renamed = OrderedDictionary<String, JSONValue>()
            for (key, child) in object { renamed[key == old ? new : key] = key == old ? moved : child }
            return .object(renamed)
        }
    }

    @Test func test_a_path_can_be_renamed() throws {
        var json = try document(jsonDocument)
        try json.map(jayway("$.store"), renaming("book", to: "updated-book"))
        #expect(try values(json, "$.store.book[*]").count == 0)
        #expect(try values(json, "$.store.updated-book[*]").count == 4)
    }

    @Test func test_keys_in_root_containing_map_can_be_renamed() throws {
        var json = try document(jsonDocument)
        try json.map(jayway("$"), renaming("store", to: "new-store"))
        #expect(try values(json, "$.store[*]").count == 0)
        #expect(try values(json, "$.new-store[*]").count == 2)
    }

    @Test func test_map_array_items_can_be_renamed() throws {
        var json = try document(jsonDocument)
        try json.map(jayway("$.store.book[*]"), renaming("category", to: "renamed-category"))
        #expect(try values(json, "$.store.book[*].category").count == 0)
        #expect(try values(json, "$.store.book[*].renamed-category").count == 4)
    }

    @Test func test_non_map_array_items_cannot_be_renamed() throws {
        var json = try document("[1,2]")
        try json.map(jayway("$[*]"), renaming("oldKey", to: "newKey"))
        #expect(try values(json, "$") == [[1, 2]])
    }

    @Test func test_multiple_properties_cannot_be_renamed() throws {
        var json = try document(jsonDocument)
        #expect(try values(json, "$.store.book[*]['author', 'category']").count == 8)
        try json.map(jayway("$.store.book[*]['author', 'category']"), renaming("old-key", to: "new-key"))
        #expect(try values(json, "$.store.book[*]['author', 'category']").count == 8)
    }

    @Test func test_root_can_be_mapped() throws {
        var json = try document(jsonDocument)
        try json.map(jayway("$")) { _ in 1 }
        #expect(try values(json, "$") == [1])
    }

    @Test func test_single_match_value_can_be_mapped() throws {
        var json = try document(jsonDocument)
        try json.map(jayway("$.string-property")) { .string(($0.stringValue ?? "") + "Converted") }
        #expect(try values(json, "$.string-property") == ["string-valueConverted"])
    }

    @Test func test_object_can_be_mapped() throws {
        var json = try document(jsonDocument)
        try json.map(jayway("$..book")) { .string($0.jsonString + "Converted") }
        let book = try #require(try values(json, "$..book").first?.stringValue)
        #expect(book.hasSuffix("Converted"))
    }

    @Test func test_multi_match_path_can_be_mapped() throws {
        var json = try document(jsonDocument)
        try json.map(jayway("$..display-price")) { .string($0.jsonString + "Converted") }
        #expect(
            sextantEqual(
                try values(json, "$..display-price"),
                ["8.95Converted", "12.99Converted", "8.99Converted", "22.99Converted", "19.95Converted"]))
    }
}
