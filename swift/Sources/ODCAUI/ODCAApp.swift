import SwiftUI
import ODCAKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `odca --fullscreen`: enter full screen as soon as the window exists (R-U2).
    nonisolated(unsafe) static var fullScreenAtLaunch = false
    private var observers: [Any] = []
    private var clickMonitor: Any?

    /// R-U12: a double-click on the title bar of a window that is not its
    /// natural size returns it there (top-left corner kept) instead of
    /// zooming; at its natural size the double-click zooms as ever.
    private func installTitleBarDoubleClick() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard event.clickCount == 2, let window = event.window,
                  !window.styleMask.contains(.fullScreen),
                  event.locationInWindow.y > window.contentLayoutRect.maxY,  // the title bar
                  let content = window.contentView?.frame.size else { return event }
            let natural = ViewerModel.naturalSize
            if abs(content.width - natural.width) < 0.5 && abs(content.height - natural.height) < 0.5 { return event }
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: natural))
            frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
            window.setFrame(frame, display: true, animate: true)
            return nil  // consumed: no zoom
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the pointer in full screen, show it again on exit (R-U2).
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main
        ) { _ in NSCursor.hide() })
        observers.append(center.addObserver(
            forName: NSWindow.willExitFullScreenNotification, object: nil, queue: .main
        ) { _ in NSCursor.unhide() })
        // Needed when launched via `swift run` (no app bundle): become a
        // regular, focusable app and take the foreground.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        installTitleBarDoubleClick()
        DispatchQueue.main.async {  // the window exists by now (R-U2, R-U8)
            for window in NSApp.windows {
                if ViewerModel.fixedCols == nil {  // R-X8: a scaled grid needs no snapping
                    window.contentResizeIncrements = NSSize(width: ViewerModel.cellSize, height: ViewerModel.cellSize)
                }
                window.collectionBehavior.insert(.fullScreenPrimary)
                if let cols = ViewerModel.fixedCols {  // R-X8: a fixed-width window opens at its width every time
                    // SwiftUI restores the last run's frame on its own, so the
                    // width is set outright; the restored height stays.
                    let content = window.contentView?.frame.size ?? NSSize(width: 0, height: 800)
                    window.setContentSize(NSSize(width: CGFloat(cols * ViewerModel.cellSize), height: content.height))
                } else {
                    window.setFrameAutosaveName("ODCA main window")
                }
                if AppDelegate.fullScreenAtLaunch { window.toggleFullScreen(nil) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true  // closing the window quits (R-U7)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in ViewerModel.shared.shutDown() }
    }
}

/// Hosts the display-link-driven AutomatonView inside SwiftUI.
struct AutomatonViewRepresentable: NSViewRepresentable {
    let model: ViewerModel

    func makeNSView(context: Context) -> AutomatonView { AutomatonView(model: model) }
    func updateNSView(_ view: AutomatonView, context: Context) {}
}

struct ContentView: View {
    @ObservedObject var model: ViewerModel

    var body: some View {
        AutomatonViewRepresentable(model: model)
            .frame(minWidth: 160, minHeight: 120)  // 40 x 30 cells at least (R-U2)
            .navigationTitle(model.title)
    }
}

/// The SwiftUI app; `launch` (Launch.swift) bootstraps the model and calls `main()`.
public struct ODCAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView(model: ViewerModel.shared)
        }
        .defaultSize(width: CGFloat(ViewerModel.defaultCols * ViewerModel.cellSize),
                     height: CGFloat(ViewerModel.defaultRows * ViewerModel.cellSize))
    }
}
