//
//  NewsHelicopterIngestTerminationTests.swift
//  CrashReportingTests
//
//  The codes real crash-extension reports carried — `[10, reason]`, whatever
//  the exception — become a termination reason the server can read, not an
//  exception code of 10 on everything.
//

import NewsHelicopter
import Foundation
import Testing
@testable import CrashReporting

@Suite("Crash extension ingest: termination reasons")
struct NewsHelicopterIngestTerminationTests {
	private func metadata(_ reason: NewsHelicopterReport.Reason) throws -> [String: Any] {
		let report = NewsHelicopterReport(app: .init(bundleID: "com.example.app", version: "1.0", build: "1", executable: "ExampleApp", osVersion: "27.0.1"),
		                                  reason: reason, images: [], threads: [], annotations: [], crumbs: nil, elapsedMilliseconds: 1)
		let diagnostic = NewsHelicopterIngest.diagnostic(for: report)
		let newsHelicopter = try #require(diagnostic["newsHelicopter"] as? [String: Any])
		#expect(newsHelicopter["codes"] as? [String] == reason.codes.map(String.init), "the raw codes ride along untouched")
		return try #require(diagnostic["diagnosticMetaData"] as? [String: Any])
	}

	@Test("a watchdog kill reads as FrontBoard's 0x8BADF00D")
	func watchdog() throws {
		let codes: [UInt64] = [10, 45_293_105_165]
		let metadata = try metadata(.init(exception: 10, codes: codes, exceptionName: "EXC_CRASH", signalName: "SIGKILL",
		                                  terminationReason: .decode(codes: codes)))
		#expect(metadata["exceptionCode"] as? UInt64 == 0x8BAD_F00D)
		#expect(metadata["terminationNamespace"] as? Int == 10)
		#expect(metadata["terminationNamespaceName"] as? String == "FRONTBOARD")
		#expect(metadata["terminationCode"] as? UInt64 == 0x8BAD_F00D)
		#expect(metadata["terminationName"] as? String == "FRONTBOARD watchdog (0x8BADF00D)")
		#expect(metadata["terminationReason"] as? String == "EXC_CRASH (SIGKILL): FRONTBOARD watchdog (0x8BADF00D)")
		#expect(metadata["signal"] as? Int == 9)
	}

	@Test("a jetsam kill from an older extension, which stored no reason, still decodes")
	func olderJetsam() throws {
		let metadata = try metadata(.init(exception: 11, codes: [10, 4_294_967_303], exceptionName: "EXC_RESOURCE", signalName: "SIGKILL"))
		#expect(metadata["exceptionCode"] as? UInt64 == 7)
		#expect(metadata["terminationNamespace"] as? Int == 1)
		#expect(metadata["terminationName"] as? String == "JETSAM per-process-limit")
		#expect(metadata["terminationReason"] as? String == "EXC_RESOURCE (SIGKILL): JETSAM per-process-limit")
	}

	@Test("an older extension's guessed signal is dropped when nothing decoded backs it")
	func olderGuess() throws {
		let metadata = try metadata(.init(exception: 1, codes: [10, 0x3_0000_0002], exceptionName: "EXC_BAD_ACCESS", signalName: "SIGBUS"))
		#expect(metadata["signal"] == nil)
		#expect(metadata["terminationReason"] as? String == "EXC_BAD_ACCESS: CODESIGNING invalid page")
	}

	@Test("Mach-layout codes keep their first code and carry no termination fields")
	func machLayout() throws {
		let metadata = try metadata(.init(exception: 6, codes: [1, 0], exceptionName: "EXC_BREAKPOINT", signalName: "SIGTRAP"))
		#expect(metadata["exceptionCode"] as? UInt64 == 1)
		#expect(metadata["terminationNamespace"] == nil)
		#expect(metadata["terminationReason"] as? String == "EXC_BREAKPOINT (SIGTRAP)")
		#expect(metadata["signal"] as? Int == 5)
	}
}
