import Foundation

extension CrashReporter {
	/// Everything app-specific about crash reporting.
	public struct Configuration: Sendable {
		/// The queue of reports waiting to upload; the app's own container, or the group's.
		public var queueDirectory: URL
		/// Where the crash-reporter extension leaves its reports (`CrashReportLocations.directory`); nil without one.
		public var newsHelicopterDirectory: URL?
		/// The app's bundle id, which every report carries.
		public var bundleID: String
		/// The full URL reports are POSTed to; nil holds them until it isn't.
		public var endpoint: @MainActor @Sendable () -> URL?
		/// The device each report carries, read whenever reports are queued; a throw holds them until the next flush.
		public var device: @MainActor @Sendable () async throws -> CrashDeviceSnapshot
		/// Adds the server's authorization to each upload (`CrashReportUploader.bearer`, a signature, both, or nothing).
		public var authorize: CrashReportUploader.Authorize
		public var transport: CrashReportUploader.Transport

		public init(queueDirectory: URL, newsHelicopterDirectory: URL?, bundleID: String = Bundle.main.bundleIdentifier ?? "", endpoint: @escaping @MainActor @Sendable () -> URL?, device: @escaping @MainActor @Sendable () async throws -> CrashDeviceSnapshot, authorize: @escaping CrashReportUploader.Authorize = { $0 }, transport: @escaping CrashReportUploader.Transport = CrashReportUploader.urlSession) {
			self.queueDirectory = queueDirectory
			self.newsHelicopterDirectory = newsHelicopterDirectory
			self.bundleID = bundleID
			self.endpoint = endpoint
			self.device = device
			self.authorize = authorize
			self.transport = transport
		}
	}
}
