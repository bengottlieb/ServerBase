import Foundation

/// A staff reply's notification payload: a kind marker and the account, conversation and message ids, either at the top
/// level of `userInfo` or inside one dictionary under `Format.container`.
public struct SupportReplyPush: Sendable, Equatable {
	/// Where a server puts the reply's fields.
	public struct Format: Sendable, Equatable {
		/// The dictionary holding the fields; nil for the top level.
		public var container: String?
		/// The key naming the push's kind, and the value that means "support reply".
		public var kindKey: String
		public var kind: String

		public init(container: String?, kindKey: String, kind: String) {
			self.container = container
			self.kindKey = kindKey
			self.kind = kind
		}
	}

	public var accountID: String
	public var conversationID: String
	public var messageID: String

	/// Nil for anything that isn't a support reply in `format`, or one missing an id.
	public init?(userInfo: [AnyHashable: Any], format: Format) {
		let fields: [AnyHashable: Any]
		if let container = format.container {
			guard let nested = userInfo[container] as? [String: Any] else { return nil }
			fields = nested
		} else {
			fields = userInfo
		}
		guard fields[format.kindKey] as? String == format.kind, let account = fields["accountID"] as? String, let conversation = fields["conversationID"] as? String, let message = fields["messageID"] as? String else { return nil }
		accountID = account
		conversationID = conversation
		messageID = message
	}

	/// Refreshes the conversation; a tap also asks for it to open.
	@MainActor public func deliver(tapped: Bool, to push: SupportChatPush = .shared) {
		push.receive(accountID: accountID, conversationID: conversationID, messageID: messageID, tapped: tapped)
	}
}
