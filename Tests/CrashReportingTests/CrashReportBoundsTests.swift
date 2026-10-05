import Foundation
import Testing
@testable import CrashReporting

/// A stack of thousands of frames must never reach the encoder as a tree of thousands of levels.
@Suite("Crash report frame bounds")
@MainActor
struct CrashReportBoundsTests {
	private func chain(_ count: Int, thread: Int = 0) -> String {
		let frames = (0..<count).map { #"{"binaryName":"ExampleApp","offsetIntoBinaryTextSegment":\#($0 + thread * 10_000),"subFrames":["# }
		return frames.joined() + String(repeating: "]}", count: count)
	}
	private func report(stacks: String) throws -> CrashReport {
		try CrashReport(kind: .crash, occurredAt: .now, device: .sample, bundleID: "com.example.app",
			diagnosticJSON: Data(#"{"callStackTree":{"callStacks":[\#(stacks)]}}"#.utf8))
	}
	private func depth(of data: Data) -> Int {
		var current = 0, deepest = 0
		for byte in data {
			if byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[") { current += 1; deepest = max(deepest, current) }
			else if byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]") { current -= 1 }
		}
		return deepest
	}
	private func offsets(_ data: Data) throws -> [Int] {
		var frame = try #require((JSONSerialization.jsonObject(with: data) as? [String: Any])?["diagnostic"] as? [String: Any])
		frame = try #require((frame["callStackTree"] as? [String: Any])?["callStacks"] as? [[String: Any]]).first ?? [:]
		var next = (frame["callStackRootFrames"] as? [[String: Any]])?.first, kept: [Int] = []
		while let current = next {
			kept.append(current["offsetIntoBinaryTextSegment"] as? Int ?? -1)
			next = (current["subFrames"] as? [[String: Any]])?.first
		}
		return kept
	}
	@Test func encodedDepthStaysBoundedForAStackTooDeepToEncode() throws {
		let data = try report(stacks: #"{"threadAttributed":true,"callStackRootFrames":[\#(chain(250))]}"#).encoded()
		#expect(depth(of: data) < 2 * CrashReport.maxFrameDepth + 8)
		let kept = try offsets(data)
		#expect(kept == Array(0..<CrashReport.maxFrameDepth), "the innermost frames survive, in order")
		#expect(String(decoding: data, as: UTF8.self).contains(#""truncatedFrames":202"#))
	}
	@Test func aStackBeyondFoundationsParserIsRefusedRatherThanWalked() throws {
		#expect(throws: (any Error).self) { try report(stacks: #"{"callStackRootFrames":[\#(chain(300))]}"#) }
	}
	@Test func everyThreadIsBoundedIndependently() throws {
		let stacks = #"{"callStackRootFrames":[\#(chain(5))]},{"callStackRootFrames":[\#(chain(200, thread: 1))]}"#
		let data = try report(stacks: stacks).encoded()
		#expect(depth(of: data) < 2 * CrashReport.maxFrameDepth + 8)
		#expect(String(decoding: data, as: UTF8.self).contains(#""truncatedFrames":152"#))
	}
	@Test func shortStacksAreLeftUntouched() throws {
		let data = try report(stacks: #"{"callStackRootFrames":[\#(chain(40))]}"#).encoded()
		#expect(try offsets(data).count == 40)
		#expect(!String(decoding: data, as: UTF8.self).contains("truncatedFrames"))
	}
}
