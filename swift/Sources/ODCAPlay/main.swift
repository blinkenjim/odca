// odca: play the looks of an odca file (REQTS section 4d).
import Foundation
import ODCAKit
import ODCAUI

let (file, flags) = parseArguments(program: "odca", help: helpOdca, flags: ["--shuffle"])
guard FileManager.default.fileExists(atPath: file.path) else {  // R-X1: the file must exist
    print("error: \(file.path) does not exist")
    exit(1)
}
MainActor.assumeIsolated {  // top-level code of an executable runs on the main thread
    launch { cols, rows in
        Session(cols: cols, rows: rows, playFile: file, shuffle: flags.contains("--shuffle"))
    }
}
