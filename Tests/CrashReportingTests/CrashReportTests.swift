import Foundation
import Testing
@testable import CrashReporting

/// A report must keep diagnostic integers exact, carry the device the app describes and the build that crashed (not
/// the one that uploads it), and never be built on the main thread.
@Suite("Crash reports")
@MainActor
struct CrashReportTests {
	@Test func wireRoundTripPreservesDiagnosticIntegersAndDeviceIdentity() throws {
		let item = try CrashReport.example(), data = try item.encoded()
		let copy = try CrashReport.decode(data)
		#expect(copy.reportID == item.reportID)
		#expect(copy.occurredAt == item.occurredAt)
		let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
		#expect(json["kind"] as? String == "crash")
		let device = try #require(json["device"] as? [String: Any])
		#expect(device["bundleID"] as? String == "com.example.app")
		#expect(device["installID"] as? String == CrashDevice.sample.installID)
		#expect(String(decoding: data, as: UTF8.self).contains("18446744073709551615"))
		#expect(String(decoding: try copy.encoded(), as: UTF8.self).contains("18446744073709551615"))
	}

	@Test func captureUsesDiagnosticBuildAndPayloadTimeAfterAnAppUpdate() throws {
		let timestamp = Date(timeIntervalSince1970: 1_780_000_000)
		let capture = CrashCapture(kind: .hang, occurredAt: timestamp,
			json: Data(#"{"callStackTree":{"callStacks":[]},"marker":"original"}"#.utf8),
			appVersion: "old-version", appBuild: "123", osVersion: "18.1", model: "iPhone16,1")
		let item = try capture.report(device: .sample, bundleID: "com.example.app")
		let body = try #require(JSONSerialization.jsonObject(with: item.encoded()) as? [String: Any])
		let device = try #require(body["device"] as? [String: Any])
		#expect(item.kind == .hang)
		#expect(item.occurredAt == timestamp)
		#expect(device["appBuild"] as? String == "123")
		#expect(device["appVersion"] as? String == "old-version")
		#expect(device["osVersion"] as? String == "18.1")
		#expect(device["model"] as? String == "iPhone16,1")
	}

	@Test("a report is converted off the main thread, whoever asks for it")
	func reportsAreBuiltOffTheMainThread() async throws {
		let capture = CrashCapture(kind: .hang, occurredAt: .now, json: Data(#"{"callStackTree":{"callStacks":[]}}"#.utf8), appVersion: "1", appBuild: "1", osVersion: "27.0", model: "iPhone12,8")
		let item = try await CrashReport.build {
			#expect(!Thread.isMainThread)
			return try capture.report(device: .sample, bundleID: "com.example.app")
		}
		#expect(item.kind == .hang)
	}

	/// An app with its own, richer device description sends all of it; the server keeps what it knows.
	@Test func anAppsOwnDeviceDescriptionTravelsWhole() throws {
		struct Details: Encodable { let installID = "install-1", idiom = "phone", locale = "en_US", distribution = "development", model = "iPhone17,1" }
		let details = Details()
		let snapshot = try CrashDeviceSnapshot(details, model: details.model)
		let item = try CrashReport(kind: .crash, occurredAt: .now, device: snapshot, bundleID: "com.example.app", diagnosticJSON: Data(#"{"callStackTree":{"callStacks":[]}}"#.utf8))
		let device = try #require((JSONSerialization.jsonObject(with: item.encoded()) as? [String: Any])?["device"] as? [String: Any])
		#expect(device["idiom"] as? String == "phone" && device["locale"] as? String == "en_US" && device["distribution"] as? String == "development")
		#expect(snapshot.model == "iPhone17,1")
	}

	@Test func aDiagnosticWithoutAStackTreeIsRefused() {
		#expect(throws: (any Error).self) { try CrashReport(kind: .crash, occurredAt: .now, device: .sample, bundleID: "com.example.app", diagnosticJSON: Data(#"{"other":1}"#.utf8)) }
	}

	@Test("distribution detection is the app's to choose")
	func distributionIsInjected() async {
		let device = await CrashDevice.current(installID: "install-1", distribution: { "development" })
		#expect(device.distribution == "development")
		#expect(device.installID == "install-1")
		#expect(!device.model.isEmpty)
	}
}

extension CrashReport {
	static func example(id: UUID = UUID(), at: Date = Date(timeIntervalSince1970: 1_789_200_000)) throws -> CrashReport {
		try CrashReport(reportID: id, kind: .crash, occurredAt: at, device: .sample, bundleID: "com.example.app",
			diagnosticJSON: Data(#"{"callStackTree":{"callStacks":[]},"address":18446744073709551615,"unknown":{"nested":[true,null,"kept"]}}"#.utf8))
	}
}
