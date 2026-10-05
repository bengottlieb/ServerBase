import Foundation
import Testing
@testable import SupportChat

/// A reply's push must be recognised in whichever shape its server sends, and only a support reply with all its ids
/// counts: without them the reply can't be checked.
@MainActor @Suite struct SupportReplyPushTests {
	let account = "6f9619ff-8b86-d011-b42d-00c04fc964ff"
	let conversation = "1e2f3a4b-8b86-d011-b42d-00c04fc964ff"
	let message = "2a3b4c5d-8b86-d011-b42d-00c04fc964ff"
	let nested = SupportReplyPush.Format(container: "app", kindKey: "t", kind: "support")
	let topLevel = SupportReplyPush.Format(container: nil, kindKey: "kind", kind: "feedback-reply")

	@Test func nestedPayloadParsesOnlySupportReplies() {
		let reply = SupportReplyPush(userInfo: ["aps": ["alert": "Hi"], "app": ["t": "support", "accountID": account, "conversationID": conversation, "messageID": message]], format: nested)
		#expect(reply?.conversationID == conversation)
		#expect(SupportReplyPush(userInfo: ["app": ["t": "alert", "inbox": 3]], format: nested) == nil)
		#expect(SupportReplyPush(userInfo: ["app": ["t": "support", "accountID": account]], format: nested) == nil, "a reply without its ids can't be checked")
	}

	@Test func topLevelPayloadParses() {
		let reply = SupportReplyPush(userInfo: ["kind": "feedback-reply", "accountID": account, "conversationID": conversation, "messageID": message], format: topLevel)
		#expect(reply?.messageID == message)
		#expect(SupportReplyPush(userInfo: ["kind": "profile", "accountID": account, "conversationID": conversation, "messageID": message], format: topLevel) == nil)
		#expect(SupportReplyPush(userInfo: ["app": ["kind": "feedback-reply"]], format: topLevel) == nil)
	}

	@Test func deliveringATapAsksToOpen() throws {
		let hub = SupportChatPush()
		let reply = try #require(SupportReplyPush(userInfo: ["kind": "feedback-reply", "accountID": account, "conversationID": conversation, "messageID": message], format: topLevel))
		reply.deliver(tapped: true, to: hub)
		#expect(hub.pending == SupportChatPush.Destination(accountID: account, conversationID: UUID(uuidString: conversation)!, messageID: UUID(uuidString: message)!))
	}

	@Test func arrivalRefreshesAndOnlyATapAsksToOpen() {
		let hub = SupportChatPush()
		hub.receive(accountID: account, conversationID: conversation, messageID: message, tapped: false)
		#expect(hub.revision == 1 && hub.pending == nil)
		hub.receive(accountID: account, conversationID: conversation, messageID: message, tapped: true)
		#expect(hub.revision == 2 && hub.pending?.messageID == UUID(uuidString: message))
		#expect(hub.pending?.accountID == account)
		hub.refresh()
		#expect(hub.revision == 3, "a silent push refreshes without naming a reply")
	}

	@Test func malformedIdsAreIgnored() {
		let hub = SupportChatPush()
		hub.receive(accountID: "not-an-id", conversationID: conversation, messageID: message, tapped: true)
		#expect(hub.revision == 0 && hub.pending == nil)
	}
}
