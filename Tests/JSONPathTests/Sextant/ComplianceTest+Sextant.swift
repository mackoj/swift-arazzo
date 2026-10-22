// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/ComplianceTest.swift

import JSONPath
import Testing



@Suite("Sextant: Compliance")
struct ComplianceTestPorted: SextantTestCase {
    
    @Test func test_one() throws {
        let json = #"{"a":"a","b":"b","c d":"e"}"#
        
        expectValues(json, "$.a", ["a"])
        expectValues(json, "$.*", ["a","b","e"])
        expectValues(json, "$[*]", ["a","b","e"])
        expectValues(json, "$['a']", ["a"])
        expectValues(json, "$.['c d']", ["e"])
        expectValues(json, "$[*]", ["a","b","e"])
    }
    
    @Test func test_two() throws {
        let json = #"[ 1, "2", 3.14, true, null ]"#
        
        expectValues(json, "$[0]", [1])
        expectValues(json, "$[4]", [nil])
        expectValues(json, "$[*]", [1, "2", 3.14, true, nil])
        expectValues(json, "$[-1:]", [nil])
    }
    
    @Test func test_three() throws {
        let json = #"{"points":[{"id":"i1","x":4,"y":-5},{"id":"i2","x":-2,"y":2,"z":1},{"id":"i3","x":8,"y":3},{"id":"i4","x":-6,"y":-1},{"id":"i5","x":0,"y":2,"z":1},{"id":"i6","x":1,"y":4}]}"#
        
        expectValues(json, "$.points[1]", [["id":"i2","x":-2,"y":2,"z":1]])
        expectValues(json, "$.points[4].x", [0])
        expectValues(json, "$.points[?(@.id == 'i4')].x", [-6])
        expectValues(json, "$.points[*].x", [4,-2,8,-6,0,1])
        expectValues(json, "$.points[?(@.z)].id", ["i2","i5"])
    }
    
    @Test func test_four() throws {
        let json = #"{"menu":{"header":"SVG Viewer","items":[{"id":"Open"},{"id":"OpenNew","label":"Open New"},null,{"id":"ZoomIn","label":"Zoom In"},{"id":"ZoomOut","label":"Zoom Out"},{"id":"OriginalView","label":"Original View"},null,{"id":"Quality"},{"id":"Pause"},{"id":"Mute"},null,{"id":"Find","label":"Find..."},{"id":"FindAgain","label":"Find Again"},{"id":"Copy"},{"id":"CopyAgain","label":"Copy Again"},{"id":"CopySVG","label":"Copy SVG"},{"id":"ViewSVG","label":"View SVG"},{"id":"ViewSource","label":"View Source"},{"id":"SaveAs","label":"Save As"},null,{"id":"Help"},{"id":"About","label":"About Adobe CVG Viewer..."}]}}"#
        
        expectCount(json, "$.menu.items[?(@)]", 22)
        expectValues(json, "$.menu.items[?(@.id == 'ViewSVG')].id", ["ViewSVG"])
        expectValues(json, "$.menu.items[?(@ && @.id == 'ViewSVG')].id", ["ViewSVG"])
        expectValues(json, "$.menu.items[?(@ && @.id && !@.label)].id", ["Open","Quality","Pause","Mute","Copy","Help"])
    }
    
    // Further tests to ensure compliance with https://cburgmer.github.io/json-path-comparison/
    
    @Test func test_JsonPathComparison1() throws {
        let json = #"{ ":": 42, "more": "string", "a": 1, "b": 2, "c": 3, "1:3": "nice" }"#
        expectValues(json, "$[1:3]", [])
    }
    
    @Test func test_JsonPathComparison2() throws {
        let json = #"{ ":": 42, "more": "string" }"#
        expectValues(json, "$[:]", [])
    }
    
    @Test func test_JsonPathComparison3() throws {
        let json = #"[ "first", "second", "third", "forth", "fifth" ]"#
        expectValues(json, "$[0:3:0]", ["first", "second", "third"])
    }
    
    @Test func test_JsonPathComparison4() throws {
        let json = #"[ "first", "second", "third", "forth", "fifth" ]"#
        expectValues(json, "$[::2]", ["first", "third", "fifth"])
    }
    
    @Test func test_JsonPathComparison5() throws {
        let json = #"{ "key": "value" }"#
        expectValues(json, "$['missing']", [])
    }
    
    @Test func test_JsonPathComparison6() throws {
        let json = #"{ "u\u0308": 42 }"#
        // Note: this not matching is correct, because even though ü and ü look exactly
        // the same they are comprised differently. This test will fail on the non-spanker
        // version of Sextant, as we're not in control of the utf8 -> unicode translation
        expectValues(json, "$['ü']", [])
        
        let json2 = #"{ "u": 42 }"#
        expectValues(json2, "$['u']", [42])
    }
        
    @Test func test_JsonPathComparison8() throws {
        let json = #"[ "one element" ]"#
        expectValues(json, "$[-2]", [])
    }
    
    @Test func test_JsonPathComparison9() throws {
        let json = #"[]"#
        expectValues(json, "$[-1]", [])
    }
    
    @Test func test_JsonPathComparison10() throws {
        let json = #"{ "0": "value" }"#
        expectValues(json, "$[0]", [])
    }
    
    @Test func test_JsonPathComparison11() throws {
        let json = #"[ "one element" ]"#
        expectValues(json, "$[1]", [])
    }
    
    @Test func test_JsonPathComparison12() throws {
        let json = #""Hello World""#
        expectValues(json, "$[0]", [])
    }
    
    @Test func test_JsonPathComparison13() throws {
        let json = #"{ "single'quote": "value" }"#
        expectInvalid(json, "$['single'quote']")
    }
    
    @Test func test_JsonPathComparison14() throws {
        let json = #"{ "another": "entry" }"#
        expectValues(json, "$['*']", [])
    }
    
    @Test func test_JsonPathComparison15() throws {
        let json = #"{ "one": { "key": "value" }, "two": { "some": "more", "key": "other value" }, "two.some": "42", "two'.'some": "43" }"#
        expectInvalid(json, "$['two'.'some']")
    }
    
    @Test func test_JsonPathComparison16() throws {
        let json = #"{ "one": { "key": "value" }, "two": { "some": "more", "key": "other value" }, "two.some": "42" }"#
        expectInvalid(json, "$[two.some]")
    }
    
    @Test func test_JsonPathComparison17() throws {
        let json = #"{ "key": "value" }"#
        expectInvalid(json, "$[key]")
    }
    
    @Test func test_JsonPathComparison18() throws {
        let json = #"{ "key": "value", "other": { "key": [ { "key": 42 } ] } }"#
        expectInvalid(json, "$.[key]")
    }
    
    @Test func test_JsonPathComparison19() throws {
        let json = #"{ "k": [ { "key": "some value" }, { "key": 42 } ], "kk": [ [ { "key": 100 }, { "key": 200 }, { "key": 300 } ], [ { "key": 400 }, { "key": 500 }, { "key": 600 } ] ], "key": [ 0, 1 ] }"#
        let result = try #require(sextantQuery(json, "$..[1].key")).compactMap(\.intValue)
        #expect(result.sorted() == [42, 200, 500])
    }
    
    @Test func test_JsonPathComparison20() throws {
        let json = #"{ "object": { "key": "value", "array": [ { "key": "something" }, { "key": { "key": "russian dolls" } } ] }, "key": "top" }"#
        expectInvalid(json, "$...key")
    }
    
    @Test func test_JsonPathComparison21() throws {
        let json = #"[ 0, 1 ]"#
        expectValues(json, "$.key", [])
    }
    
    @Test func test_JsonPathComparison22() throws {
        let json = #"[ { "id": 2 } ]"#
        expectValues(json, "$.id", [])
    }
    
    @Test func test_JsonPathComparison23() throws {
        let json = #"[ { "d": 1 }, { "d": 2 }, { "d": 1 }, { "d": 3 }, { "d": 4 } ]"#
        expectValues(json, "$[?(@.d in [2, 3])]", [ [ "d": 2 ], [ "d": 3 ] ])
    }
    
    @Test func test_JsonPathComparison24() throws {
        let json = #"[ { "d": [ 1, 2, 3 ] }, { "d": [ 2 ] }, { "d": [ 1 ] }, { "d": [ 3, 4 ] }, { "d": [ 4, 2 ] } ]"#
        expectValues(json, "$[?(2 in @.d)]", [ [ "d": [ 1, 2, 3 ] ], [ "d": [ 2 ] ], [ "d": [ 4, 2 ] ] ])
    }
    
    @Test func test_JsonPathComparison25() throws {
        let json = #"[ { "title": "Sayings of the Century", "bookmarks": [ { "page": 40 } ] }, { "title": "Sword of Honour", "bookmarks": [ { "page": 35 }, { "page": 45 } ] }, { "title": "Moby Dick", "bookmarks": [ { "page": 3035 }, { "page": 45 } ] } ]"#
        expectValues(json, "$[*].bookmarks[?(@.page == 45)]^^^", [])
    }
    
    @Test func test_JsonPathComparison26() throws {
        let json = #"[{"d": 1}, {"d": 2}, {"d": 1}, {"d": 3}, {"d": 4}]"#
        expectValues(json, "$[?(@.d in [2, 3])]", [["d":2],["d":3]])
    }
    
    @Test func test_JsonPathComparison27() throws {
        let json = #"[{"d": [1, 2, 3]}, {"d": [2]}, {"d": [1]}, {"d": [3, 4]}, {"d": [4, 2]}]"#
        expectValues(json, "$[?(2 in @.d)]", [["d":[1,2,3]],["d":[2]],["d":[4,2]]])
    }
    
    @Test func test_JsonPathComparison28() throws {
        let json = #"[{"repo":{"id":28688495,"name":"petroav/6.828","url":"https://api.github.com/repos/petroav/6.828"},"actor":{"id":665991,"login":"petroav","avatar_url":"https://avatars.githubusercontent.com/u/665991?","url":"https://api.github.com/users/petroav","gravatar_id":""},"public":true,"id":"2489651045","created_at":"2015-01-01T15:00:00Z","payload":{"master_branch":"master","pusher_type":"user","description":"Solution to homework and assignments from MIT's 6.828 (Operating Systems Engineering). Done in my spare time.","ref_type":"branch","ref":"master"},"type":"CreateEvent"},{"repo":{"id":28671719,"name":"rspt/rspt-theme","url":"https://api.github.com/repos/rspt/rspt-theme"},"actor":{"id":3854017,"login":"rspt","avatar_url":"https://avatars.githubusercontent.com/u/3854017?","url":"https://api.github.com/users/rspt","gravatar_id":""},"public":true,"id":"2489651051","created_at":"2015-01-01T15:00:01Z","payload":{"before":"437c03652caa0bc4a7554b18d5c0a394c2f3d326","ref":"refs/heads/master","push_id":536863970,"size":1,"distinct_size":1,"head":"6b089eb4a43f728f0a594388092f480f2ecacfcd","commits":[{"author":{"email":"5c682c2d1ec4073e277f9ba9f4bdf07e5794dabe@rspt.ch","name":"rspt"},"message":"Fix main header height on mobile","url":"https://api.github.com/repos/rspt/rspt-theme/commits/6b089eb4a43f728f0a594388092f480f2ecacfcd","distinct":true,"sha":"6b089eb4a43f728f0a594388092f480f2ecacfcd"}]},"type":"PushEvent"},{"repo":{"id":28270952,"name":"izuzero/xe-module-ajaxboard","url":"https://api.github.com/repos/izuzero/xe-module-ajaxboard"},"actor":{"id":6339799,"login":"izuzero","avatar_url":"https://avatars.githubusercontent.com/u/6339799?","url":"https://api.github.com/users/izuzero","gravatar_id":""},"public":true,"id":"2489651053","created_at":"2015-01-01T15:00:01Z","payload":{"before":"590433109f221a96cf19ea7a7d9a43ca333e3b3e","ref":"refs/heads/develop","push_id":536863972,"size":1,"distinct_size":1,"head":"ec819b9df4fe612bb35bf562f96810bf991f9975","commits":[{"author":{"email":"df05f55543db3c62cf64f7438018ec37f3605d3c@gmail.com","name":"Eunsoo Lee"},"message":"20 게시글 및 댓글 삭제 시 새로고침이 되는 문제 해결\n\n원래 의도는 새로고침이 되지 않고 확인창만으로 해결되어야 함.\n기본 게시판 대응 플러그인에서 발생한 이슈.","url":"https://api.github.com/repos/izuzero/xe-module-ajaxboard/commits/ec819b9df4fe612bb35bf562f96810bf991f9975","distinct":true,"sha":"ec819b9df4fe612bb35bf562f96810bf991f9975"}]},"type":"PushEvent"},{"repo":{"id":2871998,"name":"visionmedia/debug","url":"https://api.github.com/repos/visionmedia/debug"},"actor":{"id":6894991,"login":"SametSisartenep","avatar_url":"https://avatars.githubusercontent.com/u/6894991?","url":"https://api.github.com/users/SametSisartenep","gravatar_id":""},"public":true,"id":"2489651057","created_at":"2015-01-01T15:00:03Z","org":{"id":9285252,"login":"visionmedia","avatar_url":"https://avatars.githubusercontent.com/u/9285252?","url":"https://api.github.com/orgs/visionmedia","gravatar_id":""},"payload":{"action":"started"},"type":"WatchEvent"},{"repo":{"id":28593843,"name":"winterbe/streamjs","url":"https://api.github.com/repos/winterbe/streamjs"},"actor":{"id":485033,"login":"winterbe","avatar_url":"https://avatars.githubusercontent.com/u/485033?","url":"https://api.github.com/users/winterbe","gravatar_id":""},"public":true,"id":"2489651062","created_at":"2015-01-01T15:00:03Z","payload":{"before":"0fef99f604154ccfe1d2fcd0aadeffb5c58e43ff","ref":"refs/heads/master","push_id":536863975,"size":1,"distinct_size":1,"head":"15b303203be31bd295bc831075da8f74b99b3981","commits":[{"author":{"email":"52a47bffd52d9cea1ee1362f2bd0c5f87fac9262@googlemail.com","name":"Benjamin Winterberg"},"message":"Add comparator support for min, max operations","url":"https://api.github.com/repos/winterbe/streamjs/commits/15b303203be31bd295bc831075da8f74b99b3981","distinct":true,"sha":"15b303203be31bd295bc831075da8f74b99b3981"}]},"type":"PushEvent"}]"#
        expectCount(json, "$..[?(@.payload.commits.length() == 1)]", 3)
    }
}
