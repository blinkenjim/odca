import SwiftUI
import ODCAKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `odca --fullscreen`: enter full screen as soon as the window exists (R-U2).
    nonisolated(unsafe) static var fullScreenAtLaunch = false
    private var observers: [Any] = []

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
        DispatchQueue.main.async {  // the window exists by now (R-U2, R-U8)
            for window in NSApp.windows {
                window.contentResizeIncrements = NSSize(width: ViewerModel.cellSize, height: ViewerModel.cellSize)
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
