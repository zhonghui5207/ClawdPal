import ClawdPetCore
import Foundation

final class CodexTranscriptMonitor {
    private struct CachedSnapshot {
        var modifiedAt: Date
        var fileSize: UInt64
        var accumulator: CodexTranscriptParser.Accumulator
        var snapshot: CodexTranscriptSnapshot?
    }

    private struct IndexCache {
        var modifiedAt: Date
        var threadNames: [String: String]
    }

    private let fileManager = FileManager.default
    private let sessionsRoot: URL
    private let sessionIndexURL: URL
    private let startedAt: Date
    private var cache: [URL: CachedSnapshot] = [:]
    private var indexCache: IndexCache?

    init(
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"),
        sessionIndexURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/session_index.jsonl"),
        startedAt: Date = Date()
    ) {
        self.sessionsRoot = sessionsRoot
        self.sessionIndexURL = sessionIndexURL
        self.startedAt = startedAt
    }

    func snapshots(now: Date = Date()) -> [CodexTranscriptSnapshot] {
        let threadNames = loadThreadNames()

        return candidateFiles(now: now).compactMap { url in
            let snapshot = snapshot(for: url)
            guard var snapshot else { return nil }
            if snapshot.taskTitle == nil {
                snapshot.taskTitle = threadNames[snapshot.sessionID]
            }
            return snapshot
        }
    }

    private func snapshot(for url: URL) -> CodexTranscriptSnapshot? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let modifiedAt = attributes[.modificationDate] as? Date,
              let fileSize = attributes[.size] as? NSNumber else {
            return nil
        }

        let size = fileSize.uint64Value

        if let cached = cache[url], cached.modifiedAt == modifiedAt, cached.fileSize == size {
            return cached.snapshot
        }

        if var cached = cache[url], size >= cached.fileSize, let delta = try? readDelta(from: url, offset: cached.fileSize) {
            do {
                try cached.accumulator.consume(text: delta)
                cached.modifiedAt = modifiedAt
                cached.fileSize = size
                cached.snapshot = cached.accumulator.snapshot()
                cache[url] = cached
                return cached.snapshot
            } catch {
                // fall through to full reload on parse mismatch
            }
        }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        do {
            var accumulator = CodexTranscriptParser.Accumulator(activityCutoff: startedAt)
            try accumulator.consume(text: text)
            let snapshot = accumulator.snapshot()
            cache[url] = CachedSnapshot(
                modifiedAt: modifiedAt,
                fileSize: size,
                accumulator: accumulator,
                snapshot: snapshot
            )
            return snapshot
        } catch {
            return nil
        }
    }

    private func readDelta(from url: URL, offset: UInt64) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private func loadThreadNames() -> [String: String] {
        guard let attributes = try? fileManager.attributesOfItem(atPath: sessionIndexURL.path),
              let modifiedAt = attributes[.modificationDate] as? Date else {
            return [:]
        }

        if let indexCache, indexCache.modifiedAt == modifiedAt {
            return indexCache.threadNames
        }

        guard let data = try? Data(contentsOf: sessionIndexURL),
              let text = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var threadNames: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)),
                  let object = value.objectValue,
                  let sessionID = object["id"]?.stringValue,
                  let threadName = object["thread_name"]?.stringValue,
                  !threadName.isEmpty else {
                continue
            }
            threadNames[sessionID] = threadName
        }

        indexCache = IndexCache(modifiedAt: modifiedAt, threadNames: threadNames)
        return threadNames
    }

    private func candidateFiles(now: Date) -> [URL] {
        var urls: [URL] = []
        let calendar = Calendar.current
        let freshnessCutoff = max(startedAt, now.addingTimeInterval(-(60 * 90)))

        for dayOffset in 0...1 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard
                let year = components.year,
                let month = components.month,
                let day = components.day
            else {
                continue
            }

            let directory = sessionsRoot
                .appendingPathComponent(String(format: "%04d", year))
                .appendingPathComponent(String(format: "%02d", month))
                .appendingPathComponent(String(format: "%02d", day))

            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            urls.append(contentsOf: entries.filter { entry in
                guard entry.pathExtension == "jsonl" else { return false }
                let modifiedAt = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return modifiedAt >= freshnessCutoff
            })
        }

        let sorted = urls
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
        return (sorted.isEmpty ? urls.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) : sorted)
            .prefix(6)
            .map { $0 }
    }
}
