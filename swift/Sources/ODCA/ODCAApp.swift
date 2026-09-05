import SwiftUI
import ODCAKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched via `swift run` (no app bundle): become a
        // regular, focusable app and take the foreground.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {  // the window exists by now (R-U2, R-U8)
            for window in NSApp.windows {
                window.contentResizeIncrements = NSSize(width: ViewerModel.cellSize, height: ViewerModel.cellSize)
                window.collectionBehavior.insert(.fullScreenPrimary)
                window.setFrameAutosaveName("ODCA main window")
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

@main
struct ODCAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView(model: ViewerModel.shared)
        }
        .defaultSize(width: CGFloat(ViewerModel.defaultCols * ViewerModel.cellSize),
                     height: CGFloat(ViewerModel.defaultRows * ViewerModel.cellSize))
    }
}
