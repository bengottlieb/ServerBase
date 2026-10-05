import Foundation
import Testing
@testable import CrashReporting

/// Queued reports must survive relaunches, stay bounded, skip what they can't read and never be replaced by a retry.
@Suite("Crash report queue")
struct CrashReportQueueTests {
	@Test func queueSurvivesRecreationCapsOldestAndSkipsCorruptFiles() async throws {
		let path = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: path) }
		let queue = CrashReportQueue(directory: path), oldest = try CrashReport.example()
		try await queue.enqueue(oldest)
		try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: path.appendingPathComponent(oldest.reportID.uuidString + ".json").path)
		for _ in 0..<50 { try await queue.enqueue(CrashReport.example()) }
		let restored = CrashReportQueue(directory: path)
		let pending = try await restored.pending()
		#expect(pending.count == 50)
		#expect(!pending.contains { $0.reportID == oldest.reportID })
		try Data("broken".utf8).write(to: path.appendingPathComponent("corrupt.json"))
		#expect(try await restored.pending().count == 50)
		try await restored.remove(pending[0].reportID)
		#expect(try await queue.pending().count == 49)
	}

	@Test func retryIdentityDoesNotReplaceExistingPayload() async throws {
		let path = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: path) }
		let queue = CrashReportQueue(directory: path), item = try CrashReport.example()
		try await queue.enqueue(item)
		try await queue.enqueue(CrashReport.example(id: item.reportID, at: .distantPast))
		#expect(try await queue.pending().first?.occurredAt == item.occurredAt)
	}
}

func temporaryDirectory() throws -> URL {
	let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
	return path
}
