import CShow
import Foundation

/// One command-line file's contribution to a show (R-X1): the pairs a play
/// script or odca file plays, in order.
public struct Segment: Equatable {
    public let file: String
    public let pairs: [Pair]

    public init(file: String, pairs: [Pair]) {
        self.file = file
        self.pairs = pairs
    }
}

/// A script or file that cannot be played; the message is for the user.
public struct ShowError: Error, Equatable, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// A play script statement (R-X7).
public enum Statement: Equatable {
    case `import`(line: Int, file: String)
    case play(line: Int)
}

/// Play scripts (R-X7) and the show odca plays (R-X1). The parser is one C
/// program shared by every implementation (script/show.l, script/show.y;
/// the generated C is the CShow target). It turns a script into JSON; this
/// resolves the imports and hands odca its show, one segment per file.
public enum Show {
    /// The parser's own JSON for a script (R-X7), byte for byte.
    public static func parseJSON(_ text: String) -> String {
        let p = show_parse(text)!
        defer { show_free(p) }
        return String(cString: p)
    }

    /// A script's statements, or ShowError("line:column: message") at the first error.
    public static func parse(_ text: String) throws -> [Statement] {
        let root = try JSONSerialization.jsonObject(with: Data(parseJSON(text).utf8)) as! [String: Any]
        guard root["ok"] as? Bool == true else {
            throw ShowError("\(root["line"] as! Int):\(root["column"] as! Int): \(root["message"] as! String)")
        }
        return (root["statements"] as! [[String: Any]]).map { s in
            if let file = s["import"] as? String { return .import(line: s["line"] as! Int, file: file) }
            return .play(line: s["line"] as! Int)
        }
    }

    private static func isOdcaFile(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return root["pairs"] != nil || root["looks"] != nil
    }

    /// The pairs a script plays (R-X7), in import order: every pair of every
    /// imported odca file, or none when the script never says `play`.
    /// Imports are relative to the script's directory. Messages name the
    /// script as it was given (a relative path stays relative, as in Python).
    public static func loadScript(_ url: URL) throws -> [Pair] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw ShowError("\(url.relativePath): cannot read")
        }
        let statements: [Statement]
        do { statements = try parse(text) } catch let e as ShowError { throw ShowError("\(url.relativePath):\(e)") }
        var pairs: [Pair] = []
        var plays = false
        for statement in statements {
            switch statement {
            case .import(let line, let name):
                let target = url.deletingLastPathComponent().appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: target.path) else {
                    throw ShowError("\(url.relativePath):\(line): cannot read \(name)")
                }
                guard isOdcaFile(target) else { throw ShowError("\(url.relativePath):\(line): \(name) is not an odca file") }
                pairs += Store.loadOdcaFile(target) ?? []
            case .play:
                plays = true
            }
        }
        return plays ? pairs : []
    }

    /// The show for odca's command line (R-X1): one segment per file, in
    /// the order given. A `.odca` file is its own script: import it, play
    /// it. Anything else is a play script.
    public static func load(_ files: [URL]) throws -> [Segment] {
        try files.map { file in
            if file.pathExtension == "odca" {
                guard let pairs = Store.loadOdcaFile(file) else { throw ShowError("\(file.relativePath): cannot read") }
                return Segment(file: file.lastPathComponent, pairs: pairs)
            }
            return Segment(file: file.lastPathComponent, pairs: try loadScript(file))
        }
    }
}
