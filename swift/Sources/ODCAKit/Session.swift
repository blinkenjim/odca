import Foundation

/// An RGB color, states' display colors after arrangement (R-U4).
public struct RGB: Equatable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Parse "#RRGGBB" (validated on load, so a bad string yields black).
    public init(hex: String) {
        let s = Array(hex.dropFirst())
        func byte(_ i: Int) -> UInt8 { UInt8(String(s[i..<i + 2]), radix: 16) ?? 0 }
        self.init(r: byte(0), g: byte(2), b: byte(4))
    }
}

/// The toolkit-free orchestration layer: everything the two programs do
/// except rendering pixels and reading raw key events. The UI layer
/// translates toolkit key events into `Session.Key`, calls `tick(_:)` at
/// its refresh rate, and draws `history` through `paletteTable` and `rowPalettes`
/// (inverted while `inverted`). Programs: odca-select (`selectFile`, section
/// 4c), odca (`playFile`, section 4d); color set review (`reviewMode`,
/// section 4b) is on hold and bound by no program.
/// See REQTS sections R-U, R-K, R-B, R-A, R-P, R-O.
public final class Session {
    public static let defaultColorSet = 1  // slot active at startup (R-U4)
    public static let initialDelay = 1.0 / 60.0  // R-U5
    public static let minDelay = 1.0 / 16384.0  // R-K8
    public static let maxDelay = 8.0
    public static let maxCandidates = 64  // R-S3
    public static let stepCap = 2000  // per-tick catch-up cap (R-U5)
    public static let smoothScrollDelay = 2 * Session.initialDelay  // slower: continuous scrolling (R-U3)
    public static let screenSpeedup = 8.0  // paused 's' zips at delay / 8 (R-K13)
    public static let repeatScreens = 10  // repetition window in screens (R-A1)
    public static let minorityFraction = 0.10  // a producible state below this share is a minority (R-A1)
    public static let stagnationScreens = 4  // minority population steady this long -> stagnant (R-A1)
    public static let stagnationSwing = 0.25  // (max - min) / mean below this counts as steady
    public static let playTimeout = 120.0  // odca: a look's screen time before it may advance (R-X3)
    public static let playGrace = 60.0  // odca: no transition within this long of an initialization (R-X3)
    public static let shuffleTries = 100  // odca --shuffle: draws tried for an order without repeats (R-X1)
    public static let flashSeconds = 0.25  // the screen inverts this long as a mode cue (R-U10)
    public static let historyDepth = 2048  // rows remembered beyond the screen (R-U8)
    public static let paletteLimit = 64  // odca: prune the per-row palette table past this (R-X5)
    public static let minCols = 3  // R-M2

    /// Digit keys in review order (R-V): the first ten kept sets own these.
    public static let keyOrder = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]

    /// The 24 assignments of four colors to four states, lexicographic,
    /// identity first (R-K15).
    public static let arrangements: [[Int]] = permutations([0, 1, 2, 3])

    private static func permutations(_ items: [Int]) -> [[Int]] {
        if items.count <= 1 { return [items] }
        var out: [[Int]] = []
        for (i, x) in items.enumerated() {
            var rest = items
            rest.remove(at: i)
            for p in permutations(rest) { out.append([x] + p) }
        }
        return out
    }

    public enum Key: Equatable {
        case q, r, m, u, s, i, n, p, a
        case U  // undo every change since the cycle position last moved (R-K19)
        case c, C, S  // arrange colors forward / backward; S appends a look (R-W4)
        case N, P, X  // odca: next / previous look; odca-select: X deletes; review: next / previous / drop
        case R  // odca-select: toggle the n/p order, file order or grouped by rule (R-W7)
        case poolPrev, poolNext  // '[' / ']': step through the color set pool (R-K17)
        case plus, minus, space, ret
        case digit(Int)
    }

    public private(set) var cols: Int
    public private(set) var rows: Int
    public private(set) var automaton: Automaton
    /// Remembered generations, oldest first, up to `historyDepth` (never
    /// fewer than `rows + 1`). The display shows the last `rows + 1`: one
    /// more than the window, so continuous scrolling has a row to slide in;
    /// a taller window uncovers older rows (R-U8).
    public private(set) var history: [[UInt8]] = []
    /// Index into `paletteTable` of the palette each history row was painted with (R-X5).
    public private(set) var rowPalettes: [UInt16] = []
    /// odca (R-X5): the color sets rows were painted with; other modes use one entry, index 0.
    private var palettes: [[RGB]] = []
    private var paletteIndex = 0
    /// R-U5: the starting delay, 1/60 s at the default cell size and halved
    /// per halving of the cell, so the picture moves at the same speed in
    /// points; the continuous-scrolling threshold is twice it (R-U3).
    public let initialDelay: Double
    /// odca's clocks (R-X2, R-X3): whole seconds from --watchdog / --grace, or the defaults.
    public let playTimeout: Double
    public let playGrace: Double
    public var smoothScrollDelay: Double { 2 * initialDelay }
    public private(set) var delay: Double
    public private(set) var paused = false
    public private(set) var screenRemaining = 0  // generations still to zip (R-K13)
    public private(set) var screenCounter: Int?  // screenfuls since last resume (R-K14)
    public private(set) var autoInit = true  // R-K12: on at startup, not persisted
    public private(set) var cyclePeriod: Int?  // exact period once Brent's finds a cycle
    public private(set) var flashRemaining = 0.0  // seconds of screen inversion left (R-U10)
    public private(set) var colorSets: [Int: ColorSet]
    public private(set) var colorSet = Session.defaultColorSet
    // Color set review mode (R-V): kept sets in review order, position, drops.
    public let reviewMode: Bool
    public private(set) var reviewEntries: [ColorSetEntry] = []
    public private(set) var reviewIndex = 0
    public private(set) var droppedNames: [String] = []
    private var reviewArrangement: [String: Int] = [:]
    // The look cycle (R-B): the file's looks in view order plus the unsaved slot.
    public let selectFile: URL?  // odca-select (R-W)
    public private(set) var looks: [Look] = []  // always in file order
    public private(set) var lookIndex: Int?  // file index of the look under review / playing
    public private(set) var viewOrder: [Int] = []  // file indices in n/p order
    public private(set) var viewPosition: Int?  // position of lookIndex within viewOrder
    public private(set) var grouped = false  // R: n/p order grouped by rule (R-W7)
    public private(set) var unsavedRule: Rule?
    public private(set) var unsavedSet: ColorSetEntry?  // the set shown with the unsaved rule (R-B3)
    // odca (R-X): play the looks of a file in order, or shuffled per pass.
    public let playFile: URL?
    public let shuffle: Bool
    public private(set) var playOrder: [Int] = []  // file indices in the order of the current pass
    public private(set) var playPosition: Int?
    public private(set) var playElapsed = 0.0  // unpaused seconds on the current look
    public private(set) var sinceInit = 0.0  // unpaused seconds since the last (re)initialization
    public private(set) var activeSet: ColorSetEntry?  // the set in use (any pool member)
    /// Arrangement index of the active set, remembered per set name (R-K15).
    private var activeArrangement: Int {
        get { arrangementByName[activeName] ?? 0 }
        set { arrangementByName[activeName] = newValue }
    }
    private var activeName: String { activeSet?.name ?? colorSets[colorSet]!.name }
    private var pool: [ColorSetEntry] = []  // whole pool in review order for [ / ]
    public private(set) var undoStack: [Rule] = []
    private var undoMark = 0  // stack depth when the cycle position last moved; U unwinds to it (R-K19)
    public private(set) var candidates: [Rule]
    /// Terminal output sink (R-O); the UI leaves it as print, tests capture it.
    public var output: (String) -> Void = { print($0) }

    let store: Store
    let search: CandidateSearch
    var rng: Xoshiro256
    private var accumulated = 0.0
    private var zipAccumulated = 0.0
    private var counted = 0  // generations since the screen counter started
    private var arrangementByName: [String: Int] = [:]  // set name -> index into arrangements

    // Auto-init state (R-A); internal so tests can observe it.
    var boringStreak = 0
    var boringReason: String?
    private var recentRows: [[UInt8]] = []
    private var recentCounts: [[UInt8]: Int] = [:]
    private var minorityCounts: [Int] = []
    private var brentSnapshot: [UInt8]?
    private var brentPower = 1
    private var brentSteps = 0

    public init(
        cols: Int, rows: Int, store: Store = Store(),
        search: CandidateSearch = CandidateSearch(), rng: Xoshiro256 = Xoshiro256(),
        reviewMode: Bool = false, selectFile: URL? = nil, playFile: URL? = nil, shuffle: Bool = false,
        initialDelay: Double = Session.initialDelay,
        playTimeout: Double = Session.playTimeout, playGrace: Double = Session.playGrace,
        output: @escaping (String) -> Void = { print($0) }
    ) {
        self.cols = cols
        self.rows = rows
        self.playTimeout = playTimeout
        self.playGrace = playGrace
        self.initialDelay = initialDelay
        self.delay = initialDelay
        self.store = store
        self.search = search
        // Program precedence: odca (play), then odca-select, then color set review.
        self.playFile = playFile
        self.shuffle = shuffle && playFile != nil
        let selectFile = playFile == nil ? selectFile : nil
        self.reviewMode = reviewMode && selectFile == nil && playFile == nil
        self.selectFile = selectFile
        self.output = output
        var rng = rng

        // Startup per R-U1: previous rule (random fallback), random cells.
        let rule = store.loadRule() ?? Rule.random(using: &rng)
        automaton = try! Automaton(
            width: cols, rule: rule,
            cells: Automaton.randomCells(width: cols, using: &rng))
        store.saveRule(rule)
        unsavedRule = rule  // the startup rule fills the unsaved slot (R-B3) unless a file opens on look 1

        candidates = store.loadCandidates()
        colorSets = store.loadColorSets()  // R-P4
        self.rng = rng
        // Every mode but color set review draws through the active set, which
        // may be any pool member (R-K17); it starts as the default slot.
        pool = poolOrder()
        let d = colorSets[colorSet]!
        activeSet = ColorSetEntry(slot: colorSet, name: d.name, colors: d.colors)
        unsavedSet = activeSet
        pushRow(automaton.cells)
        output("rule \(rule.id)")
        if reviewMode { loadReview() }
        if let url = selectFile { loadSelect(url) }
        if let url = playFile { loadPlay(url) }
    }

    public var selectMode: Bool { selectFile != nil }
    public var playMode: Bool { playFile != nil }
    /// The display shows inverted colors while a flash runs (R-U10).
    public var inverted: Bool { flashRemaining > 0 }

    public var ruleID: String { automaton.rule.id }

    public func startSearch() { search.start() }
    public func stopSearch() { search.stop() }

    private func pushRow(_ row: [UInt8]) {
        if playMode {
            // R-X5: a row keeps the colors it was painted with. A changed
            // active set becomes a new table entry for the rows from now on.
            let current = palette
            if palettes.isEmpty {
                palettes = [current]
            } else if current != palettes[paletteIndex] {
                if let shared = palettes.firstIndex(of: current) {  // a set seen before: share its entry
                    paletteIndex = shared
                } else {
                    if palettes.count >= Session.paletteLimit { prunePalettes() }
                    palettes.append(current)
                    paletteIndex = palettes.count - 1
                }
            }
        }
        history.append(row)
        rowPalettes.append(UInt16(paletteIndex))
        trimHistory()
    }

    /// Drop table entries no remembered row uses any more, renumbering the rest.
    private func prunePalettes() {
        let keep = Set(rowPalettes.map { Int($0) }).union([paletteIndex]).sorted()
        var remap = [Int: Int]()
        for (new, old) in keep.enumerated() { remap[old] = new }
        rowPalettes = rowPalettes.map { UInt16(remap[Int($0)]!) }
        palettes = keep.map { palettes[$0] }
        paletteIndex = remap[paletteIndex]!
    }

    private func trimHistory() {
        let keep = max(Session.historyDepth, rows + 1)
        if history.count > keep {
            history.removeFirst(history.count - keep)
            rowPalettes.removeFirst(rowPalettes.count - keep)
        }
    }

    /// Index of the first history row the display shows (R-U3, R-U8).
    public var visibleStart: Int { max(0, history.count - (rows + 1)) }

    /// Change the geometry (R-U8): the state vector keeps its center — cropped
    /// from both edges when narrower, padded at both edges when wider, the
    /// new cells seeded at random (older rows padded with state 0) — and the
    /// boring detectors start afresh. Returns whether anything changed.
    @discardableResult
    public func resize(cols newCols: Int, rows newRows: Int) -> Bool {
        let newCols = max(Session.minCols, newCols)
        let newRows = max(1, newRows)
        guard newCols != cols || newRows != rows else { return false }
        if newCols != cols {
            func fit(_ row: [UInt8], padding: (Int) -> [UInt8]) -> [UInt8] {
                if newCols < row.count {
                    let left = (row.count - newCols) / 2
                    return Array(row[left..<(left + newCols)])
                }
                let add = newCols - row.count
                return padding(add / 2) + row + padding(add - add / 2)
            }
            history = history.map { fit($0) { [UInt8](repeating: 0, count: $0) } }
            var rng = self.rng
            let cells = fit(automaton.cells) { Automaton.randomCells(width: $0, using: &rng) }
            self.rng = rng
            automaton = try! Automaton(width: newCols, rule: automaton.rule, cells: cells)
            if !history.isEmpty { history[history.count - 1] = cells }
        }
        cols = newCols
        rows = newRows
        trimHistory()
        resetBoredom()
        output("resized \(cols)x\(rows)")  // R-O14
        return true
    }

    /// RGB for every (palette, state) as one array, entry palette * 4 + state
    /// (R-X5). Outside odca there is one palette, the active set, so the
    /// whole screen recolors at once.
    public var paletteTable: [RGB] {
        if playMode && !palettes.isEmpty { return palettes.flatMap { $0 } }
        return palette
    }

    /// Display color of a history cell: its state through its row's palette.
    public func color(row: Int, col: Int) -> RGB {
        paletteTable[Int(rowPalettes[row]) * 4 + Int(history[row][col])]
    }

    /// How far the display is scrolled into the top history row, in cells
    /// (R-U3): 0 while the buffer is filling; 1 (newest row fully shown) when
    /// paused or at fast speeds; else the elapsed fraction of the current
    /// delay, so the picture slides up one cell per delay.
    public var scrollOffset: Double {
        if history.count <= rows { return 0 }
        if paused || delay <= smoothScrollDelay { return 1 }
        return min(accumulated / delay, 1)
    }

    // MARK: - Colors (R-U4, R-K15, R-K16)

    /// The set under review, or nil when the review pool is empty.
    private var reviewEntry: ColorSetEntry? {
        reviewEntries.isEmpty ? nil : reviewEntries[reviewIndex]
    }

    private func arrangedReviewColors() -> [String] {
        guard let e = reviewEntry else { return Store.defaultColorSets[1]!.colors }
        return Session.arrangements[reviewArrangement[e.name] ?? 0].map { e.colors[$0] }
    }

    private func arrangedActiveColors() -> [String] {
        let base = activeSet?.colors ?? colorSets[colorSet]!.colors
        return Session.arrangements[activeArrangement].map { base[$0] }
    }

    /// The active color set as four RGB colors, states 0-3, after arrangement.
    public var palette: [RGB] {
        (reviewMode ? arrangedReviewColors() : arrangedActiveColors()).map { RGB(hex: $0) }
    }

    private func cycleColors(_ step: Int) {
        let n = Session.arrangements.count
        if reviewMode {
            guard let e = reviewEntry else { return }
            let index = (((reviewArrangement[e.name] ?? 0) + step) % n + n) % n
            reviewArrangement[e.name] = index
            output("color set \(e.name) arrangement \(index + 1)/\(n)")  // R-O9
            return
        }
        activeArrangement = ((activeArrangement + step) % n + n) % n
        output("color set \(activeName) arrangement \(activeArrangement + 1)/\(n)")  // R-O9
    }

    /// R-U10: invert the screen briefly as a cue.
    private func flash() { flashRemaining = Session.flashSeconds }

    // MARK: - Color set review (R-V)

    private static func keyRank(_ slot: Int) -> Int { keyOrder.firstIndex(of: slot) ?? 10 }

    /// Build the review order: digit-bound sets in key order (1-9, 0), then
    /// the pool, then every candidate palette not already present or dropped.
    private func loadReview() {  // R-V2
        let file = store.loadColorSetFile()
        var slotted = file.sets.filter { $0.slot != nil }
        if !slotted.contains(where: { $0.slot == 1 }) {
            let d = Store.defaultColorSets[1]!
            slotted.append(ColorSetEntry(slot: 1, name: d.name, colors: d.colors))
        }
        slotted.sort { Session.keyRank($0.slot!) < Session.keyRank($1.slot!) }
        var entries = slotted + file.sets.filter { $0.slot == nil }
        droppedNames = file.dropped
        var names = Set(entries.map(\.name))
        let dropped = Set(file.dropped)
        for p in store.loadCandidatePalettes() where !names.contains(p.name) && !dropped.contains(p.name) {
            entries.append(p)
            names.insert(p.name)
        }
        reviewEntries = entries
        reviewIndex = 0
        announceReview()
    }

    private func announceReview() {  // R-O11
        guard let e = reviewEntry else {
            output("review empty")
            return
        }
        output("review \(reviewIndex + 1)/\(reviewEntries.count) \(e.name)")
    }

    private func reviewStep(_ step: Int) {  // R-V3
        guard !reviewEntries.isEmpty else { return }
        var index = reviewIndex + step
        if index >= reviewEntries.count {
            index = 0
            output("review wrapped")
        } else if index < 0 {
            index = reviewEntries.count - 1
            output("review wrapped")
        }
        reviewIndex = index
        announceReview()
        fillScreen()  // R-V7
    }

    private func dropReview() {  // R-V4
        guard let e = reviewEntry else { return }
        reviewEntries.remove(at: reviewIndex)
        droppedNames.append(e.name)
        reviewArrangement[e.name] = nil
        output("dropped \(e.name)")
        if reviewIndex >= reviewEntries.count && !reviewEntries.isEmpty {
            reviewIndex = 0
            output("review wrapped")
        }
        announceReview()
        saveReview()  // R-V5: every drop is saved at once
        if !reviewEntries.isEmpty { fillScreen() }  // R-V7
    }

    /// Write the kept sets: the first ten in review order own the digit
    /// keys (1-9, 0), the rest are pool-only, dropped names recorded.
    /// Arrangements made during review are preview only (R-V6).
    private func saveReview() {  // R-V5
        var kept: [ColorSetEntry] = []
        for (i, e) in reviewEntries.enumerated() {
            var entry = e
            entry.slot = i < Session.keyOrder.count ? Session.keyOrder[i] : nil
            kept.append(entry)
        }
        reviewEntries = kept
        let ordered = kept.filter { $0.slot != nil }.sorted { $0.slot! < $1.slot! }
            + kept.filter { $0.slot == nil }
        store.saveColorSetFile(ColorSetFile(sets: ordered, dropped: droppedNames))
        colorSets = store.loadColorSets()
        output("saved \(kept.count) color sets, \(droppedNames.count) dropped")  // R-O11
    }

    // MARK: - The pool (R-K17)

    /// The whole pool in review order: digit-bound sets by key, then the rest.
    private func poolOrder() -> [ColorSetEntry] {
        let file = store.loadColorSetFile()
        var slotted = file.sets.filter { $0.slot != nil }
        if !slotted.contains(where: { $0.slot == 1 }) {
            let d = Store.defaultColorSets[1]!
            slotted.append(ColorSetEntry(slot: 1, name: d.name, colors: d.colors))
        }
        slotted.sort { Session.keyRank($0.slot!) < Session.keyRank($1.slot!) }
        return slotted + file.sets.filter { $0.slot == nil }
    }

    private func poolStep(_ step: Int) {  // R-K17: '[' / ']' walk the whole pool, wrapping
        guard !pool.isEmpty else { return }
        let current = pool.firstIndex { $0.name == activeSet?.name } ?? -1
        let n = pool.count
        let index = ((current + step) % n + n) % n
        let e = pool[index]
        activeSet = ColorSetEntry(slot: e.slot, name: e.name, colors: e.colors)
        if let slot = e.slot { colorSet = slot }
        output("color set \(e.name)")  // R-O15
    }

    /// Compute a screenful at once so a review step shows only the new state (R-V7).
    private func fillScreen() { for _ in 0..<rows { advance() } }

    // MARK: - The look cycle (R-B, R-W)

    /// n/p order (R-W7): file order, or looks grouped by rule, groups in
    /// order of each rule's first appearance.
    private func rebuildViewOrder() {
        if grouped {
            var groups: [String: [Int]] = [:]
            var ruleOrder: [String] = []
            for (i, p) in looks.enumerated() {
                if groups[p.rule] == nil { ruleOrder.append(p.rule) }
                groups[p.rule, default: []].append(i)
            }
            viewOrder = ruleOrder.flatMap { groups[$0]! }
        } else {
            viewOrder = Array(looks.indices)
        }
        viewPosition = lookIndex.flatMap { viewOrder.firstIndex(of: $0) }
    }

    /// 1-based group number of a file index among the rule groups, and the count.
    private func ruleGroup(of index: Int) -> (Int, Int) {
        var seen: [String] = []
        for p in looks where !seen.contains(p.rule) { seen.append(p.rule) }
        return ((seen.firstIndex(of: looks[index].rule) ?? 0) + 1, seen.count)
    }

    private func currentLook() -> Look {
        Look(rule: automaton.rule.id, colorset: activeName, colors: arrangedActiveColors())
    }

    /// Show a look's or the unsaved slot's colors: they become the active set (R-B2).
    private func showColors(name: String, colors: [String]) {
        activeSet = ColorSetEntry(slot: nil, name: name, colors: colors)
        activeArrangement = 0  // stored colors are already arranged
    }

    private func activateLook(viewPosition position: Int, pushUndo: Bool = true) {  // R-B2, R-W8
        let index = viewOrder[position]
        let look = looks[index]
        if grouped, lookIndex.map({ looks[$0].rule }) != look.rule {
            let (g, total) = ruleGroup(of: index)
            output("--- rule group \(g)/\(total) ---")  // R-O12
        }
        viewPosition = position
        lookIndex = index
        if let rule = try? Rule(id: look.rule), rule != automaton.rule {
            if pushUndo { undoStack.append(automaton.rule) }
            setRule(rule)
        }
        showColors(name: look.colorset, colors: look.colors)
        undoMark = undoStack.count
        output("look \(position + 1)/\(looks.count) \(look.colorset)")  // R-O4
        initCells()  // R-W8: the look grows in from a fresh field below the old rows
    }

    /// n/p: cycle through the looks in view order plus the unsaved slot, if
    /// occupied (R-B2, R-B3). Only odca-select has a file of looks.
    private func selectLook(step: Int) {
        let n = viewOrder.count
        let total = unsavedRule != nil ? n + 1 : n
        guard n > 0 else {
            output("no looks")  // R-O5
            return
        }
        let at = lookIndex == nil ? n : viewPosition!
        let to = ((at + step) % total + total) % total
        undoStack.append(automaton.rule)
        if to == n {  // only reachable when the unsaved slot is occupied
            lookIndex = nil
            viewPosition = nil
            output("unsaved rule")  // R-O4
            setRule(unsavedRule!)
            if let set = unsavedSet { showColors(name: set.name, colors: set.colors) }
            initCells()  // R-W8: every n/p step scrolls the selection in from a fresh field
        } else {
            activateLook(viewPosition: to, pushUndo: false)
        }
    }

    // MARK: - odca-select (R-W)

    private func loadSelect(_ url: URL) {  // R-W1
        looks = Store.loadOdcaFile(url) ?? []  // a missing file is created by the first save or at exit
        rebuildViewOrder()
        output("odca \(url.lastPathComponent): \(looks.count) looks")  // R-O12
        if !looks.isEmpty {
            // Open on look 1; the unsaved slot stays empty until r or m fires.
            unsavedRule = nil
            unsavedSet = nil
            activateLook(viewPosition: 0, pushUndo: false)
        }
    }

    private func saveLooks() {
        guard let url = selectFile else { return }
        Store.saveOdcaFile(looks, to: url)
        output("saved \(looks.count) look\(looks.count == 1 ? "" : "s") to \(url.lastPathComponent)")  // R-O12
    }

    private func saveLook() {  // R-W4: 's' rewrites the look under review's colors in place, or appends
        guard let i = lookIndex else {
            appendLook()
            return
        }
        if automaton.rule.id != looks[i].rule {
            // R-K3: a mutated look is a new look; a kept rule is never overwritten.
            // The position moves onto the new look, so further edits refine it.
            appendLook()
            lookIndex = looks.count - 1
            rebuildViewOrder()
            undoMark = undoStack.count  // an arrival (R-K19)
            return
        }
        looks[i] = Look(rule: looks[i].rule, colorset: activeName, colors: arrangedActiveColors())
        saveLooks()
        output("saved look \((viewPosition ?? i) + 1)/\(looks.count)")  // R-O12
    }

    private func appendLook() {  // R-W4: 'S' appends a copy of the screen; the position is unchanged
        looks.append(currentLook())  // always at the end of the file
        rebuildViewOrder()  // in the grouped order it joins its rule's group
        saveLooks()
        output("added look \(looks.count)/\(looks.count)")  // R-O12
    }

    private func deleteLook() {  // R-W5
        guard let i = lookIndex, let position = viewPosition else { return }
        looks.remove(at: i)  // in place: later looks keep their relative file order
        lookIndex = nil
        rebuildViewOrder()
        saveLooks()
        output("deleted look \(position + 1)/\(looks.count + 1)")  // R-O12
        if looks.isEmpty {
            // Nothing left to review: the rule on screen becomes the unsaved rule.
            viewPosition = nil
            unsavedRule = automaton.rule
            unsavedSet = activeSet
        } else {
            activateLook(viewPosition: min(position, viewOrder.count - 1))
        }
    }

    private func toggleGrouped() {  // R-W7: 'R'
        grouped.toggle()
        rebuildViewOrder()
        output("look order \(grouped ? "grouped by rule" : "file order")")  // R-O12
        flash()  // R-U10
    }

    // MARK: - odca (R-X)

    private func loadPlay(_ url: URL) {  // R-X1
        looks = Store.loadOdcaFile(url) ?? []
        output("odca \(url.lastPathComponent): \(looks.count) looks")  // R-O13
        if !looks.isEmpty {
            newPass()
            playLook(playOrder[0], reason: nil)
        }
    }

    /// File order, or a fresh shuffle per pass (R-X1): a permutation in which
    /// no rule and no color set follows itself, the seam from the look just
    /// played included; a file that allows no such order plays the last draw.
    private func newPass() {
        var order = Array(looks.indices)
        if shuffle && looks.count > 1 {
            for _ in 0..<Session.shuffleTries {
                order.shuffle(using: &rng)
                if noRepeats(order, after: lookIndex) { break }
            }
        }
        playOrder = order
        playPosition = 0
    }

    private func noRepeats(_ order: [Int], after previous: Int?) -> Bool {
        let chain = (previous.map { [$0] } ?? []) + order
        return zip(chain, chain.dropFirst()).allSatisfy { !clash($0, $1) }
    }

    /// Two looks repeat if they share the rule or the color set (in any arrangement).
    private func clash(_ a: Int, _ b: Int) -> Bool {
        looks[a].rule == looks[b].rule || looks[a].colors.sorted() == looks[b].colors.sorted()
    }

    /// Activate a look for play: its rule and colors, then a fresh seed (R-X4).
    private func playLook(_ index: Int, reason: String?) {
        let look = looks[index]
        lookIndex = index
        if let rule = try? Rule(id: look.rule), rule != automaton.rule { setRule(rule) }
        undoMark = undoStack.count  // R-K19: U returns to the look as played
        showColors(name: look.colorset, colors: look.colors)
        initCells()
        playElapsed = 0  // the look's screen time starts now
        let why = reason.map { " (\($0))" } ?? ""
        output("look \(index + 1)/\(looks.count) \(look.colorset)\(why)")  // R-O13
    }

    private func nextPlayLook(reason: String) {  // R-X2, R-X3: on through the pass, then a new pass
        playPosition = (playPosition ?? -1) + 1
        if playPosition! >= playOrder.count { newPass() }
        playLook(playOrder[playPosition!], reason: reason)
    }

    private func playStep(_ step: Int) {  // R-X6: N/P move through the pass by hand, wrapping
        guard !looks.isEmpty else { return }
        if step > 0 {
            nextPlayLook(reason: "next")
        } else {
            let n = playOrder.count
            playPosition = (((playPosition ?? 0) - 1) % n + n) % n
            playLook(playOrder[playPosition!], reason: "previous")
        }
    }

    /// Call at program exit: odca-select writes its file; review saves (R-V5).
    public func finish() {
        if selectMode { saveLooks() }
        if reviewMode { saveReview() }
    }

    /// R-K16: bake the active set's arrangement into its library entry (by
    /// name; a set not yet in the file is added, keeping its slot if it has
    /// one). No program binds this in 3.0.0; kept for the color set tool.
    private func saveColorSet() {
        let name = activeName
        let arranged = arrangedActiveColors()
        var file = store.loadColorSetFile()
        if let i = file.sets.firstIndex(where: { $0.name == name }) {
            file.sets[i].colors = arranged
        } else {
            file.sets.append(ColorSetEntry(slot: activeSet?.slot, name: name, colors: arranged))
        }
        store.saveColorSetFile(file)
        arrangementByName[name] = 0
        activeSet?.colors = arranged
        colorSets = store.loadColorSets()
        pool = poolOrder()
        output("saved color set \(name)")  // R-O10
    }

    private func selectColorSet(_ slot: Int) {
        if reviewMode { return }  // R-V1: digit keys are disabled during review
        guard let set = colorSets[slot] else { return }  // R-K9: undefined slot is a no-op
        colorSet = slot
        activeSet = ColorSetEntry(slot: slot, name: set.name, colors: set.colors)
    }

    /// Color and look keys shared by the paused and running states (R-K10).
    private func handleColorKey(_ key: Key) -> Bool {
        switch key {
        case .c: cycleColors(1)
        case .C: cycleColors(-1)
        case .S:
            if selectMode { appendLook() } else if !reviewMode && !playMode { saveColorSet() }
        case .N:
            if playMode { playStep(1) } else if reviewMode { reviewStep(1) }
        case .P:
            if playMode { playStep(-1) } else if reviewMode { reviewStep(-1) }
        case .X: if selectMode { deleteLook() } else if reviewMode { dropReview() }
        case .R: if selectMode { toggleGrouped() }
        case .poolPrev: if reviewMode { reviewStep(-1) } else { poolStep(-1) }  // R-K17
        case .poolNext: if reviewMode { reviewStep(1) } else { poolStep(1) }
        case .digit(let d): selectColorSet(d)
        default: return false
        }
        return true
    }

    // MARK: - Evolution and auto-init (R-U5, R-A)

    /// Compute one generation, display it, and apply auto-init (R-A).
    private func advance() {
        let row = automaton.step()
        pushRow(row)
        observe(row)
        if screenCounter != nil {  // R-K14
            counted += 1
            if counted % rows == 0 {
                screenCounter! += 1
                output("screen \(screenCounter!)")  // R-O7
            }
        }
        if autoInit && boringStreak >= rows {
            let reason = boringReason ?? "boring"
            if playMode && !looks.isEmpty && playElapsed >= playTimeout {
                nextPlayLook(reason: reason)  // R-X3: watchdog expired, a re-init transitions
            } else {
                initCells()
                output("auto-init (\(reason))")  // R-O6
            }
        }
    }

    /// Classify a computed generation as boring or not (R-A1).
    func observe(_ row: [UInt8]) {
        // Brent's cycle detection: one saved row, refreshed at powers of two.
        // The automaton is deterministic, so a recurring row proves the
        // future periodic; steps since the snapshot are exactly the period.
        if cyclePeriod == nil {
            if brentSnapshot == nil {
                brentSnapshot = row
            } else {
                brentSteps += 1
                if row == brentSnapshot! {
                    cyclePeriod = brentSteps
                    output("cycle period \(brentSteps)")  // R-O8
                } else if brentSteps == brentPower {
                    brentSnapshot = row
                    brentPower *= 2
                    brentSteps = 0
                }
            }
        }
        // Window repetition: seen within the last repeatScreens screens.
        let repeating = (recentCounts[row] ?? 0) > 0
        recentRows.append(row)
        recentCounts[row, default: 0] += 1
        if recentRows.count > Session.repeatScreens * rows {
            let old = recentRows.removeFirst()
            if let n = recentCounts[old] {
                if n <= 1 { recentCounts[old] = nil } else { recentCounts[old] = n - 1 }
            }
        }
        // Census: extinction with living-minority patience, and stagnation.
        var census = [Int](repeating: 0, count: Rule.stateCount)
        for c in row { census[Int(c)] += 1 }
        let producible = Set(automaton.rule.states.map { Int($0) }).sorted()
        let extinct = producible.filter { census[$0] == 0 }
        let minority = producible.filter {
            census[$0] > 0 && Double(census[$0]) < Session.minorityFraction * Double(row.count)
        }
        minorityCounts.append(minority.reduce(0) { $0 + census[$1] })
        let window = Session.stagnationScreens * rows
        if minorityCounts.count > window { minorityCounts.removeFirst() }
        var stagnant = false
        if minorityCounts.count == window {
            let lo = minorityCounts.min()!, hi = minorityCounts.max()!
            let mean = Double(minorityCounts.reduce(0, +)) / Double(window)
            stagnant = mean > 0 && Double(hi - lo) / mean < Session.stagnationSwing
        }

        let reason: String?
        if !extinct.isEmpty && minority.isEmpty {
            let names = extinct.map(String.init).joined(separator: ", ")
            reason = "state\(extinct.count > 1 ? "s" : "") \(names) extinct"
        } else if let period = cyclePeriod {
            reason = "repeating (period \(period))"
        } else if repeating {
            reason = "repeating"
        } else if stagnant {
            reason = "stagnant"
        } else {
            reason = nil
        }
        boringStreak = reason == nil ? 0 : boringStreak + 1
        boringReason = reason
    }

    private func resetBoredom() {  // R-A3
        boringStreak = 0
        boringReason = nil
        recentRows.removeAll()
        recentCounts.removeAll()
        minorityCounts.removeAll()
        brentSnapshot = nil
        brentPower = 1
        brentSteps = 0
        cyclePeriod = nil
    }

    /// Advance by elapsed wall-clock time (R-U5); call at ~60 Hz.
    public func tick(_ dt: Double) {
        drainSearch()
        flashRemaining = max(0, flashRemaining - dt)  // display only: runs while paused (R-U10)
        if paused {
            // The main accumulator is frozen while paused (no catch-up burst,
            // R-K10); a queued screenful (R-K13) paces on its own accumulator.
            if screenRemaining > 0 {
                zipAccumulated += dt
                let fast = delay / Session.screenSpeedup
                let steps = min(Int(zipAccumulated / fast), screenRemaining, Session.stepCap)
                zipAccumulated -= Double(steps) * fast
                for _ in 0..<steps { advance() }
                screenRemaining -= steps
            }
            if screenRemaining == 0 { zipAccumulated = 0 }
            return
        }
        accumulated += dt
        // Clocks advance before the generations, so a re-seed made by those
        // generations restarts the grace period from this instant (R-X3).
        sinceInit += dt
        if playMode { playElapsed += dt }
        let steps = Int(accumulated / delay)
        accumulated -= Double(steps) * delay
        for _ in 0..<min(steps, Session.stepCap) { advance() }
        if playMode && !looks.isEmpty  // R-X3: watchdog expired and the grace period observed
            && playElapsed >= playTimeout && sinceInit >= playGrace {
            nextPlayLook(reason: "timeout")
        }
    }

    private func drainSearch() {
        guard candidates.count < Session.maxCandidates else { return }
        let found = search.drain()
        if !found.isEmpty {
            candidates.append(contentsOf: found)
            if candidates.count > Session.maxCandidates {
                candidates.removeLast(candidates.count - Session.maxCandidates)
            }
            store.saveCandidates(candidates)
        }
    }

    // MARK: - Rules (R-K2..R-K6, R-B)

    private func setRule(_ rule: Rule) {
        automaton.rule = rule
        resetBoredom()
        store.saveRule(rule)
        output("rule \(rule.id)")  // R-O1
    }

    /// Make `rule` current and the occupant of the cycle's unsaved slot (R-B3).
    /// Make `rule` current and the occupant of the unsaved slot (R-B3). An
    /// arrival (r, or entering the slot) is where U unwinds to (R-K19); a
    /// mutation made on the slot is an edit, and U undoes it too.
    private func setUnsavedRule(_ rule: Rule, arrival: Bool = true) {
        unsavedRule = rule
        unsavedSet = activeSet
        lookIndex = nil
        viewPosition = nil
        setRule(rule)
        if arrival { undoMark = undoStack.count }
    }

    private func newRule() {  // R-K2
        undoStack.append(automaton.rule)
        drainSearch()
        let rule: Rule
        if !candidates.isEmpty {
            rule = candidates.removeFirst()
            store.saveCandidates(candidates)
        } else {
            let (found, tries) = Classifier.findCandidate(using: &rng)
            if tries > 1 {
                output("discarded \(tries - 1) rule\(tries > 2 ? "s" : "")")  // R-O2
            }
            rule = found
        }
        setUnsavedRule(rule)
    }

    private func mutateRule() {  // R-K3
        undoStack.append(automaton.rule)
        let mutant = automaton.rule.mutated(using: &rng)
        if selectMode && lookIndex != nil {
            setRule(mutant)  // the look under review is now changed: 's' and 'S' save it as a new look
        } else {
            setUnsavedRule(mutant, arrival: false)
        }
    }

    private func undo() {  // R-K4
        if let rule = undoStack.popLast() { setRule(rule) }
    }

    private func undoAll() {  // R-K19: every change since the cycle position last moved, at once
        let mark = min(undoMark, undoStack.count)
        guard undoStack.count > mark else { return }
        let rule = undoStack[mark]
        undoStack.removeSubrange(mark...)
        setRule(rule)
        if selectMode && lookIndex == nil { unsavedRule = rule }  // the slot's mutations are undone with it
    }

    private func initCells() {  // R-K6
        automaton.resetRandom(using: &rng)
        pushRow(automaton.cells)
        resetBoredom()
        sinceInit = 0  // R-X3: any initialization restarts the grace period
    }

    // MARK: - Keys (R-K)

    /// Returns false when the program should quit.
    public func handleKey(_ key: Key) -> Bool {
        if key == .q { return false }
        if paused {  // R-K10: space, Return, s, and the color and look keys are live
            switch key {
            case .space:
                paused = false
                screenRemaining = 0
                screenCounter = 0  // R-K14: resume (re)starts the screen counter
                counted = 0
                // Resume seamlessly: the paused view shows the newest row fully
                // (offset 1); start at the next generation so the first tick
                // computes it and the picture does not jump.
                accumulated = delay
            case .ret:
                advance()  // R-K11: single step, stay paused
            case .s:
                screenRemaining += rows  // R-K13: queue a screenful
            default:
                _ = handleColorKey(key)
            }
            return true
        }
        switch key {
        case .space:
            paused = true
        case .r:
            newRule()
        case .m:
            mutateRule()
        case .u:
            undo()
        case .U:
            undoAll()  // R-K19
        case .s:
            if selectMode { saveLook() }  // R-W4; otherwise nothing to save into
        case .i:
            initCells()
        case .n:
            if playMode { playStep(1) } else { selectLook(step: 1) }
        case .p:
            if playMode { playStep(-1) } else { selectLook(step: -1) }
        case .a:  // R-K12
            autoInit.toggle()
            output("auto-init \(autoInit ? "on" : "off")")  // R-O6
        case .c, .C, .S, .N, .P, .X, .R, .poolPrev, .poolNext, .digit:
            _ = handleColorKey(key)
        case .plus:
            delay = max(delay / 2, Session.minDelay)
        case .minus:
            delay = min(delay * 2, Session.maxDelay)
        case .q, .ret:
            break
        }
        return true
    }
}
