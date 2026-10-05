import Foundation
import Testing
@testable import CrashReporting

/// Reports must reach the server exactly once, authorized as the app says at the moment they're sent, and never be thrown
/// away for a failure that can recover.
@Suite("Crash report upload")
@MainActor
struct CrashReportUploaderTests {
	let endpoint = URL(string: "https://example.test/api/v1/crash-reports")!

	@Test(arguments: [200, 201, 204, 400, 413, 415, 422])
	func acceptedOrPermanentlyRejectedReportsAreRemoved(status: Int) async throws {
		let path = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: path) }
		let queue = CrashReportQueue(directory: path)
		try await queue.enqueue(CrashReport.example())
		let uploader = CrashReportUploader(queue: queue, endpoint: { endpoint }, transport: { _ in (Data(), status) })
		try await uploader.flush()
		#expect(try await queue.pending().isEmpty)
	}

	@Test(arguments: [0, 302, 401, 403, 404, 408, 429, 500, 503])
	func recoverableFailuresStayQueued(status: Int) async throws {
		let path = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: path) }
		let queue = CrashReportQueue(directory: path)
		try await queue.enqueue(CrashReport.example())
		let uploader = CrashReportUploader(queue: queue, endpoint: { endpoint }, transport: { _ in (Data(), status) })
		try await uploader.flush()
		#expect(try await queue.pending().count == 1)
	}

	@Test("without an endpoint nothing is sent and nothing is lost")
	func noEndpointHoldsReports() async throws {
		let path = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: path) }
		let queue = CrashReportQueue(directory: path)
		try await queue.enqueue(CrashReport.example())
		let uploader = CrashReportUploader(queue: queue, endpoint: { nil }, transport: { _ in Issue.record("sent without an endpoint"); return (Data(), 200) })
		try await uploader.flush()
		#expect(try await queue.pending().count == 1)
	}

	/// A bearer token (when there is one) and a request signature, the two ways the apps authorize an upload.
	@Test func networkFailureAndLaterAuthorizedRetry() async throws {
		let path = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: path) }
		let queue = CrashReportQueue(directory: path), item = try CrashReport.example()
		try await queue.enqueue(item)
		let failure = CrashReportUploader(queue: queue, endpoint: { endpoint }, authorize: CrashReportUploader.bearer { nil }, transport: { request in
			#expect(request.value(forHTTPHeaderField: "Authorization") == nil, "no token, no header")
			throw URLError(.notConnectedToInternet)
		})
		await #expect(throws: URLError.self) { try await failure.flush() }
		#expect(try await queue.pending().count == 1)
		let bearer = CrashReportUploader.bearer { "current-token" }
		let retry = CrashReportUploader(queue: queue, endpoint: { endpoint }, authorize: { request in
			var signed = await bearer(request)
			signed.setValue("signature", forHTTPHeaderField: "X-Client-Signature")
			return signed
		}, transport: { request in
			#expect(request.url?.path == "/api/v1/crash-reports")
			#expect(request.httpMethod == "POST")
			#expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer current-token")
			#expect(request.value(forHTTPHeaderField: "X-Client-Signature") == "signature")
			#expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
			let body = try #require(request.httpBody)
			#expect(try CrashReport.decode(body).reportID == item.reportID)
			return (Data(), 200)
		})
		try await retry.flush()
		#expect(try await queue.pending().isEmpty)
	}

	@Test func overlappingFlushDrainsNewReportsWithoutCompetingUploads() async throws {
		let path = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: path) }
		let queue = CrashReportQueue(directory: path), gate = CrashTransportGate()
		try await queue.enqueue(CrashReport.example())
		let uploader = CrashReportUploader(queue: queue, endpoint: { endpoint }, transport: { _ in
			await gate.request()
			return (Data(), 200)
		})
		let first = Task { try await uploader.flush() }
		await gate.waitUntilStarted()
		try await queue.enqueue(CrashReport.example())
		try await uploader.flush()
		#expect(await gate.count == 1)
		await gate.release()
		try await first.value
		#expect(await gate.count == 2)
		#expect(try await queue.pending().isEmpty)
	}
}

private actor CrashTransportGate {
	var count = 0
	private var started: CheckedContinuation<Void, Never>?
	private var blocked: CheckedContinuation<Void, Never>?
	func request() async {
		count += 1
		guard count == 1 else { return }
		await withCheckedContinuation { continuation in
			blocked = continuation
			started?.resume(); started = nil
		}
	}
	func waitUntilStarted() async {
		if count > 0 { return }
		await withCheckedContinuation { started = $0 }
	}
	func release() { blocked?.resume(); blocked = nil }
}
