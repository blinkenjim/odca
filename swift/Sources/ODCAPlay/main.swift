// odca: play a show, one or more play scripts or odca files (REQTS section 4d).
import Foundation
import ODCAKit
import ODCAUI

let (files, flags, options) = parseArguments(program: "odca", help: helpOdca,
                                             flags: ["--shuffle", "--fullscreen"] + cellFlags,
                                             options: ["--watchdog", "--grace"],
                                             positional: "<file> [<file> ...]", many: true)
let cellSize = chooseCellSize(program: "odca", flags: flags)  // R-U2
let watchdog = wholeSeconds(program: "odca", options: options, "--watchdog", default: Session.playTimeout)  // R-X2
let grace = wholeSeconds(program: "odca", options: options, "--grace", default: Session.playGrace)  // R-X3
for file in files where !FileManager.default.fileExists(atPath: file.path) {  // R-X1: every file must exist
    print("error: \(file.relativePath) does not exist")
    exit(1)
}
let show: [Segment]
do {
    show = try Show.load(files)  // R-X1, R-X7: scripts are read and checked before the window opens
} catch {
    print("error: \(error)")
    exit(1)
}
MainActor.assumeIsolated {  // top-level code of an executable runs on the main thread
    launch(fullScreen: flags.contains("--fullscreen"), cellSize: cellSize) { cols, rows in  // R-U2
        Session(cols: cols, rows: rows, show: show, shuffle: flags.contains("--shuffle"),
                initialDelay: Session.initialDelay * Double(cellSize) / 4,  // R-U5
                playTimeout: watchdog, playGrace: grace)
    }
}
