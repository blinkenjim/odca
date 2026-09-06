// odca-select: compose looks in an odca file (REQTS section 4c).
import Foundation
import ODCAKit
import ODCAUI

let (file, _) = parseArguments(program: "odca-select", help: helpOdcaSelect)
MainActor.assumeIsolated {  // top-level code of an executable runs on the main thread
    launch { cols, rows in
        Session(cols: cols, rows: rows, selectFile: file)  // R-W1: a missing file is created on the first save
    }
}
