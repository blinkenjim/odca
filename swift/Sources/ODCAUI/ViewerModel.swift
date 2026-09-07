import AppKit
import CoreGraphics
import ODCAKit

/// UI-side model: owns the Session, renders the history into a CGImage,
/// and translates NSEvent keys to Session keys. Pacing comes from the
/// display link in AutomatonView, which calls frameTick(dt:) once per
/// screen refresh with the true frame interval.
@MainActor
public final class ViewerModel: ObservableObject {
    /// How to build the session, handed over by `launch` before the app
    /// starts (R-U1). The model and its session are created lazily, on the
    /// first access from the SwiftUI scene, once NSApplication is running:
    /// the model installs a key monitor, and the session starts the search
    /// workers, neither of which belongs before launch.
    private static var pendingMake: (() -> Session)?
    static let shared = ViewerModel(session: pendingMake!())

    public static func bootstrap(make: @escaping () -> Session) {
        pendingMake = make
    }

    public static var cellSize = 4  // points per cell, set by `launch` before the window exists (R-U2)
    public static var defaultCols: Int { 1200 / cellSize }
    public static var defaultRows: Int { 800 / cellSize }
    var cols: Int { session.cols }
    var rows: Int { session.rows }

    let session: Session
    private(set) var frame: CGImage?
    private(set) var scrollOffset = 0.0  // cells, see Session.scrollOffset (R-U3)
    @Published var title = "ODCA"

    private var keyMonitor: Any?

    private init(session: Session) {
        self.session = session
        session.startSearch()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self else { return event }
            if Self.isFullScreenKey(event) {  // R-K18: a window key, live in every mode and while paused
                (event.window ?? NSApp.keyWindow)?.toggleFullScreen(nil)
                return nil
            }
            guard let key = Self.mapKey(event) else { return event }
            if !self.session.handleKey(key) {
                self.shutDown()
                NSApp.terminate(nil)
            }
            return nil  // consumed
        }
    }

    /// The window's content area changed (R-U8).
    func resize(cols: Int, rows: Int) {
        session.resize(cols: cols, rows: rows)
    }

    func shutDown() {
        session.finish()  // odca-select writes its file; review saves (R-V5)
        session.stopSearch()
    }

    /// Re-render the current state without advancing (used during a live
    /// resize, when the animation and its computation are frozen, R-U8).
    func renderOnly() {
        frame = renderImage()
        scrollOffset = session.scrollOffset
    }

    /// One display refresh: advance the session by the elapsed frame time,
    /// then render (R-U5).
    func frameTick(dt: Double) {
        session.tick(dt)
        frame = renderImage()
        scrollOffset = session.scrollOffset
        let newTitle = "ODCA — rule \(session.ruleID)"  // R-U6
        if newTitle != title { title = newTitle }
    }

    /// R-U3/R-U8: the image is one row taller than the window (rows + 1) and
    /// shows the last rows + 1 remembered rows; the view scrolls it up by
    /// scrollOffset cells. Filled rows from the top, state-0 background
    /// below until the buffer fills.
    private func renderImage() -> CGImage? {
        let cols = session.cols
        let rows = session.rows + 1
        var palette = session.paletteTable  // (palette, state) -> RGB (R-U4, R-X5)
        var background = session.palette[0]
        if session.inverted {  // R-U10: a brief inversion as a mode cue
            let invert = { (c: RGB) in RGB(r: 255 - c.r, g: 255 - c.g, b: 255 - c.b) }
            palette = palette.map(invert)
            background = invert(background)
        }
        let palettes = session.rowPalettes
        var pixels = [UInt8](repeating: 0, count: rows * cols * 4)
        let history = session.history
        let start = session.visibleStart
        for row in 0..<rows {
            let index = start + row
            let cells: [UInt8]? = index < history.count ? history[index] : nil
            let base4 = index < palettes.count ? Int(palettes[index]) * 4 : 0
            for col in 0..<cols {
                let color = cells.map { palette[base4 + Int($0[col])] } ?? background
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

    private static func isFullScreenKey(_ event: NSEvent) -> Bool {
        !event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "F"  // shift-f
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
        case "N": return .N  // review: next (R-V3)
        case "P": return .P  // review: previous
        case "X": return .X  // review: drop (R-V4, R-W5)
        case "R": return .R  // odca-select: toggle the n/p order (R-W7)
        case "[": return .poolPrev  // previous pool set (R-K17)
        case "]": return .poolNext  // next pool set (R-K17)
        case "+", "=": return .plus  // '=' is unshifted '+' on US layouts (R-K8)
        case "-": return .minus
        case " ": return .space
        case "0"..."9": return .digit(ch.wholeNumberValue!)
        default: return nil
        }
    }
}

/// The automaton display: a layer-backed NSView paced by a CADisplayLink,
/// so frames are phase-locked to the screen's refresh (60 or 120 Hz) and
/// dt is the true frame interval. The image layer is one row taller than
/// the view and is slid up by the scroll offset (R-U3); the view clips.
@MainActor
final class AutomatonView: NSView {
    private let model: ViewerModel
    private let gridLayer = CALayer()  // clips the grid; margins show the view's background
    private let imageLayer = CALayer()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    init(model: ViewerModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .nearest  // crisp cells, no smoothing
        imageLayer.minificationFilter = .nearest
        gridLayer.masksToBounds = true
        gridLayer.addSublayer(imageLayer)
        layer?.addSublayer(gridLayer)
    }

    /// R-U8: the grid follows the view — as many whole cells as fit.
    override func layout() {
        super.layout()
        let cell = CGFloat(ViewerModel.cellSize)
        model.resize(cols: Int(bounds.width / cell), rows: Int(bounds.height / cell))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }  // y grows downward, like the history

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(refresh(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        lastTimestamp = nil  // the frozen interval must not be caught up (R-U8)
    }

    @objc private func refresh(_ link: CADisplayLink) {
        if inLiveResize {
            model.renderOnly()  // frozen while the window is being resized (R-U8)
        } else {
            let dt = lastTimestamp.map { link.timestamp - $0 } ?? 0
            lastTimestamp = link.timestamp
            model.frameTick(dt: dt)
        }
        let cell = CGFloat(ViewerModel.cellSize)
        let gridW = CGFloat(model.cols) * cell, gridH = CGFloat(model.rows) * cell
        let bg = model.session.palette[0]
        CATransaction.begin()
        CATransaction.setDisableActions(true)  // no implicit animation of the slide
        layer?.backgroundColor = CGColor(
            red: CGFloat(bg.r) / 255, green: CGFloat(bg.g) / 255, blue: CGFloat(bg.b) / 255, alpha: 1)
        // Center the grid; leftover points become margins in the background color (R-U2).
        gridLayer.frame = CGRect(
            x: floor((bounds.width - gridW) / 2), y: floor((bounds.height - gridH) / 2),
            width: gridW, height: gridH)
        imageLayer.contents = model.frame
        imageLayer.frame = CGRect(
            x: 0, y: -CGFloat(model.scrollOffset) * cell,
            width: gridW, height: CGFloat(model.rows + 1) * cell)
        CATransaction.commit()
    }
}
