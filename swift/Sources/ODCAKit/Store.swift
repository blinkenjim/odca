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

    /// R-P6: why an odca file cannot be used, or nil when it can be.
    ///
    /// Loading skips whatever it does not understand, which is right for an
    /// entry a later version added, but a file that will not parse at all
    /// contributes *nothing*, and silently, there being no entry left to
    /// skip. When that file is also where the results go, the next save
    /// writes over it and everything it held is gone. So every program asks
    /// this of its files before it starts and refuses to run on a bad one.
    ///
    /// A file that does not exist is not this test's business: `odca-select`
    /// makes its file on the first save (R-W1), and the programs that do
    /// require a file to exist already say so themselves.
    public static func rejection(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }  // missing
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return "\(url.relativePath): not valid JSON"
        }
        if let line = trailingComma(in: data) {
            return "\(url.relativePath):\(line): a comma with nothing after it"
        }
        guard let root = json as? [String: Any] else {
            return "\(url.relativePath): not an odca file (the top level is not an object)"
        }
        if let pairs = root["pairs"] ?? root["looks"], !(pairs is [Any]) {
            return "\(url.relativePath): \"pairs\" is not a list"
        }
        if let seeds = root["seeds"], !(seeds is [String: Any]) {
            return "\(url.relativePath): \"seeds\" is not an object"
        }
        return nil
    }

    /// R-P6: the line holding a comma that closes nothing — `[1,]` or
    /// `{"a": 1,}` — or nil when there is none.
    ///
    /// JSON forbids these, but Foundation's JSONSerialization accepts them
    /// and Python's `json`, which the other implementation reads these files
    /// with, does not. An odca file is one format, so the stricter reading
    /// wins: a file only one implementation can open is a broken file, and
    /// this is exactly what a hand edit that deletes a block leaves behind.
    static func trailingComma(in data: Data) -> Int? {
        var inString = false, escaped = false, line = 1
        let bytes = [UInt8](data)
        for (i, byte) in bytes.enumerated() {
            if byte == 0x0A { line += 1 }
            if inString {
                if escaped { escaped = false }
                else if byte == 0x5C { escaped = true }       // backslash
                else if byte == 0x22 { inString = false }     // closing quote
            } else if byte == 0x22 {
                inString = true
            } else if byte == 0x2C {                          // comma
                var j = i + 1
                while j < bytes.count, bytes[j] == 0x20 || bytes[j] == 0x09
                        || bytes[j] == 0x0A || bytes[j] == 0x0D { j += 1 }
                if j < bytes.count, bytes[j] == 0x7D || bytes[j] == 0x5D { return line }
            }
        }
        return nil
    }

    // R-P3: an odca file — an ordered list of pairs (rule + color set), each
    // named when the file names it, and the seeds odca-evolve has recorded
    // (section 4e) by rule and width. The 3.0.0 key `looks` is still read.
    /// nil when the file is missing, [] when unparseable; malformed pairs
    /// skipped. Callers check Store.rejection first (R-P6), so in practice
    /// the unparseable case is refused before it reaches here.
    public static func loadOdcaFile(_ url: URL) -> [Pair]? {
        guard let data = try? Data(contentsOf: url) else { return nil }  // missing
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        var pairs: [Pair] = []
        for case let dict as [String: Any] in (root["pairs"] ?? root["looks"]) as? [Any] ?? [] {
            // R-P3, R-M12: `experiment` names the rule class, absent meaning
            // the ODCA. A class this version does not know is skipped like
            // any other entry it cannot use, rather than read as an ODCA
            // rule it is not.
            guard let experiment = Experiment.named(dict["experiment"] as? String) else { continue }
            guard let rule = dict["rule"] as? String,
                  (try? Rule(id: rule, experiment: experiment)) != nil,
                  let set = dict["colorset"] as? String,
                  let colors = dict["colors"] as? [String], colors.count == 4,
                  colors.allSatisfy(validColor) else { continue }
            pairs.append(Pair(name: dict["name"] as? String, rule: rule, experiment: experiment,
                              colorset: set, colors: colors.map { $0.uppercased() }))
        }
        return pairs
    }

    /// The union of several odca files' pairs (R-E1), in the order first
    /// seen. Nothing is lost: every distinct pair in any file appears.
    ///
    /// A pair *is* its content — rule, colour set and colours — so the same
    /// pair in two files unites into one, keeping the name from the file
    /// given earlier. The files' order arbitrates nothing else, because
    /// nothing else needs it: two pairs that differ are two pairs, and both
    /// belong in the union even when they wear the same name.
    ///
    /// Sharing a name is not a conflict in the data, only in the label, and
    /// it is the common case rather than the exception: names are generated
    /// per file from `pair-0000` up, so files grown apart collide by
    /// construction. The earlier file keeps the contested name and the later
    /// pair takes the next free one, numbered past every generated name in
    /// every file so that renaming one pair can never take a name another
    /// file is already using.
    public static func loadOdcaFiles(_ urls: [URL]) -> [Pair] {
        let perFile = urls.map { loadOdcaFile($0) ?? [] }
        var nextNumber = (perFile.flatMap { $0 }.compactMap(generatedPairNumber).max() ?? -1) + 1

        var pairs: [Pair] = []
        var seen = Set<[String]>()   // the contents already in the union
        var names = Set<String>()
        for file in perFile {
            for pair in file {
                guard seen.insert([pair.rule, pair.experiment.fileName ?? "", pair.colorset] + pair.colors).inserted else { continue }
                var name = pair.name
                if let taken = name, names.contains(taken) {
                    name = String(format: "pair-%04d", nextNumber)
                    nextNumber += 1
                }
                if let name = name { names.insert(name) }
                pairs.append(Pair(name: name, rule: pair.rule, experiment: pair.experiment,
                              colorset: pair.colorset, colors: pair.colors))
            }
        }
        return pairs
    }

    /// The number in a generated `pair-NNNN` name, or nil for any other name.
    static func generatedPairNumber(_ pair: Pair) -> Int? {
        guard let name = pair.name, name.hasPrefix("pair-") else { return nil }
        let digits = name.dropFirst(5)
        return digits.allSatisfy(\.isNumber) && !digits.isEmpty ? Int(digits) : nil
    }

    /// The union of several odca files' seeds (R-E1), merged rule by rule and
    /// width by width. Unlike pairs this does not go by the files' order:
    /// seeds are not competing values but findings, so all of them are
    /// pooled and the ten longest-lived kept (R-E3), whichever files they
    /// came from. Nothing an earlier search found is ever discarded because
    /// a file was named later.
    public static func loadSeeds(_ urls: [URL]) -> Seeds {
        urls.reduce(Seeds()) { Evolve.merge($0, loadSeeds($1)) }
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
            // R-P3, R-M12: a seed key is a bare rule ID for the ODCA and
            // `<class>:<id>` for anything else, because 20 digits mean two
            // different automata once fredkin exists.
            guard let (experiment, ruleID) = Experiment.splitSeedKey(id),
                  (try? Rule(id: ruleID, experiment: experiment)) != nil,
                  let byWidth = byWidth as? [String: Any] else { continue }
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
                    + [("rule", .string(p.rule))]
                    // R-M12: the ODCA writes no key, so a file of ordinary
                    // pairs is byte for byte what it was before R-M12.
                    + (p.experiment.fileName.map { [("experiment", JSON.string($0))] } ?? [])
                    + [("colorset", .string(p.colorset)),
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
        String(format: "pair-%04d", (pairs.compactMap(generatedPairNumber).max() ?? -1) + 1)
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

    /// The `end` of a row that outlived the cap (R-E2); such seeds are not
    /// played under `--longest` (R-X8).
    public static let survived = "survived"

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
    /// R-P3, R-M12: which rule class `rule` belongs to. The ODCA writes no
    /// key, so a file from before R-M12 reads as exactly what it meant. It
    /// is part of what a pair *is*: two pairs with the same 20 digits under
    /// different classes are two different automata, not one.
    public var experiment: Experiment
    public var colorset: String
    public var colors: [String]

    public init(name: String? = nil, rule: String, experiment: Experiment = .none,
                colorset: String, colors: [String]) {
        self.name = name
        self.rule = rule
        self.experiment = experiment
        self.colorset = colorset
        self.colors = colors
    }

    /// The key this pair's seeds are recorded under (R-P3).
    public var seedKey: String { experiment.seedKey(rule) }
}
