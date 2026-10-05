#if DEBUG
	import Foundation
	import MachO

	/// A synthetic diagnostic with real loaded-app UUIDs/offsets, suitable for simulator dSYM verification.
	public enum CrashReportSample {
		public static func makeJSON() throws -> Data {
			let addresses = Thread.callStackReturnAddresses.map(\.uint64Value)
			let product = Bundle.main.executableURL?.lastPathComponent ?? ""
			var frames: [[String: Any]] = []
			for index in 0..<_dyld_image_count() {
				guard let name = _dyld_get_image_name(index), let header = _dyld_get_image_header(index), header.pointee.magic == MH_MAGIC_64 else { continue }
				let binary = URL(fileURLWithPath: String(cString: name)).lastPathComponent
				guard binary == product || binary == product + ".debug.dylib" else { continue }
				var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
				var uuid: String?, text: segment_command_64?
				for _ in 0..<header.pointee.ncmds {
					let load = command.load(as: load_command.self)
					if load.cmd == LC_UUID { uuid = UUID(uuid: command.load(as: uuid_command.self).uuid).uuidString }
					if load.cmd == LC_SEGMENT_64 {
						let segment = command.load(as: segment_command_64.self)
						let segmentName = withUnsafeBytes(of: segment.segname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
						if segmentName == "__TEXT" { text = segment }
					}
					command = command.advanced(by: Int(load.cmdsize))
				}
				guard let uuid, let text else { continue }
				let base = UInt64(bitPattern: Int64(bitPattern: text.vmaddr) &+ Int64(_dyld_get_image_vmaddr_slide(index)))
				for address in addresses where address >= base && address - base < text.vmsize {
					frames.append(["binaryUUID": uuid, "binaryName": binary, "offsetIntoBinaryTextSegment": String(address - base), "address": String(address)])
				}
			}
			guard !frames.isEmpty else { throw CocoaError(.coderInvalidValue) }
			return try JSONSerialization.data(withJSONObject: [
				"diagnosticMetaData": ["exceptionType": "DeveloperSample", "terminationReason": "Synthetic sample; app did not crash"],
				"callStackTree": ["callStacks": [["threadAttributed": true, "callStackRootFrames": Array(frames.prefix(8))]]],
			])
		}
	}
#endif
