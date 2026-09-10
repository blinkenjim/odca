// odca-evolve: search an odca file's rules for their longest-lived seeds
// (REQTS section 4e). No window, no state under ~/.odca, no background search.
import Foundation
import ODCAKit

let (files, _, options) = parseArguments(program: "odca-evolve", help: helpOdcaEvolve,
                                         options: ["--cells", "--time", "--cap"])
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
    say("rule \(id) (\(index + 1)/\(rules.count)): \(cells) cells", at: deadline)  // opens with the whole budget
    let search = SeedSearch(rule: rule, cells: cells, cap: cap, kept: seeds[id]?[cells] ?? [])
    search.onKept = { seed, rank in
        say("kept \(seed.generations) generations, rank \(rank) (\(seed.end))", at: deadline)
    }
    let kept = search.run(until: deadline) { remaining in
        if interrupted { search.stop() }
        countdown("  \(Evolve.hms(remaining))")
    }
    outputLock.lock()
    clearCountdown()
    outputLock.unlock()
    seeds[id, default: [:]][cells] = kept  // R-E3: the merged ten, written now
    Store.saveOdcaFile(pairs, seeds: seeds, to: file)
    if interrupted { exit(130) }
}
