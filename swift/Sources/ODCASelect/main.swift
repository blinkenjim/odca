// odca-select: compose pairs in an odca file (REQTS section 4c).
import Foundation
import ODCAKit
import ODCAUI

let (files, flags, _) = parseArguments(program: "odca-select", help: helpOdcaSelect, flags: cellFlags)
let file = files[0]
let cellSize = chooseCellSize(program: "odca-select", flags: flags)  // R-U2
MainActor.assumeIsolated {  // top-level code of an executable runs on the main thread
    launch(cellSize: cellSize) { cols, rows in
        Session(cols: cols, rows: rows, selectFile: file,  // R-W1: a missing file is created on the first save
                initialDelay: Session.initialDelay * Double(cellSize) / 4)  // R-U5
    }
}
