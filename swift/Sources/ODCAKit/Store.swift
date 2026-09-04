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
    public let colorSetsFile: URL

    /// Built-in fallback so the default slot always exists (R-U4).
    public static let defaultColorSets: [Int: ColorSet] = [
        1: ColorSet(name: "ODCA default", colors: ["#121218", "#EBEBE1", "#FFA136", "#409CFF"])
    ]

    public init(
        stateDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".odca"),
        keeperFile: URL = Store.repoRoot.appendingPathComponent("interesting-rules.txt"),
        colorSetsFile: URL = Store.repoRoot.appendingPathComponent("colorsets/colorsets.json")
    ) {
        self.stateDir = stateDir
        self.keeperFile = keeperFile
        self.colorSetsFile = colorSetsFile
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

    // R-P4: color sets file, shared by all implementations.
    private static func validColor(_ c: String) -> Bool {
        c.count == 7 && c.hasPrefix("#") && c.dropFirst().allSatisfy { $0.isHexDigit }
    }

    /// {slot: ColorSet}; malformed entries skipped, slot 1 always present.
    public func loadColorSets() -> [Int: ColorSet] {
        var sets = Store.defaultColorSets
        guard let data = try? Data(contentsOf: colorSetsFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["sets"] as? [Any] else { return sets }
        for case let entry as [String: Any] in entries {
            guard let slot = entry["slot"] as? Int, (0...9).contains(slot),
                  let name = entry["name"] as? String,
                  let colors = entry["colors"] as? [String], colors.count == 4,
                  colors.allSatisfy(Store.validColor) else { continue }
            sets[slot] = ColorSet(name: name, colors: colors.map { $0.uppercased() })
        }
        return sets
    }

    /// Writes the same layout as Python's json.dumps(indent=1) so an 'S'
    /// from either implementation leaves the shared file byte-stable.
    public func saveColorSets(_ sets: [Int: ColorSet]) {
        func quoted(_ s: String) -> String {
            var out = "\""
            for scalar in s.unicodeScalars {
                switch scalar {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                default:
                    if scalar.value < 0x20 || scalar.value > 0x7E {
                        out += String(format: "\\u%04x", scalar.value)
                    } else {
                        out.unicodeScalars.append(scalar)
                    }
                }
            }
            return out + "\""
        }
        let entries = sets.keys.sorted().map { slot -> String in
            let set = sets[slot]!
            let colors = set.colors.map { "    " + quoted($0) }.joined(separator: ",\n")
            return "  {\n   \"slot\": \(slot),\n   \"name\": \(quoted(set.name)),\n   \"colors\": [\n\(colors)\n   ]\n  }"
        }
        let text = "{\n \"sets\": [\n" + entries.joined(separator: ",\n") + "\n ]\n}\n"
        try? FileManager.default.createDirectory(
            at: colorSetsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: colorSetsFile, atomically: true, encoding: .utf8)
    }
}

/// A named color set: four "#RRGGBB" strings in state order (R-U4).
public struct ColorSet: Equatable {
    public var name: String
    public var colors: [String]

    public init(name: String, colors: [String]) {
        self.name = name
        self.colors = colors
    }
}
