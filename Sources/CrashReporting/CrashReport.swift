import Foundation

/// One crash or hang as the server's crash-report endpoint takes it: MetricKit's diagnostic JSON (or the crash
/// extension's, in the same shape) and the device it came from. Integers in the diagnostic stay exact.
public struct CrashReport: Codable, Sendable {
	public enum Kind: String, Codable, Sendable { case crash, hang }
	public let reportID: UUID
	public let kind: Kind
	public let occurredAt: Date
	private let device: [String: CrashJSON]
	private let diagnostic: [String: CrashJSON]

	/// Not for the main thread: see `build`.
	public init(reportID: UUID = UUID(), kind: Kind, occurredAt: Date, device: CrashDeviceSnapshot, bundleID: String, diagnosticJSON: Data, appVersion: String? = nil, appBuild: String? = nil, osVersion: String? = nil, model: String? = nil) throws {
		self.reportID = reportID
		self.kind = kind
		self.occurredAt = occurredAt
		var snapshot = device.fields
		snapshot["bundleID"] = .string(bundleID)
		if let appVersion { snapshot["appVersion"] = .string(appVersion) }
		if let appBuild { snapshot["appBuild"] = .string(appBuild) }
		if let osVersion { snapshot["osVersion"] = .string(osVersion) }
		if let model { snapshot["model"] = .string(model) }
		self.device = snapshot
		self.diagnostic = try JSONDecoder().decode([String: CrashJSON].self, from: Self.boundingFrames(in: diagnosticJSON))
		guard case .object? = diagnostic["callStackTree"] else { throw CocoaError(.coderInvalidValue) }
	}

	/// Builds a report away from the caller's actor. Pruning and decoding a diagnostic walks a stack tree on every
	/// thread; on the main thread it hung an iPhone SE for a second or two per report, and each hang MetricKit then
	/// delivered made another.
	public static func build(_ work: @escaping @Sendable () throws -> CrashReport) async throws -> CrashReport {
		try await Task.detached(priority: .utility, operation: work).value
	}

	public func encoded() throws -> Data {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		return try encoder.encode(self)
	}

	public static func decode(_ data: Data) throws -> Self {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return try decoder.decode(Self.self, from: data)
	}
}
