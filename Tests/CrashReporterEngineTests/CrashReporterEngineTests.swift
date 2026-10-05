import Foundation
import Testing
@testable import CrashReporterEngine

/// The extension finds its store only through its Info.plist; a plist that doesn't name one must give no store rather
/// than a guess.
@Suite("Crash reporter engine")
struct CrashReporterEngineTests {
	let keys = CrashReportLocations.InfoKeys(appGroup: "ExampleCrashAppGroup", directory: "ExampleCrashDirectory")

	@Test func aPlistWithoutTheKeysHasNoStore() {
		#expect(CrashReportLocations.store(keys: keys, info: [:]) == nil)
		#expect(CrashReportLocations.store(keys: keys, info: ["ExampleCrashAppGroup": "group.com.example.app"]) == nil)
	}
}
