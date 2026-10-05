import Foundation

/// MetricKit's diagnostic, copied on its callback thread before it crosses actors.
struct CrashCapture: Sendable {
	let kind: CrashReport.Kind
	let occurredAt: Date
	let json: Data
	let appVersion: String
	let appBuild: String
	let osVersion: String
	let model: String

	func report(device: CrashDeviceSnapshot, bundleID: String) throws -> CrashReport {
		try CrashReport(kind: kind, occurredAt: occurredAt, device: device, bundleID: bundleID, diagnosticJSON: json, appVersion: appVersion, appBuild: appBuild, osVersion: osVersion, model: model)
	}
}
