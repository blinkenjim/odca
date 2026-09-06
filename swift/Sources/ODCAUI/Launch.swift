import AppKit
import ODCAKit

/// Shared command-line handling for odca and odca-select (R-U9, R-W1, R-X1):
/// `--help` prints and exits before anything else; the one positional
/// argument is the odca file; unknown options and a missing file argument
/// are usage errors (exit 2).
public func parseArguments(program: String, help: String, flags: [String] = []) -> (file: URL, flags: Set<String>) {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.contains("--help") {
        print(help, terminator: "")
        exit(0)
    }
    var given = Set<String>()
    var files: [String] = []
    for a in args {
        if flags.contains(a) {
            given.insert(a)
        } else if a.hasPrefix("-") {
            print("\(program): unknown option \(a)")
            exit(2)
        } else {
            files.append(a)
        }
    }
    guard files.count == 1 else {
        let usage = flags.isEmpty ? "" : " [" + flags.joined(separator: "] [") + "]"
        print("usage: \(program) <file.odca>\(usage)")
        exit(2)
    }
    return (URL(fileURLWithPath: files[0]), given)
}

/// Open the window on a session built by `make` (called once, on the main
/// actor, with the default geometry) and run the app until it quits.
@MainActor
public func launch(_ make: (_ cols: Int, _ rows: Int) -> Session) {
    ViewerModel.bootstrap(session: make(ViewerModel.defaultCols, ViewerModel.defaultRows))
    ODCAApp.main()
}
