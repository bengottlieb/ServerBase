@testable import CrashReporting

extension CrashDevice {
	static let sample = CrashDevice(installID: "6F9619FF-8B86-D011-B42D-00C04FC964FF", platform: "iOS", model: "iPhone17,1", osVersion: "27.0", appVersion: "1.0", appBuild: "42", distribution: "testflight", isSimulator: false)
}

extension CrashDeviceSnapshot {
	static let sample = try! CrashDeviceSnapshot(CrashDevice.sample)
}
