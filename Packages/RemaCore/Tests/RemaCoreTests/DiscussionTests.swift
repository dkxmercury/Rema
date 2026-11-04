import Foundation
import Testing
@testable import RemaCore

struct DiscussionTests {
    @Test func messagesKeepTheOrderTheyWereWritten() {
        let first = SharedComment(id: "A", author: "anya", text: "Билеты купила", at: 1000, seq: 5)
        let second = SharedComment(id: "B", author: "ilya", text: "Опоздаю", at: 2000, seq: 6)
        let merged = Discussion.merge([second], into: [first])
        #expect(merged.map(\.id) == ["A", "B"])
        #expect(Discussion.merge([first, second], into: merged) == merged)
    }

    @Test func aMessageTakenBackStaysInItsPlaceWithoutWords() {
        let first = SharedComment(id: "A", author: "anya", text: "Билеты купила", at: 1000, seq: 5)
        let second = SharedComment(id: "B", author: "ilya", text: "Опоздаю", at: 2000, seq: 6)
        let gone = SharedComment(id: "A", author: "anya", text: nil, deleted: true, at: 1000, seq: 9)
        let merged = Discussion.merge([gone], into: [first, second])
        #expect(merged.map(\.id) == ["A", "B"])
        #expect(merged.first?.deleted == true && merged.first?.text == nil)
        #expect(Discussion.merge([first], into: merged).first?.deleted == true)
    }

    @Test func emptyOrTooLongIsNotSent() {
        #expect(Discussion.cleaned("  Привет  ") == "Привет")
        #expect(Discussion.cleaned("   ") == nil)
        #expect(Discussion.cleaned(String(repeating: "я", count: SharedComment.maximumLength + 1)) == nil)
        #expect(Discussion.cleaned(String(repeating: "\u{0438}\u{0306}", count: SharedComment.maximumLength)) != nil)
    }

    @Test func aMessageFromTheServerIsReadLeniently() throws {
        let comment = try JSONDecoder().decode(SharedComment.self, from: Data(#"{"id": "A", "author": "anya", "deleted": true, "at": 1000, "seq": 7}"#.utf8))
        #expect(comment.deleted && comment.text == nil && comment.seq == 7)
    }

    @Test func aPushAboutAMessageKnowsItsReminder() throws {
        let push = try #require(SharedPush(userInfo: ["rema": ["event": "comment", "to": "ilya", "actor": "anya", "shared": "0F8FAD5B-D9CB-469F-A165-70867728950E"]]))
        #expect(push.event == .comment)
        #expect(push.shared == "0F8FAD5B-D9CB-469F-A165-70867728950E")
        #expect(push.item == nil)
        #expect(SharedPush(userInfo: ["rema": ["event": "thanks", "to": "ilya", "actor": "anya"]])?.event == .thanks)
    }
}
