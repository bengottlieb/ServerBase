import CustomerFeedbackKit
import Foundation

/// The signed-in account's support conversation: one FeedbackKit session per account (and credential), rebuilt when it
/// changes, so one account's conversation never shows to another. Opens the conversation for a tapped reply only once
/// the reply is confirmed to belong to it.
@MainActor @Observable public final class SupportChatModel {
	public private(set) var session: CustomerFeedbackSession?
	/// How many support screens are showing, so a tapped reply doesn't open a second one.
	public var presentationCount = 0
	@ObservationIgnored private var identity: String?
	@ObservationIgnored private var accountID: String?
	@ObservationIgnored private var transport: (any SupportReplyTransport)?
	@ObservationIgnored private let push: SupportChatPush

	public init(push: SupportChatPush = .shared) {
		self.push = push
	}

	public var unreadCount: Int { session?.unreadCount ?? 0 }

	/// Starts (or restarts) the session for `accountID`; nil ends it. A new `credential` (a token) for the same account
	/// also restarts it. `transport` is built only when a session starts.
	public func connect(accountID: String?, credential: String? = nil, transport makeTransport: () -> any SupportReplyTransport) {
		let identity = accountID.map { [$0, credential].compactMap { $0 }.joined(separator: ":") }
		guard identity != self.identity else { return }
		session?.invalidate()
		session = nil
		transport = nil
		self.identity = identity
		self.accountID = accountID
		guard accountID != nil else { return }
		let transport = makeTransport()
		self.transport = transport
		session = CustomerFeedbackSession(transport: transport)
	}

	/// True when a tapped reply should open the conversation now: it's this account's, the server confirms it, and no
	/// support screen is already showing. A reply that doesn't check out is dropped; one the server couldn't be asked
	/// about, or that arrived before the account, is kept.
	public func handlePending() async -> Bool {
		guard let pending = push.pending, let accountID, let session, let transport else { return false }
		guard pending.accountID.caseInsensitiveCompare(accountID) == .orderedSame else {
			push.pending = nil
			return false
		}
		do {
			guard try await transport.validates(messageID: pending.messageID, conversationID: pending.conversationID) else {
				if push.pending == pending { push.pending = nil }
				return false
			}
		} catch {
			return false
		}
		await session.refresh()
		guard self.session === session, session.loaded, push.pending == pending else { return false }
		push.pending = nil
		return session.conversation?.id == pending.conversationID && presentationCount == 0
	}
}
