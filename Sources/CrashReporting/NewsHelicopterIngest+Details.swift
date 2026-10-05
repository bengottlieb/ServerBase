import Foundation
import NewsHelicopter

extension NewsHelicopterIngest {
	/// Everything the extension knows that MetricKit's shape has no room for.
	static func newsHelicopter(for report: NewsHelicopterReport) -> [String: Any] {
		var object: [String: Any] = [
			"reportID": report.id.uuidString.lowercased(),
			"capturedAt": ISO8601DateFormatter().string(from: report.capturedAt),
			"elapsedMilliseconds": report.elapsedMilliseconds,
			"exceptionName": report.reason.exceptionName,
			"codes": report.reason.codes.map(String.init),
			"annotations": report.annotations.map { annotation -> [String: Any] in
				var fields: [String: Any] = ["image": annotation.image, "abortCause": annotation.abortCause]
				if let text = annotation.message { fields["message"] = text }
				if let text = annotation.message2 { fields["message2"] = text }
				if let text = annotation.signature { fields["signature"] = text }
				return fields
			},
			"threads": report.threads.map { thread -> [String: Any] in
				var fields: [String: Any] = ["index": thread.index, "id": String(thread.id), "isCrashed": thread.isCrashed,
				                             "registers": thread.registers.mapValues { String($0, radix: 16) },
				                             "frames": thread.frames.map { frame -> [String: Any] in
					var fields: [String: Any] = ["address": String(frame.address, radix: 16)]
					if let index = frame.imageIndex, report.images.indices.contains(index) { fields["image"] = report.images[index].name }
					if let offset = frame.offsetInImage { fields["offset"] = String(offset) }
					if !frame.symbols.isEmpty {
						fields["symbols"] = frame.symbols.map { symbol -> [String: Any] in
							var fields: [String: Any] = ["name": symbol.name, "offset": symbol.offset, "inline": symbol.isInline]
							if let file = symbol.file { fields["file"] = file }
							if let line = symbol.line { fields["line"] = line }
							return fields
						}
					}
					return fields
				}]
				if let name = thread.name { fields["name"] = name }
				return fields
			},
		]
		if let signal = report.reason.signalName { object["signalName"] = signal }
		if let footprint = report.memoryFootprintBytes { object["memoryFootprintBytes"] = footprint }
		if let crumbs = report.crumbs {
			var fields: [String: Any] = ["lines": crumbs.lines]
			if let runID = crumbs.runID { fields["runID"] = runID }
			if let screen = crumbs.screen { fields["screen"] = screen }
			object["crumbs"] = fields
		}
		return object
	}

	static func signalNumber(_ name: String) -> Int? {
		switch name {
		case "SIGABRT": 6
		case "SIGBUS": 10
		case "SIGFPE": 8
		case "SIGILL": 4
		case "SIGKILL": 9
		case "SIGSEGV": 11
		case "SIGTRAP": 5
		case "SIGTERM": 15
		case "SIGSYS": 12
		case "SIGPIPE": 13
		default: nil
		}
	}
}
