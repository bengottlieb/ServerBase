import CrashReportCore
import Foundation
import NewsHelicopter

extension CrashReportLocations {
	/// The extension's report store, from the place its Info.plist names under `keys`; nil when a key is missing or the
	/// App Group isn't available.
	///
	///     guard let store = CrashReportLocations.store(keys: keys) else { return }
	///     NewsHelicopterReporter(store: store, logSubsystem: Bundle.main.bundleIdentifier ?? "CrashReporter").process(process)
	public static func store(keys: InfoKeys, info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> NewsHelicopterReportStore? {
		guard let locations = CrashReportLocations(info: info, keys: keys) else { return nil }
		return NewsHelicopterReportStore(appGroup: locations.appGroup, path: locations.groupRelativePath)
	}
}
