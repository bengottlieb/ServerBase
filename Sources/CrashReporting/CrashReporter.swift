import Chronicle
import Foundation
import NewsHelicopter
#if canImport(MetricKit)
	import MetricKit
#endif

/// Crash and hang reporting: MetricKit's diagnostics and the crash-reporter extension's reports go onto one queue on
/// disk and are uploaded at launch, whenever the app calls `flush()` (on foreground) and as they arrive. NewsHelicopter
/// crumbs (`beginRun` at start, `setScreen`, `note`) say what the app was doing when it died.
@MainActor public enum CrashReporter {
	private static var configuration: Configuration?
	private static var queue: CrashReportQueue?
	private static var uploader: CrashReportUploader?
	private static var newsHelicopter: NewsHelicopterReportStore?
	#if canImport(MetricKit)
		private static var subscriber: Subscriber?
	#endif

	public static func start(_ configuration: Configuration) {
		guard queue == nil else { return }
		NewsHelicopterCrumbs.beginRun()
		self.configuration = configuration
		let pending = CrashReportQueue(directory: configuration.queueDirectory)
		queue = pending
		newsHelicopter = configuration.newsHelicopterDirectory.map(NewsHelicopterReportStore.init(directory:))
		uploader = CrashReportUploader(queue: pending, endpoint: configuration.endpoint, authorize: configuration.authorize, transport: configuration.transport)
		#if canImport(MetricKit)
			let receiver = Subscriber()
			subscriber = receiver
			MXMetricManager.shared.add(receiver)
		#endif
		Task { await flush() }
	}

	/// Moves the extension's reports onto the queue and uploads; failures wait for the next flush.
	public static func flush() async {
		await drainNewsHelicopter()
		do {
			try await uploader?.flush()
		} catch {
			Chronicle.error(error, description: "Crash report upload deferred", severity: .warning)
		}
	}

	/// The screen the app is on, for the next crash's crumbs.
	public static func setScreen(_ name: String) { NewsHelicopterCrumbs.setScreen(name) }

	/// A line in the next crash's crumbs.
	public static func note(_ line: String) { NewsHelicopterCrumbs.note(line) }

	/// The extension's reports join the queue before every flush: a crash last session was filed by a process that
	/// couldn't upload it.
	private static func drainNewsHelicopter() async {
		guard let newsHelicopter, let queue, let configuration, let device = await device() else { return }
		_ = await NewsHelicopterIngest.drain(newsHelicopter, into: queue, device: device, bundleID: configuration.bundleID)
	}

	static func receive(_ entries: [CrashCapture]) async {
		guard let queue, let configuration, let device = await device() else { return }
		let bundleID = configuration.bundleID
		for entry in entries {
			do {
				try await queue.enqueue(CrashReport.build { try entry.report(device: device, bundleID: bundleID) })
			} catch {
				Chronicle.error(error, description: "Couldn't keep a MetricKit diagnostic", severity: .warning)
			}
		}
		await flush()
	}

	private static func device() async -> CrashDeviceSnapshot? {
		do {
			return try await configuration?.device()
		} catch {
			Chronicle.error(error, description: "Couldn't describe the device for a crash report", severity: .warning)
			return nil
		}
	}

	#if DEBUG
		/// Uploads a made-up crash with real app frames, to check the pipeline and dSYM symbolication.
		public static func sendSample() async throws {
			guard let queue, let uploader, let configuration, let device = await device() else { throw CocoaError(.coderInvalidValue) }
			let bundleID = configuration.bundleID
			try await queue.enqueue(CrashReport.build { try CrashReport(kind: .crash, occurredAt: .now, device: device, bundleID: bundleID, diagnosticJSON: CrashReportSample.makeJSON()) })
			try await uploader.flush()
		}
	#endif
}
