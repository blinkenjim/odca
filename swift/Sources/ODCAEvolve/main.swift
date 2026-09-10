// odca-evolve: search an odca file's rules for their longest-lived seeds
// (REQTS section 4e). No window, no state under ~/.odca, no background search.
import Foundation
import ODCAKit

let (files, flags, options) = parseArguments(program: "odca-evolve", help: helpOdcaEvolve,
                                             flags: ["--parity"], options: ["--cells", "--time", "--cap"])
let parity = flags.contains("--parity")  // R-E5
let file = files[0]
let cells = wholeNumber(program: "odca-evolve", options: options, "--cells", unit: "cells", minimum: Session.minCols)  // R-E1
let budget = wholeNumber(program: "odca-evolve", options: options, "--time", unit: "seconds")  // R-E1
let cap = wholeNumber(program: "odca-evolve", options: options, "--cap", unit: "generations", default: Evolve.defaultCap)  // R-E2
guard FileManager.default.fileExists(atPath: file.path) else {  // R-E1: the file must exist
    print("error: \(file.relativePath) does not exist")
    exit(1)
}
let pairs = Store.loadOdcaFile(file) ?? []
guard !pairs.isEmpty else {  // R-E1: and hold pairs
    print("error: \(file.relativePath): no pairs")
    exit(1)
}
var seeds = Store.loadSeeds(file)
var rules: [String] = []  // distinct, in order of first appearance (R-E2)
for pair in pairs where !rules.contains(pair.rule) { rules.append(pair.rule) }

// Ctrl-C: finish the rule in hand by writing what it has, then leave (R-E4).
var interrupted = false
signal(SIGINT) { _ in interrupted = true }

// Terminal output (R-O16): lines, each opening with the time left on the
// rule, and on a terminal a countdown redrawn in place, cleared before any
// line is printed over it.
let terminal = isatty(1) != 0
let outputLock = NSLock()
var countdownShown = false
func clearCountdown() {
    if countdownShown {
        print("\r\u{1B}[K", terminator: "")
        countdownShown = false
    }
}
func say(_ line: String, at deadline: Date) {
    outputLock.lock()
    clearCountdown()
    print("\(Evolve.hms(deadline.timeIntervalSinceNow)) \(line)")
    outputLock.unlock()
}
func countdown(_ text: String) {
    guard terminal else { return }
    outputLock.lock()
    print("\r\u{1B}[K" + text, terminator: "")
    fflush(stdout)
    countdownShown = true
    outputLock.unlock()
}
for (index, id) in rules.enumerated() {
    let rule = try! Rule(id: id)  // loadOdcaFile keeps only valid rule IDs
    let deadline = Date().addingTimeInterval(Double(budget))
    // R-E5: under --parity a rule far ahead of every other gives up its
    // turn, judged on the seeds as they stand now, this run's included.
    if parity, let (shortest, longest) = Evolve.givesUpTurn(rule: id, width: cells, seeds: seeds, rules: rules) {
        say("rule \(id) (\(index + 1)/\(rules.count)): \(cells) cells, skipped: shortest \(shortest) × 0.9 outlives \(longest)", at: deadline)
        continue
    }
    say("rule \(id) (\(index + 1)/\(rules.count)): \(cells) cells", at: deadline)  // opens with the whole budget
    let search = SeedSearch(rule: rule, cells: cells, cap: cap, kept: seeds[id]?[cells] ?? [])
    search.onKept = { seed, rank in
        say("kept \(seed.generations) generations, rank \(rank) (\(seed.end))", at: deadline)
    }
    // The rate shown is recent, not cumulative: rows finished over the last
    // ten seconds of ticks. A cumulative average carries the rows still in
    // flight (one per worker) as a deficit that shrinks like 1/t, so it
    // would creep upward long after the search had settled.
    var samples: [(elapsed: Double, tried: Int)] = []
    let kept = search.run(until: deadline) { remaining in
        if interrupted { search.stop() }
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
    if !kept.isEmpty {  // R-O16: the ages of the ten, longest first, before moving on
        say(kept.map { String($0.generations) }.joined(separator: ", "), at: deadline)
    }
    seeds[id, default: [:]][cells] = kept  // R-E3: the merged ten, written now
    Store.saveOdcaFile(pairs, seeds: seeds, to: file)
    if interrupted { exit(130) }
}
