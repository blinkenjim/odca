// odca: play the looks of an odca file (REQTS section 4d).
import Foundation
import ODCAKit
import ODCAUI

let (file, flags) = parseArguments(program: "odca", help: helpOdca, flags: ["--shuffle", "--fullscreen"] + cellFlags)
let cellSize = chooseCellSize(program: "odca", flags: flags)  // R-U2
guard FileManager.default.fileExists(atPath: file.path) else {  // R-X1: the file must exist
    print("error: \(file.path) does not exist")
    exit(1)
}
MainActor.assumeIsolated {  // top-level code of an executable runs on the main thread
    launch(fullScreen: flags.contains("--fullscreen"), cellSize: cellSize) { cols, rows in  // R-U2
        Session(cols: cols, rows: rows, playFile: file, shuffle: flags.contains("--shuffle"),
                initialDelay: Session.initialDelay * Double(cellSize) / 4)  // R-U5
    }
}
