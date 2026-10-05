import Foundation

/// The device a report came from, as the report carries it: whatever fields the app describes its devices with, copied
/// once into a small value that crosses actors. An app with its own device type (main-actor bound, more fields) makes one
/// from that on the main actor; otherwise `CrashDevice` covers the hardware and the build.
public struct CrashDeviceSnapshot: Sendable {
	let fields: [String: CrashJSON]
	/// The hardware model, for a report whose diagnostic doesn't name one.
	public let model: String

	public init(_ device: some Encodable, model: String) throws {
		fields = try JSONDecoder().decode([String: CrashJSON].self, from: JSONEncoder().encode(device))
		self.model = model
	}

	public init(_ device: CrashDevice) throws {
		try self.init(device, model: device.model)
	}
}
