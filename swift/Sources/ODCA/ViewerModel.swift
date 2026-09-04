import AppKit
import CoreGraphics
import ODCAKit

/// UI-side model: owns the Session, paces it with a 60 Hz timer, renders
/// the history into a CGImage, and translates NSEvent keys to Session keys.
@MainActor
final class ViewerModel: ObservableObject {
    static let shared = ViewerModel()

    static let cellSize = 4
    static let cols = 1200 / cellSize
    static let rows = 800 / cellSize

    let session: Session
    @Published var frame: CGImage?
    @Published var scrollOffset = 0.0  // cells, see Session.scrollOffset (R-U3)
    @Published var title = "ODCA"

    private var timer: Timer?
    private var keyMonitor: Any?
    private var lastTick = Date()

    private init() {
        session = Session(cols: Self.cols, rows: Self.rows)
        session.startSearch()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, let key = Self.mapKey(event) else { return event }
            if !self.session.handleKey(key) {
                self.shutDown()
                NSApp.terminate(nil)
            }
            return nil  // consumed
        }

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.frameTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func shutDown() {
        timer?.invalidate()
        session.stopSearch()
    }

    private func frameTick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        session.tick(dt)
        frame = renderImage()
        scrollOffset = session.scrollOffset
        title = "ODCA — rule \(session.ruleID)"  // R-U6
    }

    /// R-U3: the image is one row taller than the window (rows + 1); the
    /// view scrolls it up by scrollOffset cells. Filled rows from the top,
    /// state-0 background below until the buffer fills.
    private func renderImage() -> CGImage? {
        let cols = Self.cols
        let rows = Self.rows + 1
        let palette = session.palette  // arranged colors of the active set (R-U4)
        let background = palette[0]
        var pixels = [UInt8](repeating: 0, count: rows * cols * 4)
        let history = session.history
        for row in 0..<rows {
            let cells: [UInt8]? = row < history.count ? history[row] : nil
            for col in 0..<cols {
                let color = cells.map { palette[Int($0[col])] } ?? background
                let base = (row * cols + col) * 4
                pixels[base] = color.r
                pixels[base + 1] = color.g
                pixels[base + 2] = color.b
                pixels[base + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }
        return CGImage(
            width: cols, height: rows, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: cols * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)
    }

    private static func mapKey(_ event: NSEvent) -> Session.Key? {
        if event.modifierFlags.contains(.command) { return nil }  // let Cmd-… pass
        switch event.keyCode {
        case 36, 76: return .ret  // Return, keypad Enter (R-K11)
        case 69: return .plus  // keypad +
        case 78: return .minus  // keypad -
        default: break
        }
        guard let chars = event.charactersIgnoringModifiers, let ch = chars.first
        else { return nil }
        switch ch {
        case "q": return .q
        case "r": return .r
        case "m": return .m
        case "u": return .u
        case "s": return .s
        case "i": return .i
        case "n": return .n
        case "p": return .p
        case "a": return .a
        case "c": return .c
        case "C": return .C  // shift-c (R-K15)
        case "S": return .S  // shift-s (R-K16)
        case "+", "=": return .plus  // '=' is unshifted '+' on US layouts (R-K8)
        case "-": return .minus
        case " ": return .space
        case "0"..."9": return .digit(ch.wholeNumberValue!)
        default: return nil
        }
    }
}
