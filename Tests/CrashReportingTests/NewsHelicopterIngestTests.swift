//
//  NewsHelicopterIngestTests.swift
//  CrashReportingTests
//
//  The extension's report becomes the queue's report: MetricKit's shape for
//  the server's signature and symbolication, everything else under `newsHelicopter`.
//

import NewsHelicopter
import Foundation
import Testing
@testable import CrashReporting

@Suite("Crash extension ingest")
@MainActor
struct NewsHelicopterIngestTests {
	private func sample() -> NewsHelicopterReport {
		let images = [
			NewsHelicopterReport.Image(path: "/usr/lib/system/libsystem_kernel.dylib", uuid: UUID(uuidString: "11111111-2222-3333-4444-555555555555"), baseAddress: 0x1_8000_0000, size: 0x10000),
			NewsHelicopterReport.Image(path: "/private/var/containers/Bundle/Application/X/ExampleApp.app/ExampleApp", uuid: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"), baseAddress: 0x1_0000_0000, size: 0x100000),
		]
		let crashed = NewsHelicopterReport.Thread(index: 0, id: 7, name: "main", queueName: nil, isCrashed: true, frames: [
			NewsHelicopterReport.Frame(address: 0x1_8000_0010, imageIndex: 0, offsetInImage: 0x10,
			                    symbols: [NewsHelicopterReport.Symbol(name: "__pthread_kill", offset: 8, file: nil, line: nil, isInline: false)]),
			NewsHelicopterReport.Frame(address: 0x1_0000_1234, imageIndex: 1, offsetInImage: 0x1234,
			                    symbols: [NewsHelicopterReport.Symbol(name: "LibraryScreen.body", offset: 40, file: "LibraryScreen.swift", line: 103, isInline: true)]),
			NewsHelicopterReport.Frame(address: 0x1_0000_0100, imageIndex: 1, offsetInImage: 0x100, symbols: []),
		], registers: ["pc": 0x1_8000_0010, "far": 0])
		let other = NewsHelicopterReport.Thread(index: 1, id: 9, name: nil, queueName: nil, isCrashed: false, frames: [
			NewsHelicopterReport.Frame(address: 0x1_8000_0020, imageIndex: 0, offsetInImage: 0x20, symbols: []),
		], registers: [:])
		return NewsHelicopterReport(id: UUID(uuidString: "0BADF00D-0000-4000-8000-000000000001")!, capturedAt: Date(timeIntervalSince1970: 1_789_300_000),
		                     app: .init(bundleID: "com.example.app", version: "2026.4", build: "2478", executable: "ExampleApp", osVersion: "27.0"),
		                     reason: .init(exception: 6, codes: [1, 0], exceptionName: "EXC_BREAKPOINT", signalName: "SIGTRAP"),
		                     images: images, threads: [other, crashed],
		                     annotations: [.init(image: "libswiftCore.dylib", message: "Fatal error: No Observable object of type ReviewModel found.", message2: nil, signature: nil, abortCause: 0)],
		                     crumbs: .init(runID: "run-42", screen: "library", lines: ["launch: CatalogSync begins", "screen library"]),
		                     elapsedMilliseconds: 12.5)
	}

	@Test("the queue's report carries MetricKit's shape, rooted at the crashing frame")
	func metricKitShape() throws {
		let report = try NewsHelicopterIngest.report(from: sample(), device: .sample, bundleID: "com.example.app")
		#expect(report.kind == .crash)
		#expect(report.reportID == sample().id)
		#expect(report.occurredAt == sample().capturedAt)
		let body = try #require(JSONSerialization.jsonObject(with: report.encoded()) as? [String: Any])
		let device = try #require(body["device"] as? [String: Any])
		#expect(device["bundleID"] as? String == "com.example.app", "the crashed app's, not the ingesting build's")
		#expect(device["appBuild"] as? String == "2478")
		let diagnostic = try #require(body["diagnostic"] as? [String: Any])
		#expect(diagnostic["source"] as? String == "news-helicopter")
		let metadata = try #require(diagnostic["diagnosticMetaData"] as? [String: Any])
		#expect(metadata["exceptionType"] as? Int == 6)
		#expect(metadata["signal"] as? Int == 5)
		#expect(metadata["exceptionReason"] as? String == "Fatal error: No Observable object of type ReviewModel found.")
		#expect(metadata["terminationReason"] as? String == "EXC_BREAKPOINT (SIGTRAP)")
		let tree = try #require(diagnostic["callStackTree"] as? [String: Any])
		let stacks = try #require(tree["callStacks"] as? [[String: Any]])
		#expect(stacks.count == 2)
		let attributed = try #require(stacks.first { $0["threadAttributed"] as? Bool == true })
		let roots = try #require(attributed["callStackRootFrames"] as? [[String: Any]])
		#expect(roots.count == 1)
		#expect(roots[0]["binaryName"] as? String == "libsystem_kernel.dylib", "the root is the crashing frame")
		#expect(roots[0]["offsetIntoBinaryTextSegment"] as? String == "16")
		#expect(roots[0]["binaryUUID"] as? String == "11111111-2222-3333-4444-555555555555")
		let caller = try #require((roots[0]["subFrames"] as? [[String: Any]])?.first)
		#expect(caller["binaryName"] as? String == "ExampleApp")
		#expect(caller["offsetIntoBinaryTextSegment"] as? String == "4660")
		let outermost = try #require((caller["subFrames"] as? [[String: Any]])?.first)
		#expect(outermost["subFrames"] == nil)
	}

	@Test("what MetricKit has no room for rides under newsHelicopter")
	func newsHelicopterDetail() throws {
		let diagnostic = NewsHelicopterIngest.diagnostic(for: sample())
		let newsHelicopter = try #require(diagnostic["newsHelicopter"] as? [String: Any])
		let crumbs = try #require(newsHelicopter["crumbs"] as? [String: Any])
		#expect(crumbs["runID"] as? String == "run-42")
		#expect(crumbs["screen"] as? String == "library")
		#expect((crumbs["lines"] as? [String])?.count == 2)
		let threads = try #require(newsHelicopter["threads"] as? [[String: Any]])
		let crashed = try #require(threads.first { $0["isCrashed"] as? Bool == true })
		let frames = try #require(crashed["frames"] as? [[String: Any]])
		let symbol = try #require((frames[1]["symbols"] as? [[String: Any]])?.first)
		#expect(symbol["name"] as? String == "LibraryScreen.body")
		#expect(symbol["line"] as? Int == 103)
		#expect(symbol["inline"] as? Bool == true)
		#expect((newsHelicopter["annotations"] as? [[String: Any]])?.first?["message"] as? String == sample().headline)
		#expect(newsHelicopter["elapsedMilliseconds"] as? Double == 12.5)
	}

	@Test("draining moves every report onto the queue and out of the store")
	func drain() async throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		let store = NewsHelicopterReportStore(directory: root.appendingPathComponent("NewsHelicopter"))
		let queue = CrashReportQueue(directory: root.appendingPathComponent("CrashReports"))
		try store.write(sample())
		let moved = await NewsHelicopterIngest.drain(store, into: queue, device: .sample, bundleID: "com.example.app")
		#expect(moved == 1)
		#expect(store.reports().isEmpty)
		#expect(try await queue.pending().map(\.reportID) == [sample().id])
	}
}
