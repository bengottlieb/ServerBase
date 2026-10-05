import CustomerFeedbackKit
import Foundation
import Testing
@testable import SupportChat

/// Tapping a staff reply's notification opens that customer's conversation. A tap is a routing hint from outside the
/// app, so it opens nothing until the device's own account is ready, the server confirms the reply belongs to the
/// conversation named, and the conversation has loaded; anything addressed to another account, or to a reply that is
/// gone, is dropped without showing a thing. Switching accounts must never show one account's conversation to another.
@MainActor @Suite("Support reply routing")
struct SupportChatModelTests {
	let accountID = UUID().uuidString
	let server = ScriptedReplies()
	let hub = SupportChatPush()

	private func connected(as id: String?) -> SupportChatModel {
		let model = SupportChatModel(push: hub)
		model.connect(accountID: id, credential: "token") { server }
		return model
	}

	private func tap(for accountID: String) {
		hub.receive(accountID: accountID, conversationID: server.conversationID.uuidString, messageID: server.replyID.uuidString, tapped: true)
	}

	@Test("a tap for this account opens the conversation the server confirms")
	func tapOpensTheConfirmedConversation() async {
		let model = connected(as: accountID)
		tap(for: accountID)
		#expect(await model.handlePending())
		#expect(model.session?.conversation?.id == server.conversationID)
		#expect(hub.pending == nil, "one tap opens it once")
	}

	// A tap can launch the app before its account exists. It must wait for the account rather than be lost.
	@Test("a tap from a cold launch waits for the account, then opens")
	func coldLaunchWaitsForTheAccount() async {
		let model = connected(as: nil)
		tap(for: accountID)
		#expect(!(await model.handlePending()))
		#expect(hub.pending != nil, "kept until the account is ready")
		#expect(server.validations == 0, "nothing is asked of the server without an account")
		model.connect(accountID: accountID, credential: "token") { server }
		#expect(await model.handlePending())
	}

	@Test("a tap addressed to another account is dropped without asking the server")
	func anotherAccountsTapIsDropped() async {
		let model = connected(as: accountID)
		tap(for: UUID().uuidString)
		#expect(!(await model.handlePending()))
		#expect(hub.pending == nil)
		#expect(server.validations == 0, "another customer's conversation is never looked up")
	}

	@Test("switching accounts or credentials replaces the session; the same keeps it")
	func sessionsFollowTheAccount() throws {
		let model = connected(as: accountID)
		let first = try #require(model.session)
		model.connect(accountID: accountID, credential: "token") { server }
		#expect(model.session === first, "the same account keeps its session")
		model.connect(accountID: accountID, credential: "renewed") { server }
		#expect(model.session !== first, "a new token is a new session")
		model.connect(accountID: UUID().uuidString) { server }
		#expect(model.session != nil)
		model.connect(accountID: nil) { server }
		#expect(model.session == nil)
	}

	@Test("switching accounts drops the old account's tap")
	func switchingAccountsDropsTheTap() async {
		let model = connected(as: accountID)
		tap(for: accountID)
		model.connect(accountID: UUID().uuidString, credential: "other") { server }
		#expect(!(await model.handlePending()))
		#expect(hub.pending == nil)
	}

	@Test("a reply the server places elsewhere opens nothing and isn't retried")
	func staleReplyOpensNothing() async {
		let model = connected(as: accountID)
		server.validation = .success(false)
		tap(for: accountID)
		#expect(!(await model.handlePending()))
		#expect(hub.pending == nil)
	}

	// Offline is not a verdict on the reply: the tap waits for the next time the app is active.
	@Test("a tap the server could not be asked about is kept for later")
	func offlineTapIsKept() async {
		let model = connected(as: accountID)
		server.validation = .failure(URLError(.notConnectedToInternet))
		tap(for: accountID)
		#expect(!(await model.handlePending()))
		#expect(hub.pending != nil)
	}

	@Test("a conversation already on screen is not opened a second time")
	func alreadyShowingOpensNoSecondSheet() async {
		let model = connected(as: accountID)
		model.presentationCount = 1
		tap(for: accountID)
		#expect(!(await model.handlePending()))
		#expect(hub.pending == nil, "the tap is spent: the reader is already there")
	}

	// A reply arriving while the app is open refreshes the unread count, and never counts as read: nothing was shown.
	@Test("a reply arriving in the foreground refreshes unread without opening it")
	func foregroundArrivalRefreshesUnread() async {
		let model = connected(as: accountID)
		hub.receive(accountID: accountID, conversationID: server.conversationID.uuidString, messageID: server.replyID.uuidString, tapped: false)
		await model.session?.refresh()
		#expect(hub.pending == nil, "arrival alone opens nothing")
		#expect(model.unreadCount == 1)
	}
}
