#if canImport(MetricKit)
	import Foundation
	import MetricKit

	extension CrashReporter {
		/// SDK objects stay on MetricKit's callback thread; only copies cross to the main actor.
		final class Subscriber: NSObject, MXMetricManagerSubscriber {
			nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
				var entries: [CrashCapture] = []
				for payload in payloads {
					for crash in payload.crashDiagnostics ?? [] { entries.append(Self.copy(crash, kind: .crash, at: payload.timeStampBegin)) }
					for hang in payload.hangDiagnostics ?? [] { entries.append(Self.copy(hang, kind: .hang, at: payload.timeStampBegin)) }
				}
				let captured = entries
				Task { @MainActor in await CrashReporter.receive(captured) }
			}

			nonisolated private static func copy(_ diagnostic: MXDiagnostic, kind: CrashReport.Kind, at date: Date) -> CrashCapture {
				CrashCapture(kind: kind, occurredAt: date, json: diagnostic.jsonRepresentation(), appVersion: diagnostic.applicationVersion, appBuild: diagnostic.metaData.applicationBuildVersion, osVersion: diagnostic.metaData.osVersion, model: diagnostic.metaData.deviceType)
			}
		}
	}
#endif
