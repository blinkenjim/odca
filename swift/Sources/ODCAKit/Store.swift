import Foundation

/// Persistence (R-P): per-user state in ~/.odca/, the keeper file at the
/// repository root. Loaders treat missing or malformed files as absent.
public struct Store {
    /// Repository root, anchored from this source file's location:
    /// swift/Sources/ODCAKit/Store.swift -> up four levels (R-P3).
    public static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // ODCAKit
        .deletingLastPathComponent()  // Sources
        .deletingLastPathComponent()  // swift
        .deletingLastPathComponent()  // repository root

    public let stateDir: URL
    public let keeperFile: URL

    public init(
        stateDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".odca"),
        keeperFile: URL = Store.repoRoot.appendingPathComponent("interesting-rules.txt")
    ) {
        self.stateDir = stateDir
        self.keeperFile = keeperFile
    }

    var ruleFile: URL { stateDir.appendingPathComponent("rule") }
    var candidatesFile: URL { stateDir.appendingPathComponent("candidates") }

    private func ensureStateDir() {
        try? FileManager.default.createDirectory(
            at: stateDir, withIntermediateDirectories: true)
    }

    // R-P1: current rule.
    public func loadRule() -> Rule? {
        guard let text = try? String(contentsOf: ruleFile, encoding: .utf8) else {
            return nil
        }
        return try? Rule(id: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func saveRule(_ rule: Rule) {
        ensureStateDir()
        try? (rule.id + "\n").write(to: ruleFile, atomically: true, encoding: .utf8)
    }

    // R-P2: candidate stash, one ID per line, invalid lines skipped.
    public func loadCandidates() -> [Rule] {
        guard let text = try? String(contentsOf: candidatesFile, encoding: .utf8) else {
            return []
        }
        return text.split(separator: "\n").compactMap {
            try? Rule(id: $0.trimmingCharacters(in: .whitespaces))
        }
    }

    public func saveCandidates(_ rules: [Rule]) {
        ensureStateDir()
        try? rules.map { $0.id + "\n" }.joined()
            .write(to: candidatesFile, atomically: true, encoding: .utf8)
    }

    // R-P3: keeper file, "rule <id>" lines; non-conforming lines ignored.
    public func appendInteresting(_ rule: Rule) {
        let line = "rule \(rule.id)\n"
        if let handle = try? FileHandle(forWritingTo: keeperFile) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? line.write(to: keeperFile, atomically: true, encoding: .utf8)
        }
    }

    public func loadInteresting() -> [Rule] {
        guard let text = try? String(contentsOf: keeperFile, encoding: .utf8) else {
            return []
        }
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard parts.count == 2, parts[0] == "rule" else { return nil }
            return try? Rule(id: String(parts[1]))
        }
    }
}
