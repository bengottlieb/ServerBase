import Foundation
import StoreKit

/// The device and build a crash came from: hardware and build only, nothing about the person (no device name).
/// `installID` is the app's own id for this install, so the server can match a report to a device.
public struct CrashDevice: Sendable, Encodable, Equatable {
	public var installID: String
	public var platform: String
	public var model: String
	public var osVersion: String
	public var appVersion: String
	public var appBuild: String
	/// How the build was distributed, in the app's own words (`CrashDevice.appTransactionDistribution` says `debug`,
	/// `testflight` or `appstore`).
	public var distribution: String
	public var isSimulator: Bool

	public init(installID: String, platform: String, model: String, osVersion: String, appVersion: String, appBuild: String, distribution: String, isSimulator: Bool) {
		self.installID = installID
		self.platform = platform
		self.model = model
		self.osVersion = osVersion
		self.appVersion = appVersion
		self.appBuild = appBuild
		self.distribution = distribution
		self.isSimulator = isSimulator
	}

	/// This device, with the distribution `distribution` reports (by default, from the app's StoreKit transaction).
	public static func current(installID: String, distribution: @Sendable () async -> String = appTransactionDistribution) async -> CrashDevice {
		let info = Bundle.main.infoDictionary ?? [:]
		#if targetEnvironment(simulator)
			let simulator = true
		#else
			let simulator = false
		#endif
		#if os(macOS)
			let platform = "macOS"
		#else
			let platform = "iOS"
		#endif
		return CrashDevice(installID: installID, platform: platform, model: machine(), osVersion: ProcessInfo.processInfo.operatingSystemVersionString, appVersion: info["CFBundleShortVersionString"] as? String ?? "", appBuild: info["CFBundleVersion"] as? String ?? "", distribution: await distribution(), isSimulator: simulator)
	}

	/// `appstore`, `testflight` (StoreKit's sandbox) or `debug` (no verified transaction: Xcode, the simulator).
	@Sendable public static func appTransactionDistribution() async -> String {
		guard case .verified(let transaction)? = try? await AppTransaction.shared else { return "debug" }
		switch transaction.environment {
		case .production: return "appstore"
		case .sandbox: return "testflight"
		default: return "debug"
		}
	}

	/// "iPhone17,1", "Mac16,10".
	static func machine() -> String {
		var system = utsname()
		uname(&system)
		return withUnsafeBytes(of: system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
	}
}
