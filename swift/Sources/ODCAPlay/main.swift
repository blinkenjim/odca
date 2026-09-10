// odca: play a show, one or more play scripts or odca files (REQTS section 4d).
import Foundation
import ODCAKit
import ODCAUI

let (files, flags, options) = parseArguments(program: "odca", help: helpOdca,
                                             flags: ["--shuffle", "--longest", "--fullscreen"] + cellFlags,
                                             options: ["--watchdog", "--grace", "--cells"],
                                             positional: "<file> [<file> ...]", many: true)
let cellSize = chooseCellSize(program: "odca", flags: flags)  // R-U2
let longest = flags.contains("--longest")  // R-X8
if longest {
    for option in ["--watchdog", "--grace"] where options[option] != nil {  // no clocks: a seed plays to its end
        print("odca: \(option) does not apply with --longest")
        exit(2)
    }
} else if options["--cells"] != nil {
    print("odca: --cells applies only with --longest")
    exit(2)
}
let watchdog = wholeSeconds(program: "odca", options: options, "--watchdog", default: Session.playTimeout)  // R-X2
let grace = wholeSeconds(program: "odca", options: options, "--grace", default: Session.playGrace)  // R-X3
let cells = options["--cells"] == nil ? nil
    : wholeNumber(program: "odca", options: options, "--cells", unit: "cells", minimum: Session.minCols)
for file in files where !FileManager.default.fileExists(atPath: file.path) {  // R-X1: every file must exist
    print("error: \(file.relativePath) does not exist")
    exit(1)
}
if longest, let script = files.first(where: { $0.pathExtension != "odca" }) {  // R-X8: odca files only
    print("error: \(script.relativePath): --longest plays odca files only")
    exit(1)
}
let show: [Segment]
let width: Int?
do {
    show = try Show.load(files)  // R-X1, R-X7: scripts are read and checked before the window opens
    width = longest ? try Show.seedWidth(show, cells: cells) : nil  // R-X8: the one width, or the chosen one
} catch {
    print("error: \(error)")
    exit(1)
}
MainActor.assumeIsolated {  // top-level code of an executable runs on the main thread
    launch(fullScreen: flags.contains("--fullscreen"), cellSize: cellSize, cols: width) { cols, rows in  // R-U2
        Session(cols: cols, rows: rows, show: show, shuffle: flags.contains("--shuffle"), longest: longest,
                initialDelay: Session.initialDelay * Double(cellSize) / 4,  // R-U5
                playTimeout: watchdog, playGrace: grace)
    }
}
