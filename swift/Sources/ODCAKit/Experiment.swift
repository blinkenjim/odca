/// R-M12: experimental rule classes, chosen with `-x` / `--experiment`.
///
/// Every one of these brings the *grandparent* — the cell's own state two
/// generations back — into the rule, which makes them second-order cellular
/// automata. That is a studied family: Fredkin's construction (case 2) is the
/// standard way to make a reversible CA out of an irreversible one, and
/// Toffoli and Margolus build most of *Cellular Automata Machines* (1987) on
/// it. A second-order rule is always a first-order rule on the doubled state
/// (current, previous), so none of this is more powerful than what we have —
/// but it is a differently shaped slice of that space, which is the point.
///
/// Since 3.92.0 an odca file records which class a pair's rule belongs to
/// (R-P3), so all four can be kept and played from one file.
public enum Experiment: Int, CaseIterable {
    /// The ODCA of R-M5: no grandparent, three counted cells, 20 entries.
    case none = 0
    /// The grandparent selects among four sub-rules for each count vector:
    /// `next = rule[countvector][grandparent]`, 80 entries. A strict superset
    /// — four equal columns everywhere is exactly a case-0 rule — so a cell's
    /// own recent past decides which of four moods the automaton is in.
    case modal = 1
    /// Fredkin's second-order form, `next = rule[countvector] - grandparent`
    /// (mod 4), 20 entries and so the same rule IDs as case 0. Reversible:
    /// any two consecutive rows determine the row before them, so there are
    /// no orphans, no transient, and nothing dies out for good.
    case fredkin = 2
    /// The grandparent counted as a fourth cell, order-blind like the rest:
    /// 35 multisets of four cells from four states. Memory as inertia rather
    /// than mode-switching, the grandparent carrying no more weight than a
    /// neighbour.
    case totalistic4 = 3

    /// Whether the rule reads the grandparent at all.
    public var secondOrder: Bool { self != .none }

    /// Cells whose states the rule counts.
    public var countedCells: Int { self == .totalistic4 ? 4 : 3 }

    /// Entries in a rule table: one per count vector, times four under
    /// `modal` where the grandparent chooses a column.
    public var tableSize: Int {
        countVectors.count * (self == .modal ? Rule.stateCount : 1)
    }

    /// Weighted-state lookup, as R-M7 does it for three cells: with one more
    /// than the counted cells as the radix, a plain sum of the weights is a
    /// unique index. Three cells give the familiar 0, 1, 4, 16; four give
    /// 0, 1, 5, 25.
    public var weights: [UInt8] {
        let radix = UInt8(countedCells + 1)
        return [0, 1, radix, radix * radix]
    }

    /// Entries in the dense lookup a weighted sum indexes: 49 for three
    /// counted cells, 101 for four. Under `modal` there are four of these
    /// side by side, one per grandparent state.
    public var denseSize: Int { countedCells * Int(weights[3]) + 1 }

    /// The count vectors (n0, n1, n2, n3) summing to the counted cells, in
    /// canonical ascending-lexicographic order (R-M6). 20 for three cells,
    /// 35 for four.
    public var countVectors: [[Int]] {
        let total = countedCells
        var vectors: [[Int]] = []
        for n0 in 0...total {
            for n1 in 0...(total - n0) {
                for n2 in 0...(total - n0 - n1) {
                    vectors.append([n0, n1, n2, total - n0 - n1 - n2])
                }
            }
        }
        return vectors
    }

    /// Where a count vector lands in the dense lookup.
    public func denseIndex(of vector: [Int]) -> Int {
        let w = weights
        return vector[1] * Int(w[1]) + vector[2] * Int(w[2]) + vector[3] * Int(w[3])
    }


    /// R-P3: what an odca file's `experiment` key says, and reads back.
    /// The ODCA writes no key at all, so every file written before R-M12
    /// stays exactly what it was and reads as what it always meant.
    public var fileName: String? {
        switch self {
        case .none: return nil
        case .modal: return "modal"
        case .fredkin: return "fredkin"
        case .totalistic4: return "totalistic4"
        }
    }

    public static func named(_ text: String?) -> Experiment? {
        guard let text = text else { return Experiment.none }
        return allCases.first { $0.fileName == text }
    }

    /// The key a rule's seeds are recorded under (R-P3). An ODCA rule keeps
    /// the bare ID it always had; another class qualifies it, since a
    /// 20-digit ID means two different automata once fredkin exists.
    public func seedKey(_ id: String) -> String {
        fileName.map { "\($0):\(id)" } ?? id
    }

    /// Split such a key back into its class and rule ID, or nil if it names
    /// a class this version does not know.
    public static func splitSeedKey(_ key: String) -> (Experiment, String)? {
        guard let colon = key.firstIndex(of: ":") else { return (Experiment.none, key) }
        guard let experiment = named(String(key[key.startIndex..<colon])) else { return nil }
        return (experiment, String(key[key.index(after: colon)...]))
    }

    /// The spelling `-x` takes, and what a bad one is told.
    public static func parse(_ text: String) -> Experiment? {
        guard let n = Int(text), let experiment = Experiment(rawValue: n) else { return nil }
        return experiment
    }

    public static var choices: String {
        allCases.map { String($0.rawValue) }.joined(separator: ", ")
    }
}
