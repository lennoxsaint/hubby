import XCTest
@testable import Hubby

final class GrokRosterTests: XCTestCase {
    func testBase32Decode() {
        XCTAssertEqual(
            GrokRoster.base32Decode("ONQW4ZA=").flatMap { String(data: $0, encoding: .utf8) },
            "sand")
        XCTAssertEqual(
            GrokRoster.base32Decode("onqw4za").flatMap { String(data: $0, encoding: .utf8) },
            "sand") // lowercase, no padding — the on-disk filename form
        XCTAssertNil(GrokRoster.base32Decode("not!base32"))
    }

    func testKeyForBlobFilename() {
        // "sand.client.slice.ui-layout" as Grok writes it.
        let filename = "onqw4zbomnwgszlooqxhg3djmnss45ljfvwgc6lpov2a.blob"
        XCTAssertEqual(GrokRoster.key(forBlobFilename: filename), "sand.client.slice.ui-layout")
        XCTAssertNil(GrokRoster.key(forBlobFilename: "whatever.json"))
    }

    private let roster = """
        {"schemaVersion":3,"value":{"rows":[
          {"id":"idle-1","name":"Wally","title":"Weight","updatedAt":1787000000000,
           "lastActivityAt":1787000000000,"awaitingUserResponse":null,"isHiddenFromSidebar":false},
          {"id":"needs-you","name":"Jamie","title":"Jobs","updatedAt":1786900000000,
           "lastActivityAt":1786900000000,
           "awaitingUserResponse":{"tabId":"box","reason":"Tick the checkbox","since":1786900000000}},
          {"id":"hidden","name":"Ghost","title":"Hidden","lastActivityAt":1787100000000,
           "isHiddenFromSidebar":true},
          {"id":"untitled","name":"Nameless","title":"","lastActivityAt":1786800000000},
          {"id":"nameless","name":"","title":"Solo Project","lastActivityAt":1786700000000}
        ]}}
        """

    func testRosterParse() {
        let threads = GrokRoster.parse(Data(roster.utf8))
        // Hidden agents are dropped; awaiting-user sorts first despite
        // being less recent.
        XCTAssertEqual(threads.map(\.id), ["needs-you", "idle-1", "untitled", "nameless"])
        XCTAssertTrue(threads[0].isWaitingOnYou)
        XCTAssertFalse(threads[1].isWaitingOnYou)
        // The bot's name is the thread title; the project is the subtitle.
        XCTAssertEqual(threads[0].title, "Jamie")
        XCTAssertEqual(threads[0].subtitle, "Jobs")
        // The blocked reason doubles as the hover recap.
        XCTAssertEqual(threads[0].recap, "Tick the checkbox")
        XCTAssertNil(threads[1].recap)
        XCTAssertEqual(threads[2].title, "Nameless")
        XCTAssertNil(threads[2].subtitle) // empty project → no subtitle
        XCTAssertEqual(threads[3].title, "Solo Project") // no name → project title
        XCTAssertNil(threads[3].subtitle) // …and it isn't duplicated below
    }

    func testRosterParseGarbage() {
        XCTAssertEqual(GrokRoster.parse(Data("not json".utf8)), [])
        XCTAssertEqual(GrokRoster.parse(Data("{}".utf8)), [])
    }
}
