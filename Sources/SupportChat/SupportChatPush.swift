import Foundation

/// Support replies' notifications as they arrive: any arrival refreshes the conversation (`revision`), and a tap also
/// asks for it to open (`pending`) once `SupportChatModel.handlePending` confirms it.
@MainActor @Observable public final class SupportChatPush {
	/// The reply a tapped notification names.
	public struct Destination: Equatable, Sendable {
		public let accountID: String
		public let conversationID: UUID
		public let messageID: UUID

		public init(accountID: String, conversationID: UUID, messageID: UUID) {
			self.accountID = accountID
			self.conversationID = conversationID
			self.messageID = messageID
		}
	}

	public static let shared = SupportChatPush()
	public var pending: Destination?
	/// Bumps on every arrival; observe it to refresh the conversation.
	public private(set) var revision = 0

	public init() {}

	/// A reply arrived; `tapped` when the person opened its notification. Ids that aren't UUIDs are ignored.
	public func receive(accountID: String, conversationID: String, messageID: String, tapped: Bool) {
		guard UUID(uuidString: accountID) != nil, let conversation = UUID(uuidString: conversationID), let message = UUID(uuidString: messageID) else { return }
		if tapped { pending = Destination(accountID: accountID, conversationID: conversation, messageID: message) }
		revision += 1
	}

	/// Something changed in the conversation without naming a reply (a silent push): refresh only.
	public func refresh() { revision += 1 }
}
