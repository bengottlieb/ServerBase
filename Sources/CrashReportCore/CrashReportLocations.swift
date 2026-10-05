import Foundation

/// Where the crash-reporter extension leaves its reports for the app: a directory in an App Group. The extension can't
/// import the app's code (it carries as little as it can), so its Info.plist names the same place under two keys the app
/// chooses, and the app's test compares the two (`init?(info:keys:)` == the app's own value).
public struct CrashReportLocations: Sendable, Equatable {
	/// The Info.plist keys that name the group and the directory.
	public struct InfoKeys: Sendable, Equatable {
		public var appGroup: String
		public var directory: String

		public init(appGroup: String, directory: String) {
			self.appGroup = appGroup
			self.directory = directory
		}
	}

	public var appGroup: String
	/// Relative to the group container's root.
	public var groupRelativePath: String

	public init(appGroup: String, groupRelativePath: String) {
		self.appGroup = appGroup
		self.groupRelativePath = groupRelativePath
	}

	/// The place an Info.plist names under `keys`; nil when either is missing.
	public init?(info: [String: Any], keys: InfoKeys) {
		guard let group = info[keys.appGroup] as? String, let path = info[keys.directory] as? String else { return nil }
		self.init(appGroup: group, groupRelativePath: path)
	}

	/// The reports' directory, or nil when the App Group isn't available (unsigned builds).
	public var directory: URL? {
		FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup).map(directory(in:))
	}

	/// The reports' directory inside a group container at `container`.
	public func directory(in container: URL) -> URL {
		container.appending(path: groupRelativePath, directoryHint: .isDirectory)
	}
}
