import Foundation

/// Shared command-line handling for every program (R-U9, R-W1, R-X1, R-E1):
/// `--help` prints and exits before anything else; the positional
/// arguments are files, exactly one or, with `many`, one or more, in
/// order; none, or too many, and unknown options are usage errors (exit
/// 2). `options` take the next argument as their value; one without a
/// value is a usage error.
public func parseArguments(program: String, help: String, flags: [String] = [], options: [String] = [],
                           positional: String = "<file.odca>", many: Bool = false)
    -> (files: [URL], flags: Set<String>, options: [String: String]) {
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
    guard !files.isEmpty, files.count == 1 || many else {
        let usage = flags.map { " [\($0)]" }.joined() + options.map { " [\($0) N]" }.joined()
        print("usage: \(program) \(positional)\(usage)")
        exit(2)
    }
    return (files.map { URL(fileURLWithPath: $0) }, given, values)
}

/// A whole number of `unit` given to `option`, at least `minimum`, or
/// `default`; with no default the option is required (R-X2, R-X3, R-E1).
/// Anything else is a usage error (exit 2).
public func wholeNumber(program: String, options: [String: String], _ option: String,
                        unit: String, minimum: Int = 1, default value: Int? = nil) -> Int {
    guard let text = options[option] else {
        if let value = value { return value }
        print("\(program): \(option) is required")
        exit(2)
    }
    guard let n = Int(text), n >= minimum, text.allSatisfy(\.isNumber) else {
        let floor = minimum > 1 ? " (\(minimum) or more)" : ""
        print("\(program): \(option) needs a whole number of \(unit)\(floor)")
        exit(2)
    }
    return n
}

/// A positive whole number of seconds given to `option`, or `default` (R-X2, R-X3).
public func wholeSeconds(program: String, options: [String: String], _ option: String, default value: Double) -> Double {
    Double(wholeNumber(program: program, options: options, option, unit: "seconds", default: Int(value)))
}

/// The cell size flags (R-U2), accepted by both programs.
public let cellFlags = ["--4", "--3", "--2", "--1"]

/// Points per cell for this run: 4 unless one cell flag says otherwise;
/// more than one is a usage error (exit 2).
public func chooseCellSize(program: String, flags: Set<String>) -> Int {
    let chosen = cellFlags.filter { flags.contains($0) }
    guard chosen.count <= 1 else {
        print("\(program): choose one of \(cellFlags.joined(separator: ", "))")
        exit(2)
    }
    return chosen.first.map { Int($0.dropFirst(2))! } ?? 2  // R-U2: 2-point cells by default
}
