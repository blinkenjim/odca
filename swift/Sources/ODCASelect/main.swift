// odca-select: compose pairs in an odca file (REQTS section 4c).
import Foundation
import ODCAKit
import ODCAUI

let (files, flags, _) = parseArguments(program: "odca-select", help: helpOdcaSelect, flags: ["--longest"] + cellFlags)
let file = files[0]
// R-P6: a missing file is made on the first save (R-W1), but one that exists
// and will not parse must not open a window: this program saves back over the
// file it was given, so starting on an empty reading of it would destroy it.
if let why = Store.rejection(file) {
    print("error: \(why)")
    exit(1)
}
let cellSize = chooseCellSize(program: "odca-select", flags: flags)  // R-U2
MainActor.assumeIsolated {  // top-level code of an executable runs on the main thread
    launch(cellSize: cellSize) { cols, rows in
        Session(cols: cols, rows: rows, selectFile: file,  // R-W1: a missing file is created on the first save
                selectLongest: flags.contains("--longest"),  // R-W9: only the pairs with seeds
                initialDelay: Session.initialDelay * Double(cellSize) / 4)  // R-U5
    }
}
