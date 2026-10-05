import Foundation

/// Sends queued reports to the server one at a time, oldest first. A report leaves the queue once the server has it
/// (2xx) or refuses it for good (400, 413, 415, 422); anything else stops the drain until the next flush.
@MainActor public final class CrashReportUploader {
	/// Sends a request and answers its body and status (0 when there was no HTTP response).
	public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)
	/// Adds whatever the server needs to accept a report (a bearer token, a signature) just before it's sent.
	public typealias Authorize = @Sendable (URLRequest) async -> URLRequest
	private let queue: CrashReportQueue
	private let endpoint: () -> URL?
	private let authorize: Authorize
	private let transport: Transport
	private var flushing = false
	private var flushAgain = false

	/// `endpoint` is the full URL reports are POSTed to; nil holds them until it isn't.
	public init(queue: CrashReportQueue, endpoint: @escaping () -> URL?, authorize: @escaping Authorize = { $0 }, transport: @escaping Transport = CrashReportUploader.urlSession) {
		self.queue = queue
		self.endpoint = endpoint
		self.authorize = authorize
		self.transport = transport
	}

	nonisolated public static let urlSession: Transport = { request in
		let (data, response) = try await URLSession.shared.data(for: request)
		return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
	}

	/// An `Authorize` that sends `Bearer <token>` when `token` has one, and nothing otherwise.
	nonisolated public static func bearer(_ token: @escaping @Sendable () async -> String?) -> Authorize {
		{ request in
			guard let bearer = await token() else { return request }
			var request = request
			request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
			return request
		}
	}

	/// One drain at a time; a flush asked for meanwhile runs once more after it. Authorization is applied for each
	/// attempt and never stored with a report.
	public func flush() async throws {
		guard !flushing else { flushAgain = true; return }
		flushing = true
		defer { flushing = false }
		repeat {
			flushAgain = false
			try await drain()
		} while flushAgain
	}

	private func drain() async throws {
		guard let url = endpoint() else { return }
		for report in try await queue.pending() {
			try Task.checkCancellation()
			var request = URLRequest(url: url)
			request.httpMethod = "POST"
			request.httpBody = try report.encoded()
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			let (_, status) = try await transport(await authorize(request))
			// Throttling, auth and server errors can recover later.
			guard (200..<300).contains(status) || [400, 413, 415, 422].contains(status) else {
				flushAgain = false
				break
			}
			try await queue.remove(report.reportID)
		}
	}
}
