import Foundation

/// Standard output with one line that is redrawn in place (R-O17): the
/// `--longest` generation counter on a terminal. Any ordinary line clears
/// it first, so the two never collide; when standard output is not a
/// terminal the in-place line is not shown at all. Main thread only.
public final class TerminalStatus {
    public static let shared = TerminalStatus()
    public let terminal = isatty(1) != 0
    private var shown = false

    private init() {}

    /// Print a line, clearing the in-place line if one is showing.
    public func line(_ text: String) {
        if shown {
            print("\r\u{1B}[K", terminator: "")
            shown = false
        }
        print(text)
    }

    /// Draw the in-place line (a terminal only): carriage return, erase to
    /// the end of the line, the text, no newline.
    public func show(_ text: String) {
        guard terminal else { return }
        print("\r\u{1B}[K" + text, terminator: "")
        fflush(stdout)
        shown = true
    }
}
