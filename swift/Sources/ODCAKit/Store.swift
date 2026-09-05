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
    public let candidatePalettesFile: URL

    /// Built-in fallback so the default slot always exists (R-U4).
    public static let defaultColorSets: [Int: ColorSet] = [
        1: ColorSet(name: "ODCA default", colors: ["#121218", "#EBEBE1", "#FFA136", "#409CFF"])
    ]

    public init(
        stateDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".odca"),
        keeperFile: URL = Store.repoRoot.appendingPathComponent("interesting-rules.json"),
        colorSetsFile: URL = Store.repoRoot.appendingPathComponent("colorsets/colorsets.json"),
        candidatePalettesFile: URL = Store.repoRoot.appendingPathComponent("colorsets/candidates.json")
    ) {
        self.stateDir = stateDir
        self.keeperFile = keeperFile
        self.colorSetsFile = colorSetsFile
        self.candidatePalettesFile = candidatePalettesFile
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

    // R-P3: keeper file — a screensaver-format file of rule / color set pairs.
    public func loadInterestingPairs() -> [ScreensaverPair] {
        Store.loadScreensaver(keeperFile) ?? []
    }

    /// The saved rules in order (one per pair; a rule may recur with other colors).
    public func loadInteresting() -> [Rule] {
        loadInterestingPairs().compactMap { try? Rule(id: $0.rule) }
    }

    public func appendInteresting(_ pair: ScreensaverPair) {
        Store.saveScreensaver(loadInterestingPairs() + [pair], to: keeperFile)
    }

    /// Convenience: save a rule with the built-in default color set.
    public func appendInteresting(_ rule: Rule) {
        let d = Store.defaultColorSets[1]!
        appendInteresting(ScreensaverPair(rule: rule.id, colorset: d.name, colors: d.colors))
    }

    // R-P4: color sets file, shared by all implementations.
    private static func validColor(_ c: String) -> Bool {
        c.count == 7 && c.hasPrefix("#") && c.dropFirst().allSatisfy { $0.isHexDigit }
    }

    private static func entry(from dict: [String: Any]) -> ColorSetEntry? {
        guard let name = dict["name"] as? String,
              let colors = dict["colors"] as? [String], colors.count == 4,
              colors.allSatisfy(validColor) else { return nil }
        var slot: Int?
        if let raw = dict["slot"], !(raw is NSNull) {
            guard let s = raw as? Int, (0...9).contains(s) else { return nil }
            slot = s
        }
        return ColorSetEntry(slot: slot, name: name, colors: colors.map { $0.uppercased() })
    }

    /// The whole pool: sets in file order (slot nil = pool-only) and the
    /// dropped names. Malformed entries skipped; a missing file is empty.
    public func loadColorSetFile() -> ColorSetFile {
        var file = ColorSetFile(sets: [], dropped: [])
        guard let data = try? Data(contentsOf: colorSetsFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return file }
        for case let dict as [String: Any] in (root["sets"] as? [Any]) ?? [] {
            if let e = Store.entry(from: dict) { file.sets.append(e) }
        }
        file.dropped = (root["dropped"] as? [String]) ?? []
        return file
    }

    // JSON writing in the layout of Python's json.dumps(indent=1), so a
    // save from either implementation leaves shared files byte-stable.
    static func quoted(_ s: String) -> String {
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

    static func list(_ items: [String], indent: String) -> String {
        items.isEmpty ? "[]"
            : "[\n" + items.map { indent + " " + $0 }.joined(separator: ",\n") + "\n" + indent + "]"
    }

    private func write(_ text: String, to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    public func saveColorSetFile(_ file: ColorSetFile) {
        let quoted = Store.quoted
        let sets = file.sets.map { e -> String in
            var lines: [String] = []
            if let slot = e.slot { lines.append("   \"slot\": \(slot)") }
            lines.append("   \"name\": \(quoted(e.name))")
            lines.append("   \"colors\": " + Store.list(e.colors.map(quoted), indent: "   "))
            return "{\n" + lines.joined(separator: ",\n") + "\n  }"
        }
        let text = "{\n \"sets\": " + Store.list(sets, indent: " ")
            + ",\n \"dropped\": " + Store.list(file.dropped.map(quoted), indent: " ") + "\n}\n"
        write(text, to: colorSetsFile)
    }

    // R-P5: screensaver file — an ordered list of rule / color set pairs.
    public static func loadScreensaver(_ url: URL) -> [ScreensaverPair]? {
        guard let data = try? Data(contentsOf: url) else { return nil }  // missing
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        var pairs: [ScreensaverPair] = []
        for case let dict as [String: Any] in (root["pairs"] as? [Any]) ?? [] {
            guard let rule = dict["rule"] as? String, (try? Rule(id: rule)) != nil,
                  let name = dict["colorset"] as? String,
                  let colors = dict["colors"] as? [String], colors.count == 4,
                  colors.allSatisfy(validColor) else { continue }
            pairs.append(ScreensaverPair(rule: rule, colorset: name, colors: colors.map { $0.uppercased() }))
        }
        return pairs
    }

    public static func saveScreensaver(_ pairs: [ScreensaverPair], to url: URL) {
        let entries = pairs.map { p -> String in
            "{\n   \"rule\": \(quoted(p.rule)),\n   \"colorset\": \(quoted(p.colorset)),\n"
            + "   \"colors\": " + list(p.colors.map(quoted), indent: "   ") + "\n  }"
        }
        let text = "{\n \"pairs\": " + list(entries, indent: " ") + "\n}\n"
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// {slot: ColorSet} for the digit-bound sets; slot 1 always present (R-U4).
    public func loadColorSets() -> [Int: ColorSet] {
        var sets = Store.defaultColorSets
        for e in loadColorSetFile().sets {
            if let slot = e.slot { sets[slot] = ColorSet(name: e.name, colors: e.colors) }
        }
        return sets
    }

    /// Replace the digit-bound sets, preserving the pool and the dropped list.
    public func saveColorSets(_ sets: [Int: ColorSet]) {
        let file = loadColorSetFile()
        let slotted = sets.keys.sorted().map {
            ColorSetEntry(slot: $0, name: sets[$0]!.name, colors: sets[$0]!.colors)
        }
        let pool = file.sets.filter { $0.slot == nil }
        saveColorSetFile(ColorSetFile(sets: slotted + pool, dropped: file.dropped))
    }

    /// Palettes from colorsets/candidates.json, the raw pool source (R-V2).
    public func loadCandidatePalettes() -> [ColorSetEntry] {
        guard let data = try? Data(contentsOf: candidatePalettesFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        var out: [ColorSetEntry] = []
        for case let dict as [String: Any] in (root["palettes"] as? [Any]) ?? [] {
            if var e = Store.entry(from: dict) { e.slot = nil; out.append(e) }
        }
        return out
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

/// One entry of the color sets file: slot nil means pool-only (R-P4).
public struct ColorSetEntry: Equatable {
    public var slot: Int?
    public var name: String
    public var colors: [String]

    public init(slot: Int?, name: String, colors: [String]) {
        self.slot = slot
        self.name = name
        self.colors = colors
    }
}

/// The color sets file as a whole (R-P4).
public struct ColorSetFile: Equatable {
    public var sets: [ColorSetEntry]
    public var dropped: [String]

    public init(sets: [ColorSetEntry], dropped: [String]) {
        self.sets = sets
        self.dropped = dropped
    }
}

/// One screensaver entry: a rule with a color set, colors already arranged (R-P5).
public struct ScreensaverPair: Equatable {
    public var rule: String
    public var colorset: String
    public var colors: [String]

    public init(rule: String, colorset: String, colors: [String]) {
        self.rule = rule
        self.colorset = colorset
        self.colors = colors
    }
}
