import Foundation

/// MetricKit nests every frame inside its caller as `subFrames`, so a long stack is a JSON tree
/// hundreds of levels deep, and both `JSONDecoder` and `JSONEncoder` recurse through all of it.
/// The pruning happens on Foundation's own parse, before any `Codable` walk. A linear chain (a crash
/// stack) keeps its innermost frames, which the signature reads, and its outermost, where the app's own
/// code often sits under a deep framework stack; the frame before the gap counts what was elided as
/// `truncatedFrames`. A branching tree (a hang) keeps only the innermost levels, with a count of the rest.
extension CrashReport {
	/// Measured on a 512 KB thread: the encoder overflows near 80 nested frames in Debug, 90 in Release.
	static let maxFrameDepth = 48
	/// How much of `maxFrameDepth` a linear chain spends on its outer end.
	static let outerFrameCount = 16

	static func boundingFrames(in diagnosticJSON: Data, limit: Int = maxFrameDepth) throws -> Data {
		guard var root = try JSONSerialization.jsonObject(with: diagnosticJSON) as? [String: Any],
			var tree = root["callStackTree"] as? [String: Any], let stacks = tree["callStacks"] as? [[String: Any]] else { return diagnosticJSON }
		tree["callStacks"] = stacks.map { stack in
			guard let roots = stack["callStackRootFrames"] as? [Any] else { return stack }
			var copy = stack
			copy["callStackRootFrames"] = roots.map { bounded($0, remaining: limit) }
			return copy
		}
		root["callStackTree"] = tree
		return try JSONSerialization.data(withJSONObject: root)
	}

	// Recursion here is bounded by `remaining`, unlike the coders' walk of the original tree.
	private static func bounded(_ frame: Any, remaining: Int) -> Any {
		guard var fields = frame as? [String: Any], let children = fields["subFrames"] as? [Any], !children.isEmpty else { return frame }
		if remaining == outerFrameCount + 1, let chain = linearChain(below: children), chain.count > outerFrameCount {
			fields["subFrames"] = [chain[chain.count - outerFrameCount]]
			fields["truncatedFrames"] = chain.count - outerFrameCount
		} else if remaining > 1 {
			fields["subFrames"] = children.map { bounded($0, remaining: remaining - 1) }
		} else {
			fields["subFrames"] = nil
			fields["truncatedFrames"] = frameCount(below: children)
		}
		return fields
	}

	/// The frames below, outermost last, or nil if any level has more than one caller.
	private static func linearChain(below frames: [Any]) -> [[String: Any]]? {
		var chain: [[String: Any]] = [], next = frames
		while let only = next.first {
			guard next.count == 1, let fields = only as? [String: Any] else { return nil }
			chain.append(fields)
			next = fields["subFrames"] as? [Any] ?? []
		}
		return chain
	}

	private static func frameCount(below frames: [Any]) -> Int {
		var pending = frames, count = 0
		while let next = pending.popLast() {
			guard let fields = next as? [String: Any] else { continue }
			count += 1
			if let children = fields["subFrames"] as? [Any] { pending.append(contentsOf: children) }
		}
		return count
	}
}
