import CustomerFeedbackKit
import Foundation

/// A FeedbackKit transport that can also say whether the staff reply a notification names belongs to the conversation
/// it claims. The app writes it over its own server client; `SupportChatModel` asks it before opening anything.
@MainActor public protocol SupportReplyTransport: CustomerFeedbackTransport {
	/// False when the server doesn't have the reply (a 404) or places it in another conversation: the tap is dropped.
	/// Throw only when the server couldn't be asked (offline, 5xx): the tap is kept for the next try.
	func validates(messageID: UUID, conversationID: UUID) async throws -> Bool
}
