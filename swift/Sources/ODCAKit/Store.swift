import Foundation

/// Persistence (R-P): per-user state in ~/.odca/, the library at the
/// repository root, and odca files named on the command line. Loaders treat
/// missing or malformed files as absent.
public struct Store {
    /// Repository root, anchored from this source file's location:
    /// swift/Sources/ODCAKit/Store.swift -> up four levels (R-P4).
    public static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // ODCAKit
        .deletingLastPathComponent()  // Sources
        .deletingLastPathComponent()  // swift
        .deletingLastPathComponent()  // repository root

    public let stateDir: URL
    public let libraryFile: URL
    public let candidatePalettesFile: URL

    /// Built-in fallback so the default slot always exists (R-U4).
    public static let defaultColorSets: [Int: ColorSet] = [
        1: ColorSet(name: "ODCA default", colors: ["#121218", "#EBEBE1", "#FFA136", "#409CFF"])
    ]

    public init(
        stateDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".odca"),
        libraryFile: URL = Store.repoRoot.appendingPathComponent("library.json"),
        candidatePalettesFile: URL = Store.repoRoot.appendingPathComponent("colorsets/candidates.json")
    ) {
        self.stateDir = stateDir
        self.libraryFile = libraryFile
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

    // R-P4: the library, shared by all implementations.
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
        guard let data = try? Data(contentsOf: libraryFile),
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

    private static func write(_ text: String, to url: URL) {
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
        Store.write(text, to: libraryFile)
    }

    // A JSON value tree rendered exactly as Python's json.dumps(indent=1)
    // renders it, so both implementations write shared files byte for byte.
    indirect enum JSON {
        case string(String), int(Int), array([JSON]), object([(String, JSON)])
    }

    static func render(_ value: JSON, indent: Int = 0) -> String {
        let pad = String(repeating: " ", count: indent)
        let inner = pad + " "
        switch value {
        case .string(let s): return quoted(s)
        case .int(let n): return String(n)
        case .array(let items):
            if items.isEmpty { return "[]" }
            return "[\n" + items.map { inner + render($0, indent: indent + 1) }.joined(separator: ",\n") + "\n" + pad + "]"
        case .object(let members):
            if members.isEmpty { return "{}" }
            return "{\n" + members.map { inner + quoted($0.0) + ": " + render($0.1, indent: indent + 1) }
                .joined(separator: ",\n") + "\n" + pad + "}"
        }
    }

    // R-P3: an odca file — an ordered list of pairs (rule + color set), each
    // named when the file names it, and the seeds odca-evolve has recorded
    // (section 4e) by rule and width. The 3.0.0 key `looks` is still read.
    /// nil when the file is missing, [] when unparseable; malformed pairs skipped.
    public static func loadOdcaFile(_ url: URL) -> [Pair]? {
        guard let data = try? Data(contentsOf: url) else { return nil }  // missing
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        var pairs: [Pair] = []
        for case let dict as [String: Any] in (root["pairs"] ?? root["looks"]) as? [Any] ?? [] {
            guard let rule = dict["rule"] as? String, (try? Rule(id: rule)) != nil,
                  let set = dict["colorset"] as? String,
                  let colors = dict["colors"] as? [String], colors.count == 4,
                  colors.allSatisfy(validColor) else { continue }
            pairs.append(Pair(name: dict["name"] as? String, rule: rule, colorset: set,
                              colors: colors.map { $0.uppercased() }))
        }
        return pairs
    }

    /// The file's seeds (R-P3, section 4e): rule ID -> width -> seeds, longest
    /// first. Empty when the file is missing, unparseable, or has none;
    /// malformed entries are skipped.
    public static func loadSeeds(_ url: URL) -> Seeds {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let section = root["seeds"] as? [String: Any] else { return [:] }
        var seeds: Seeds = [:]
        for (id, byWidth) in section {
            guard (try? Rule(id: id)) != nil, let byWidth = byWidth as? [String: Any] else { continue }
            for (key, entries) in byWidth {
                guard let width = Int(key), width >= Session.minCols, let entries = entries as? [Any] else { continue }
                var list: [Seed] = []
                for case let dict as [String: Any] in entries {
                    guard let text = dict["row"] as? String, text.count == width,
                          let generations = dict["generations"] as? Int, generations >= 0,
                          let end = dict["end"] as? String else { continue }
                    let row = text.compactMap { $0.wholeNumberValue }.filter { $0 < Rule.stateCount }.map(UInt8.init)
                    guard row.count == width else { continue }
                    list.append(Seed(row: row, generations: generations, end: end))
                }
                if !list.isEmpty { seeds[id, default: [:]][width] = Evolve.merge(list) }
            }
        }
        return seeds
    }

    /// Write pairs and seeds (R-P3). Layout: each pair as name (when it has
    /// one), rule, colorset, colors; then, when there are any, `seeds` by
    /// rule ID (sorted) and width (ascending, as a string), each seed as
    /// row, generations, end.
    public static func saveOdcaFile(_ pairs: [Pair], seeds: Seeds, to url: URL) {
        let entries = pairs.map { p -> JSON in
            .object((p.name.map { [("name", JSON.string($0))] } ?? [])
                    + [("rule", .string(p.rule)), ("colorset", .string(p.colorset)),
                       ("colors", .array(p.colors.map(JSON.string)))])
        }
        var root: [(String, JSON)] = [("pairs", .array(entries))]
        let rules = seeds.filter { !$0.value.values.allSatisfy(\.isEmpty) }.keys.sorted()
        if !rules.isEmpty {
            root.append(("seeds", .object(rules.map { id in
                (id, .object(seeds[id]!.filter { !$0.value.isEmpty }.keys.sorted().map { width in
                    (String(width), .array(Evolve.merge(seeds[id]![width]!).map { seed in
                        .object([("row", .string(seed.rowText)), ("generations", .int(seed.generations)),
                                 ("end", .string(seed.end))])
                    }))
                }))
            })))
        }
        write(render(.object(root)) + "\n", to: url)
    }

    /// Write pairs, carrying the file's existing seeds through unchanged
    /// (odca-select never touches them, R-P3).
    public static func saveOdcaFile(_ pairs: [Pair], to url: URL) {
        saveOdcaFile(pairs, seeds: loadSeeds(url), to: url)
    }

    /// The next generated name, `pair-NNNN` (R-P3): one past the highest number
    /// in use in the file, four digits, more once they are needed.
    public static func nextPairName(_ pairs: [Pair]) -> String {
        let used = pairs.compactMap { p -> Int? in
            guard let name = p.name, name.hasPrefix("pair-") else { return nil }
            let digits = name.dropFirst(5)
            return digits.allSatisfy(\.isNumber) && !digits.isEmpty ? Int(digits) : nil
        }
        return String(format: "pair-%04d", (used.max() ?? -1) + 1)
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

/// One entry of the library: slot nil means pool-only (R-P4).
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

/// The library as a whole (R-P4).
public struct ColorSetFile: Equatable {
    public var sets: [ColorSetEntry]
    public var dropped: [String]

    public init(sets: [ColorSetEntry], dropped: [String]) {
        self.sets = sets
        self.dropped = dropped
    }
}

/// A recorded seed (R-P3, section 4e): a row for one rule at one width, the
/// generations it lived before the extinction that makes odca re-seed, and
/// how it ended — the extinction text, or `survived` for the cap.
public struct Seed: Equatable {
    public var row: [UInt8]
    public var generations: Int
    public var end: String

    public init(row: [UInt8], generations: Int, end: String) {
        self.row = row
        self.generations = generations
        self.end = end
    }

    /// The row as the file writes it: one digit per cell.
    public var rowText: String { row.map(String.init).joined() }
}

/// Seeds by rule ID, then by width (R-P3), each list longest first.
public typealias Seeds = [String: [Int: [Seed]]]

/// One pair: a rule with a color set, colors already arranged, and its name
/// when the file gives one (R-P3).
public struct Pair: Equatable {
    public var name: String?
    public var rule: String
    public var colorset: String
    public var colors: [String]

    public init(name: String? = nil, rule: String, colorset: String, colors: [String]) {
        self.name = name
        self.rule = rule
        self.colorset = colorset
        self.colors = colors
    }
}
