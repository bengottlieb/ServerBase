import Foundation
import Testing
@testable import CrashReporting

/// The app and its crash-reporter extension must name the same directory, or the extension's reports are never found.
/// These use made-up values; each app's own test compares its real Info.plist with its own locations.
@Suite("Crash report locations")
struct CrashReportLocationsTests {
	let keys = CrashReportLocations.InfoKeys(appGroup: "ExampleCrashAppGroup", directory: "ExampleCrashDirectory")
	let expected = CrashReportLocations(appGroup: "group.com.example.app", groupRelativePath: "Library/Application Support/Example/NewsHelicopter")

	@Test("an extension's Info.plist names the place the app reads")
	func plistMatchesTheAppsLocations() throws {
		let plist = """
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0"><dict>
		<key>EXAppExtensionAttributes</key><dict><key>EXExtensionPointIdentifier</key><string>com.apple.crash-reporter.extension</string></dict>
		<key>ExampleCrashAppGroup</key><string>group.com.example.app</string>
		<key>ExampleCrashDirectory</key><string>Library/Application Support/Example/NewsHelicopter</string>
		</dict></plist>
		"""
		let info = try #require(try PropertyListSerialization.propertyList(from: Data(plist.utf8), format: nil) as? [String: Any])
		#expect(CrashReportLocations(info: info, keys: keys) == expected)
	}

	@Test func aMissingKeyNamesNoPlace() {
		#expect(CrashReportLocations(info: ["ExampleCrashAppGroup": "group.com.example.app"], keys: keys) == nil)
		#expect(CrashReportLocations(info: ["ExampleCrashDirectory": "x"], keys: keys) == nil)
	}

	@Test func theDirectoryIsRelativeToTheGroupContainer() {
		let container = URL(fileURLWithPath: "/tmp/group")
		#expect(expected.directory(in: container).path == "/tmp/group/Library/Application Support/Example/NewsHelicopter")
	}
}
