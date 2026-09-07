import AppKit
import ODCAKit

/// Shared command-line handling for odca and odca-select (R-U9, R-W1, R-X1):
/// `--help` prints and exits before anything else; the one positional
/// argument is the odca file; unknown options and a missing file argument
/// are usage errors (exit 2). `options` take the next argument as their
/// value; one without a value is a usage error.
public func parseArguments(program: String, help: String, flags: [String] = [], options: [String] = [])
    -> (file: URL, flags: Set<String>, options: [String: String]) {
    setlinebuf(stdout)  // status lines (R-O) arrive promptly even when piped or logged
    let args = Array(CommandLine.arguments.dropFirst())
    if args.contains("--help") {
        print(help, terminator: "")
        exit(0)
    }
    var given = Set<String>()
    var values: [String: String] = [:]
    var files: [String] = []
    var i = 0
    while i < args.count {
        let a = args[i]
        if flags.contains(a) {
            given.insert(a)
        } else if options.contains(a) {
            guard i + 1 < args.count, !args[i + 1].hasPrefix("-") else {
                print("\(program): \(a) needs a value")
                exit(2)
            }
            values[a] = args[i + 1]
            i += 1
        } else if a.hasPrefix("-") {
            print("\(program): unknown option \(a)")
            exit(2)
        } else {
            files.append(a)
        }
        i += 1
    }
    guard files.count == 1 else {
        let usage = flags.map { " [\($0)]" }.joined() + options.map { " [\($0) N]" }.joined()
        print("usage: \(program) <file.odca>\(usage)")
        exit(2)
    }
    return (URL(fileURLWithPath: files[0]), given, values)
}

/// A positive whole number of seconds given to `option`, or `default` (R-X2, R-X3).
public func wholeSeconds(program: String, options: [String: String], _ option: String, default value: Double) -> Double {
    guard let text = options[option] else { return value }
    guard let n = Int(text), n >= 1, text.allSatisfy(\.isNumber) else {
        print("\(program): \(option) needs a whole number of seconds")
        exit(2)
    }
    return Double(n)
}

/// The cell size flags (R-U2), accepted by both programs.
public let cellFlags = ["--4", "--2", "--1"]

/// Points per cell for this run: 4 unless one cell flag says otherwise;
/// more than one is a usage error (exit 2).
public func chooseCellSize(program: String, flags: Set<String>) -> Int {
    let chosen = cellFlags.filter { flags.contains($0) }
    guard chosen.count <= 1 else {
        print("\(program): choose one of \(cellFlags.joined(separator: ", "))")
        exit(2)
    }
    return chosen.first.map { Int($0.dropFirst(2))! } ?? 4
}

/// Open the window on a session built by `make` (called once, on the main
/// actor, with the default geometry) and run the app until it quits.
/// `fullScreen` opens the window full screen at launch (`--fullscreen`, R-U2);
/// `cellSize` is the points per cell for the run (`--4` / `--2` / `--1`).
@MainActor
public func launch(fullScreen: Bool = false, cellSize: Int = 4,
                   _ make: @escaping (_ cols: Int, _ rows: Int) -> Session) {
    ViewerModel.cellSize = cellSize
    ViewerModel.bootstrap { make(ViewerModel.defaultCols, ViewerModel.defaultRows) }
    AppDelegate.fullScreenAtLaunch = fullScreen
    // AppKit treats unknown command-line arguments as documents to open, and
    // SwiftUI then shows no default window (it expects a DocumentGroup to
    // take the file). Our argument is ours, not a document (3.0.0 shipped
    // without this and opened no window).
    UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])
    ODCAApp.main()
}
