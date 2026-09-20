// odca-evolve: search an odca file's rules for their longest-lived seeds
// (REQTS section 4e). No window, no state under ~/.odca, no background search.
import Foundation
import ODCAKit

let (files, flags, options) = parseArguments(program: "odca-evolve", help: helpOdcaEvolve,
                                             flags: ["--parity", "-v", "--verbose"],
                                             options: ["--cells", "--time", "--cap", "--limit", "-o"],
                                             valueNames: ["-o": "<file.odca>"],
                                             positional: "<file.odca> [<file.odca> ...]", many: true)
let parity = flags.contains("--parity")  // R-E5
let verbose = flags.contains("-v") || flags.contains("--verbose")  // R-E6
if options["--limit"] != nil && !parity {
    print("odca-evolve: --limit applies only with --parity")
    exit(2)
}
let limit = wholeNumber(program: "odca-evolve", options: options, "--limit", unit: "rules", minimum: 0, default: 0)  // R-E5: 0 is no limit
let cells = wholeNumber(program: "odca-evolve", options: options, "--cells", unit: "cells", minimum: Session.minCols)  // R-E1
let budget = wholeNumber(program: "odca-evolve", options: options, "--time", unit: "seconds")  // R-E1
let cap = wholeNumber(program: "odca-evolve", options: options, "--cap", unit: "generations", default: Evolve.defaultCap)  // R-E2

// R-E1: the output file is always named outright, however many inputs
// there are. A single input used to be written back to implicitly, which
// meant a file could be rewritten as a side effect of being searched;
// having to say where the results go makes that a choice instead.
guard let path = options["-o"] else {
    print("odca-evolve: -o <file.odca> is required")
    exit(2)
}
let output = URL(fileURLWithPath: path)
for file in files where !FileManager.default.fileExists(atPath: file.path) {  // R-E1: every input must exist
    print("error: \(file.relativePath) does not exist")
    exit(1)
}

// Naming an input as the output is allowed and is the ordinary way to
// keep searching one file, but it overwrites that file, so it is said
// out loud. Paths are compared resolved, so `f.odca`, `./f.odca` and an
// absolute path to it are recognised as the same file.
func sameFile(_ a: URL, _ b: URL) -> Bool {
    a.resolvingSymlinksInPath().standardizedFileURL.path
        == b.resolvingSymlinksInPath().standardizedFileURL.path
}
if let shared = files.first(where: { sameFile($0, output) }) {  // R-E1
    // Shouted rather than prefixed with the program name as other messages
    // are: this one warns that a file is about to be rewritten, and is worth
    // catching the eye in a scrolling terminal.
    print("*** WARNING: \(shared.relativePath) is both an input and the output, and will be overwritten")
}
// The union is wholly in memory before anything is written, so naming an
// input file as the output is safe.
let pairs = Store.loadOdcaFiles(files)
guard !pairs.isEmpty else {  // R-E1: and between them hold pairs
    print("error: \(files.map(\.relativePath).joined(separator: ", ")): no pairs")
    exit(1)
}
var seeds = Store.loadSeeds(files)
var rules: [String] = []  // distinct, in order of first appearance (R-E2)
for pair in pairs where !rules.contains(pair.rule) { rules.append(pair.rule) }

// R-E6: which pairs a rule belongs to, for the verbose lines. A rule can
// belong to more than one — the same automaton under different colours is
// a different pair — so this is a list, and each gets its own line rather
// than one of them standing in for the rest.
var pairsByRule: [String: [Pair]] = [:]
for pair in pairs { pairsByRule[pair.rule, default: []].append(pair) }
func pairLines(_ id: String) -> [String] {
    (pairsByRule[id] ?? []).map { "\($0.name ?? "(unnamed)"), \($0.colorset), \(id)" }
}
func ages(_ seeds: [Seed]) -> String {  // R-O16: generations, longest first
    seeds.map { String($0.generations) }.joined(separator: ", ")
}

// Ctrl-C: finish the rule in hand by writing what it has, then leave (R-E4).
var interrupted = false
signal(SIGINT) { _ in interrupted = true }

// Terminal output (R-O16): lines, each opening with the time left on the
// rule, and on a terminal a countdown redrawn in place, cleared before any
// line is printed over it.
let terminal = isatty(1) != 0
let outputLock = NSLock()
var countdownShown = false

/// R-E6: whether the blank line that separates one verbose burst from the
/// next is already on screen and not yet used up. There is only ever one,
/// and either the countdown or the next burst puts it there, whichever
/// comes first: the countdown draws it so that it does not sit flush
/// against the burst above, and a burst arriving afterwards writes over
/// the countdown's own line rather than adding a second blank.
var separatorOnScreen = false

func clearCountdown() {
    if countdownShown {
        print("\r\u{1B}[K", terminator: "")  // back to column 0 and erase, leaving the line to be written on
        countdownShown = false
    }
}
/// `blankBefore` asks for an empty line above, put there inside the same
/// lock so the blank and the line it announces cannot be separated. If the
/// countdown already laid one down, this takes over that line instead of
/// adding another.
func say(_ line: String, at deadline: Date, blankBefore: Bool = false) {
    outputLock.lock()
    clearCountdown()
    if blankBefore && !separatorOnScreen { print("") }
    print("\(Evolve.hms(deadline.timeIntervalSinceNow)) \(line)")
    separatorOnScreen = false
    outputLock.unlock()
}
func countdown(_ text: String) {
    guard terminal else { return }
    outputLock.lock()
    // Only on its first draw after a line, and only under verbose, where
    // blanks are the way bursts are told apart; plain output stays as it was.
    if verbose && !separatorOnScreen && !countdownShown {
        print("")
        separatorOnScreen = true
    }
    print("\r\u{1B}[K" + text, terminator: "")
    fflush(stdout)
    countdownShown = true
    outputLock.unlock()
}
// R-E2: round trips through the rules until interrupted (R-E4).
var round = 0
while true {
  round += 1
  let whole = Date().addingTimeInterval(Double(budget))  // the round trip's own lines open with the whole budget
  say("round trip \(round)", at: whole)  // R-O16
  // R-E5: under --parity the round trip's plan is made up front, on the
  // seeds as they stand now: the rules far ahead give up their turns,
  // at most --limit of them, whatever the rules before them find.
  var plan: [String: (shortest: Int, longest: Int)] = [:]
  if parity {
    let made = Evolve.parityPlan(rules: rules, width: cells, seeds: seeds, limit: limit)
    plan = made.skips
    let limited = limit > 0 ? " (limit \(limit))" : ""
    let running = rules.count - plan.count
    say("parity: \(rules.count) rules this round trip, \(plan.count) of \(made.ahead) ahead give up their turn, \(running) run\(limited)", at: whole)
  }
  let toRun = rules.count - plan.count
  var ran = 0
  for (index, id) in rules.enumerated() {
    let rule = try! Rule(id: id)  // loadOdcaFile keeps only valid rule IDs
    let deadline = Date().addingTimeInterval(Double(budget))
    if let (shortest, longest) = plan[id] {
        say("rule \(id) (\(index + 1)/\(rules.count)): \(cells) cells, skipped: shortest \(shortest) × 0.9 outlives \(longest)", at: deadline)
        continue
    }
    ran += 1
    let place = parity ? ", running \(ran) of \(toRun)" : ""  // R-O16: its place among the rules that run
    say("rule \(id) (\(index + 1)/\(rules.count)\(place)): \(cells) cells", at: deadline)  // opens with the whole budget
    let search = SeedSearch(rule: rule, cells: cells, cap: cap, kept: seeds[id]?[cells] ?? [])
    // R-E6: verbose adds, under each join, which pairs the rule belongs to
    // and the ten as they now stand. The ten come in as an argument rather
    // than being read back from the search: this runs with the search's lock
    // held, and reading `kept` would take that same lock and deadlock.
    search.onKept = { seed, rank, kept in
        // Verbose makes each join a burst of several lines, so it opens with
        // a blank one to keep bursts apart. Plain output stays one line a
        // join and needs no spacing. The burst is assembled first so the
        // blank always falls on whatever line comes first, which under
        // verbose is the pairs the rule belongs to: they name what is being
        // improved, and so read better above the news than below it.
        let keptLine = "kept \(seed.generations) generations, rank \(rank) (\(seed.end))"
        let lines = verbose ? pairLines(id) + [keptLine, ages(kept)] : [keptLine]
        for (i, line) in lines.enumerated() {
            say(line, at: deadline, blankBefore: verbose && i == 0)
        }
    }
    // The rate shown is recent, not cumulative: rows finished over the last
    // ten seconds of ticks. A cumulative average carries the rows still in
    // flight (one per worker) as a deficit that shrinks like 1/t, so it
    // would creep upward long after the search had settled.
    var samples: [(elapsed: Double, tried: Int)] = []
    var cutShort = false
    let kept = search.run(until: deadline) { remaining in
        if interrupted { search.stop() }
        if !cutShort && Evolve.allSurvived(search.kept) {  // R-E3: nothing left to improve
            cutShort = true
            search.stop()
        }
        let elapsed = Double(budget) - remaining
        samples.append((elapsed, search.tried))
        if samples.count > Evolve.rateWindow + 1 { samples.removeFirst() }
        let first = samples[0], last = samples[samples.count - 1]
        let span = last.elapsed - first.elapsed
        let rate = span > 0 ? Double(last.tried - first.tried) / span : 0
        countdown("\(Evolve.hms(remaining))  \(Int(rate.rounded())) seeds/s")
    }
    outputLock.lock()
    clearCountdown()
    outputLock.unlock()
    // R-E6: the lines closing a turn are a burst of their own, so under
    // verbose they open with a blank line as a join does — one blank for
    // the whole of what follows, not one per line.
    var turnEndOpened = false
    func closing(_ line: String) {
        say(line, at: deadline, blankBefore: verbose && !turnEndOpened)
        turnEndOpened = true
    }
    if cutShort { closing("all ten survived the cap: turn ended early") }  // R-O16
    if !kept.isEmpty {  // R-O16: the ages of the ten, longest first, before moving on
        if verbose {  // R-E6: name the pairs this rule belongs to first
            for line in pairLines(id) { closing(line) }
        }
        closing(ages(kept))
    }
    seeds[id, default: [:]][cells] = kept  // R-E3: the merged ten, written now
    Store.saveOdcaFile(pairs, seeds: seeds, to: output)
    if interrupted { exit(130) }
  }
}
