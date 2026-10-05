import Foundation

/// Serializes disk operations; report files are the immutable wire payload.
public actor CrashReportQueue {
	private let directory: URL
	private let capacity: Int
	private let files = FileManager.default
	public init(directory: URL, capacity: Int = 50) {
		self.directory = directory
		self.capacity = max(1, capacity)
	}
	public func enqueue(_ report: CrashReport) throws {
		try files.createDirectory(at: directory, withIntermediateDirectories: true)
		let path = url(report.reportID)
		guard !files.fileExists(atPath: path.path) else { return }
		try report.encoded().write(to: path, options: .atomic)
		let entries = try orderedFiles()
		for entry in entries.prefix(max(0, entries.count - capacity)) { try files.removeItem(at: entry) }
	}
	public func pending() throws -> [CrashReport] {
		try orderedFiles().compactMap { path in
			guard let data = try? Data(contentsOf: path), let report = try? CrashReport.decode(data),
				path.lastPathComponent == url(report.reportID).lastPathComponent else { return nil }
			return report
		}
	}
	public func remove(_ id: UUID) throws {
		let path = url(id)
		if files.fileExists(atPath: path.path) { try files.removeItem(at: path) }
	}
	private func url(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
	private func orderedFiles() throws -> [URL] {
		guard files.fileExists(atPath: directory.path) else { return [] }
		let entries = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])
		var dated: [(url: URL, date: Date)] = []
		for entry in entries where entry.pathExtension == "json" {
			let values = try entry.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
			if values.isRegularFile == true { dated.append((entry, values.contentModificationDate ?? .distantPast)) }
		}
		dated.sort { lhs, rhs in
			lhs.date == rhs.date ? lhs.url.lastPathComponent < rhs.url.lastPathComponent : lhs.date < rhs.date
		}
		return dated.map(\.url)
	}
}
