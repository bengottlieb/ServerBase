import CustomerFeedbackKit
import Foundation
@testable import SupportChat

/// A server with one conversation holding one unread staff reply.
@MainActor final class ScriptedReplies: SupportReplyTransport {
	let conversationID = UUID()
	let replyID = UUID()
	var validation: Result<Bool, any Error> = .success(true)
	private(set) var validations = 0

	func validates(messageID: UUID, conversationID: UUID) async throws -> Bool {
		validations += 1
		return try validation.get()
	}
	func fetch(_ query: CustomerFeedbackQuery) async throws -> CustomerFeedbackPage {
		.init(conversation: .init(id: conversationID, generation: 1, unreadCount: 1),
		      messages: [.init(id: replyID, sequence: 1, role: "staff", text: "Thanks!", createdAt: 0)])
	}
	func send(_ submission: FeedbackSubmission) async throws {}
	func attachment(_ id: UUID) async throws -> Data { Data() }
	func markRead(conversationID: UUID, messageIDs: [UUID]) async throws {}
}
