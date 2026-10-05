import Chronicle
import Foundation
import NewsHelicopter

/// What the crash-reporter extension left in the App Group, turned into the reports the server takes, in
/// MetricKit's shape (a callStackTree rooted at the crashing frame, each caller a subFrame) so the server's signature
/// and dSYM symbolication read it unchanged. What MetricKit never has rides alongside under `newsHelicopter`: the
/// device's own symbolication, the fatal error's text, the crumbs and the run id.
public enum NewsHelicopterIngest {
	/// Which of the app's launches a report came from, when the report's
	/// crumbs say. The server tells an extension's report from MetricKit's
	/// by `source`.
	public static let source = "news-helicopter"

	/// Move every report the extension wrote onto the upload queue. Reading and converting them happens off the
	/// caller's actor, as `CrashReport.build` explains.
	static func drain(_ store: NewsHelicopterReportStore, into queue: CrashReportQueue, device: CrashDeviceSnapshot, bundleID: String) async -> Int {
		await Task.detached(priority: .utility) {
			var moved = 0
			for report in store.reports() {
				do {
					try await queue.enqueue(try Self.report(from: report, device: device, bundleID: bundleID))
					moved += 1
				} catch {
					Chronicle.error(error, description: "Couldn't queue a crash extension report", severity: .warning)
				}
				// Either way it leaves the store: a report this build can't convert would only fail the same way next launch.
				store.remove(report)
			}
			return moved
		}.value
	}

	static func report(from report: NewsHelicopterReport, device: CrashDeviceSnapshot, bundleID: String) throws -> CrashReport {
		try CrashReport(reportID: report.id, kind: .crash, occurredAt: report.capturedAt, device: device,
		                   bundleID: report.app.bundleID ?? bundleID, diagnosticJSON: diagnosticJSON(for: report),
		                   appVersion: report.app.version, appBuild: report.app.build, osVersion: report.app.osVersion, model: device.model)
	}

	/// The MetricKit-shaped diagnostic, plus the `newsHelicopter` object.
	static func diagnosticJSON(for report: NewsHelicopterReport) throws -> Data {
		try JSONSerialization.data(withJSONObject: diagnostic(for: report))
	}

	static func diagnostic(for report: NewsHelicopterReport) -> [String: Any] {
		var metadata: [String: Any] = [
			"exceptionType": Int(report.reason.exception),
			"platformArchitecture": "arm64",
			"osVersion": report.app.osVersion,
			"terminationReason": "\(report.reason.exceptionName)\(report.reason.signalName.map { " (\($0))" } ?? "")",
		]
		if let code = report.reason.codes.first { metadata["exceptionCode"] = code }
		if let signal = report.reason.signalName.flatMap(signalNumber) { metadata["signal"] = signal }
		if let headline = report.headline { metadata["exceptionReason"] = headline }
		if let bundle = report.app.bundleID { metadata["bundleIdentifier"] = bundle }
		if let version = report.app.version { metadata["appVersion"] = version }
		if let build = report.app.build { metadata["appBuildVersion"] = build }

		let stacks: [[String: Any]] = report.threads.map { thread in
			["threadAttributed": thread.isCrashed, "callStackRootFrames": rootFrames(of: thread, images: report.images)]
		}
		return [
			"version": "1.0.0",
			"source": Self.source,
			"diagnosticMetaData": metadata,
			"callStackTree": ["callStackPerThread": true, "callStacks": stacks],
			"newsHelicopter": newsHelicopter(for: report),
		]
	}

	/// MetricKit nests each caller inside the frame it called, rooted at the
	/// crashing frame. An empty stack is an empty array, which the server
	/// refuses — better refused than a report that names nothing.
	static func rootFrames(of thread: NewsHelicopterReport.Thread, images: [NewsHelicopterReport.Image]) -> [[String: Any]] {
		var nested: [String: Any]?
		for frame in thread.frames.reversed() {
			var fields: [String: Any] = ["address": String(frame.address)]
			if let index = frame.imageIndex, images.indices.contains(index) {
				let image = images[index]
				fields["binaryName"] = image.name
				if let uuid = image.uuid { fields["binaryUUID"] = uuid.uuidString.lowercased() }
				if let offset = frame.offsetInImage { fields["offsetIntoBinaryTextSegment"] = String(offset) }
			}
			if let nested { fields["subFrames"] = [nested] }
			nested = fields
		}
		return nested.map { [$0] } ?? []
	}
}
